const std = @import("std");
const mem = std.mem;
const net = std.net; // For StreamServer.Connection if needed by caller
const uri = std.Uri;

pub const RequestError = error{
    InvalidRequestLine,
    UnsupportedMethod,
    UriParseFailed,
    HeaderTooLarge,
    InvalidHeader,
    BodyTooLarge, // For future use
    UnexpectedEOF,
    SocketError,
};

pub const Method = enum {
    GET,
    POST, // Add other methods as needed
    // HEAD,
    // PUT,
    // DELETE,
    // ...
};

pub const Request = struct {
    allocator: mem.Allocator,
    method: Method,
    path: []const u8, // Owned by this struct
    // version: []const u8, // HTTP version, e.g., "HTTP/1.1", owned
    headers: std.StringHashMap([]const u8), // Headers, values owned

    // For simplicity, we'll parse only up to a certain number of headers
    // and a max line length for the request line and each header.
    const MAX_REQUEST_LINE_LEN = 2048;
    const MAX_HEADER_LINE_LEN = 2048;
    const MAX_HEADERS = 64;

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.path);
        // self.allocator.free(self.version);
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*); // Free the duplicated header value
        }
        self.headers.deinit();
        self.* = undefined;
    }

    // Parses a request from a connection stream.
    // The caller is responsible for closing the connection.stream.
    pub fn parse(
        allocator: mem.Allocator,
        reader: anytype, // e.g., net.StreamServer.Connection.stream.reader()
    ) !Request {
        var self = Request{
            .allocator = allocator,
            .method = undefined,
            .path = undefined,
            // .version = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
        errdefer self.deinit();

        var buf: [MAX_REQUEST_LINE_LEN]u8 = undefined;

        // 1. Parse Request Line (e.g., "GET /index.html HTTP/1.1")
        const request_line_raw = reader.readUntilDelimiterOrEof(&buf, '\n') catch |err| switch (err) {
            error.StreamTooLong => return RequestError.HeaderTooLarge, // Using HeaderTooLarge for request line too
            error.EndOfStream => return RequestError.UnexpectedEOF,
            else => |e| return e, // Propagate other stream errors
        };
        if (request_line_raw == null) return RequestError.UnexpectedEOF;
        const request_line = mem.trimRight(u8, request_line_raw.?, "\r");

        var parts = mem.splitScalar(u8, request_line, ' ');
        const method_str = parts.next() orelse return RequestError.InvalidRequestLine;
        const path_str_raw = parts.next() orelse return RequestError.InvalidRequestLine;
        // const version_str = parts.next() orelse return RequestError.InvalidRequestLine;

        // Parse Method
        if (mem.eql(u8, method_str, "GET")) {
            self.method = .GET;
        } else if (mem.eql(u8, method_str, "POST")) {
            self.method = .POST;
        } else {
            std.debug.print("Unsupported method: {s}\n", .{method_str});
            return RequestError.UnsupportedMethod;
        }

        // Parse Path (and potentially query params later)
        // For now, just duplicate the path string.
        // A proper URI parser should be used here (std.Uri.parse)
        const parsed_uri = uri.parse(path_str_raw) catch |err| {
            std.debug.print("Failed to parse URI '{s}': {any}\n", .{ path_str_raw, err });
            return RequestError.UriParseFailed;
        };
        self.path = try allocator.dupe(u8, parsed_uri.path orelse "/"); // Default to "/" if path is empty

        // self.version = try allocator.dupe(u8, version_str);

        // 2. Parse Headers
        var header_count: usize = 0;
        while (header_count < MAX_HEADERS) : (header_count += 1) {
            var header_buf: [MAX_HEADER_LINE_LEN]u8 = undefined;
            const header_line_raw = reader.readUntilDelimiterOrEof(&header_buf, '\n') catch |err| switch (err) {
                error.StreamTooLong => return RequestError.HeaderTooLarge,
                error.EndOfStream => break, // EOF might be fine after headers if no body
                else => |e| return e,
            };
            if (header_line_raw == null) break; // End of headers (or stream)

            const header_line = mem.trimRight(u8, header_line_raw.?, "\r");
            if (header_line.len == 0) {
                // Empty line signifies end of headers
                break;
            }

            const header_parts = mem.splitOnceScalar(u8, header_line, ':');
            if (header_parts == null) {
                std.debug.print("Invalid header line: {s}\n", .{header_line});
                return RequestError.InvalidHeader;
            }

            const name = mem.trim(u8, header_parts.?.before, " ");
            const value_trimmed = mem.trim(u8, header_parts.?.after, " ");
            const value_owned = try allocator.dupe(u8, value_trimmed);

            // Store header (lowercase name for case-insensitivity)
            // For simplicity, not lowercasing here, but good practice.
            try self.headers.put(name, value_owned);
        }

        // 3. Parse Body (TODO for POST, PUT, etc.)
        // For GET requests, we typically ignore the body or assume there isn't one.

        return self;
    }

    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        // Header names are case-insensitive in HTTP.
        // A real implementation should lowercase 'name' or store all header names lowercased.
        if (self.headers.get(name)) |value| {
            return value;
        }
        // Attempt to find with common capitalizations if not found directly (simple approach)
        if (name.len > 0) {
            var capitalized_name_buf: [64]u8 = undefined; // Adjust size as needed
            if (std.fmt.bufPrint(&capitalized_name_buf, "{u}{s}", .{ name[0], name[1..] })) |capitalized_name| {
                if (self.headers.get(capitalized_name)) |value_cap| return value_cap;
            }
        }
        return null;
    }
};
