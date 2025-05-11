const std = @import("std");
const mem = std.mem;
const net = std.net; // For StreamServer.Connection if needed by caller
const uri = std.Uri;

pub const RequestError = error{
    InvalidRequestLine,
    UnsupportedMethod,
    PathTooLong,
    UnexpectedEOF,
};

pub const Method = enum { GET, POST };

pub const Request = struct {
    method: Method,
    path: [256]u8,
    path_len: usize,

    pub fn parse(reader: anytype) !Request {
        var buf: [1024]u8 = undefined;
        const line = reader.readUntilDelimiterOrEof(&buf, '\n') catch return RequestError.UnexpectedEOF;
        if (line == null) return RequestError.UnexpectedEOF;
        const request_line = mem.trimRight(u8, line.?, "\r");

        var parts = mem.splitScalar(u8, request_line, ' ');
        const method_str = parts.next() orelse return RequestError.InvalidRequestLine;
        const path_str_raw = parts.next() orelse return RequestError.InvalidRequestLine;

        var req = Request{
            .method = undefined,
            .path = undefined,
            .path_len = 0,
        };

        if (mem.eql(u8, method_str, "GET")) {
            req.method = .GET;
        } else if (mem.eql(u8, method_str, "POST")) {
            req.method = .POST;
        } else {
            return RequestError.UnsupportedMethod;
        }

        // Parse path (just copy, no URI parsing)
        const path_bytes = mem.trim(u8, path_str_raw, " \r\t");
        if (path_bytes.len > req.path.len) return RequestError.PathTooLong;
        @memcpy(req.path[0..path_bytes.len], path_bytes);
        req.path_len = path_bytes.len;

        return req;
    }
};
