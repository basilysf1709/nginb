const std = @import("std");
const mem = std.mem;
const net = std.net; // For StreamServer.Connection if needed by caller
const fs = std.fs; // For file streaming

pub const ResponseError = error{
    WriteFailed,
    HeaderTooLarge, // If we were to format headers into a buffer first
};

pub const StatusCode = enum(u16) {
    Ok = 200,
    Created = 201,
    Accepted = 202,
    NoContent = 204,

    MovedPermanently = 301,
    Found = 302,

    BadRequest = 400,
    Unauthorized = 401,
    Forbidden = 403,
    NotFound = 404,
    MethodNotAllowed = 405,

    InternalServerError = 500,
    NotImplemented = 501,
    BadGateway = 502,
    ServiceUnavailable = 503,

    // Helper to get the reason phrase
    pub fn reasonPhrase(self: StatusCode) []const u8 {
        return switch (self) {
            .Ok => "OK",
            .Created => "Created",
            .Accepted => "Accepted",
            .NoContent => "No Content",
            .MovedPermanently => "Moved Permanently",
            .Found => "Found",
            .BadRequest => "Bad Request",
            .Unauthorized => "Unauthorized",
            .Forbidden => "Forbidden",
            .NotFound => "Not Found",
            .MethodNotAllowed => "Method Not Allowed",
            .InternalServerError => "Internal Server Error",
            .NotImplemented => "Not Implemented",
            .BadGateway => "Bad Gateway",
            .ServiceUnavailable => "Service Unavailable",
        };
    }
};

pub const Response = struct {
    allocator: mem.Allocator,
    status: StatusCode,
    headers: std.StringHashMap([]const u8), // Header values are owned
    headers_sent: bool,

    pub fn init(allocator: mem.Allocator) Response {
        return Response{
            .allocator = allocator,
            .status = .Ok, // Default status
            .headers = std.StringHashMap([]const u8).init(allocator),
            .headers_sent = false,
        };
    }

    pub fn deinit(self: *Response) void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.* = undefined;
    }

    pub fn setStatus(self: *Response, status: StatusCode) void {
        self.status = status;
    }

    // Value will be duplicated
    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (self.headers.fetchPut(name, owned_value) catch @panic("Failed to put header")) |old_entry| {
            self.allocator.free(old_entry.value); // Free old value if replacing
        }
    }

    fn sendHeaders(self: *Response, writer: anytype) !void {
        if (self.headers_sent) return;

        try writer.print("HTTP/1.1 {d} {s}\r\n", .{
            @intFromEnum(self.status),
            self.status.reasonPhrase(),
        });

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeAll("\r\n");
        self.headers_sent = true;
    }

    pub fn send(self: *Response, writer: anytype, body: []const u8) !void {
        if (!self.headers.contains("Content-Length")) {
            const content_length_str = try std.fmt.allocPrint(self.allocator, "{d}", .{body.len});
            defer self.allocator.free(content_length_str);
            try self.setHeader("Content-Length", content_length_str);
        }
        try self.sendHeaders(writer);
        try writer.writeAll(body);
    }

    // For sending larger content, like files, without loading all into memory
    pub fn sendStream(self: *Response, writer: anytype, comptime R: type, stream_reader: R, content_length: u64) !void {
        if (!self.headers.contains("Content-Length")) {
            const content_length_str = try std.fmt.allocPrint(self.allocator, "{d}", .{content_length});
            defer self.allocator.free(content_length_str);
            try self.setHeader("Content-Length", content_length_str);
        }
        try self.sendHeaders(writer);

        var buffer: [4096]u8 = undefined;
        var total_sent: u64 = 0;
        while (total_sent < content_length) {
            const bytes_to_read = @min(buffer.len, content_length - total_sent);
            const bytes_read = try stream_reader.read(buffer[0..bytes_to_read]);
            if (bytes_read == 0) break; // EOF

            try writer.writeAll(buffer[0..bytes_read]);
            total_sent += bytes_read;
        }
    }

    // Convenience for sending simple text/html error pages
    pub fn sendError(
        allocator: mem.Allocator,
        writer: anytype,
        status: StatusCode,
        message: []const u8,
    ) !void {
        var error_response = Response.init(allocator);
        defer error_response.deinit();
        error_response.setStatus(status);
        try error_response.setHeader("Content-Type", "text/html; charset=utf-8");
        // In a real app, use an HTML template for errors
        const body = try std.fmt.allocPrint(allocator,
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head><meta charset="UTF-8"><title>{d} {s}</title></head>
            \\<body><h1>{d} {s}</h1><p>{s}</p></body>
            \\</html>
        , .{ @intFromEnum(status), status.reasonPhrase(), @intFromEnum(status), status.reasonPhrase(), message });
        defer allocator.free(body);

        try error_response.send(writer, body);
    }
};
