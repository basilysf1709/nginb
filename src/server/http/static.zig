const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const path_mod = std.Path; // Using std.Path for consistency
const config_mod = @import("../config.zig"); // Assuming Config is needed for root_path
const request_mod = @import("./request.zig");
const response_mod = @import("./response.zig");
// const mime_mod = @import("../utils/mime.zig"); // For later MIME type detection

pub const StaticServerError = error{
    FileNotFound,
    PermissionDenied,
    IsDirectory, // If we don't want to serve directories (or list them)
    PathTraversalAttempt, // Basic security
    ReadError,
    WriteError,
    Internal,
};

// Basic security check: ensure the resolved path is still within the root directory.
// This is a VERY basic check and might not be sufficient for all cases.
fn isPathSafe(root_path: []const u8, full_path: []const u8) bool {
    // A more robust check would involve canonicalizing both paths
    // and then checking if full_path startsWith root_path.
    // For now, a simple check for ".." components that might escape.
    // This is NOT a complete security solution.
    if (mem.indexOf(u8, full_path, "..")) |_| {
        // Check if ".." actually leads out of root_path.
        // This requires proper path normalization which is complex.
        // For this basic version, we'll be very restrictive.
        // A better way is to use fs.realpath or similar and compare.
        // For now, if ".." exists and full_path doesn't start with root_path after some normalization...
        // This is still weak.
        // Let's rely on the fact that we join root_path + request.path
        // and then check if the result *starts* with root_path.
        // std.fs.path.resolve will handle ".." to some extent.
        return mem.startsWith(u8, full_path, root_path);
    }
    return mem.startsWith(u8, full_path, root_path);
}

pub fn serveFile(
    allocator: mem.Allocator,
    cfg: *const config_mod.Config,
    req: *const request_mod.Request,
    resp: *response_mod.Response,
    writer: anytype,
) !void {
    // 1. Construct the full file path
    // Basic path sanitization: disallow ".." to prevent traversal (very basic)
    if (mem.indexOf(u8, req.path[0..req.path_len], "..")) |_| {
        std.debug.print("Path traversal attempt: {s}\n", .{req.path[0..req.path_len]});
        try response_mod.Response.sendError(allocator, writer, .Forbidden, "Access denied: Invalid path.");
        return;
    }

    // Normalize requested path: ensure it starts with '/' and handle multiple slashes
    var path_buf = std.ArrayList(u8).init(allocator);
    defer path_buf.deinit();
    if (!mem.startsWith(u8, req.path[0..req.path_len], "/")) {
        try path_buf.append('/');
    }
    try path_buf.appendSlice(req.path[0..req.path_len]);

    const normalized_req_path = try path_buf.toOwnedSlice();
    defer allocator.free(normalized_req_path);

    // Now we can safely access normalized_req_path directly
    // If path is "/", serve "index.html"
    const actual_req_path = if (normalized_req_path.len == 1 and normalized_req_path[0] == '/')
        "/index.html"
    else
        normalized_req_path;

    var full_path_list = std.ArrayList(u8).init(allocator);
    defer full_path_list.deinit();
    try full_path_list.appendSlice(cfg.root_path);
    // Ensure root_path doesn't end with '/' if actual_req_path starts with '/'
    if (cfg.root_path[cfg.root_path.len - 1] == '/' and actual_req_path[0] == '/') {
        try full_path_list.appendSlice(actual_req_path[1..]);
    } else if (cfg.root_path[cfg.root_path.len - 1] != '/' and actual_req_path[0] != '/') {
        try full_path_list.append('/');
        try full_path_list.appendSlice(actual_req_path);
    } else {
        try full_path_list.appendSlice(actual_req_path);
    }
    const full_path = try full_path_list.toOwnedSlice();
    defer allocator.free(full_path);

    std.debug.print("Attempting to serve static file: {s} (from req path {s})\n", .{ full_path, req.path[0..req.path_len] });

    // Basic security: Check if the resolved path is still within the root.
    // This needs a much more robust implementation in a real server.
    // For now, we rely on the construction logic. A better way is to use
    // `fs.cwd().realpath(full_path, ...)` and compare with `fs.cwd().realpath(cfg.root_path, ...)`
    // This is a placeholder for a real security check.
    if (!mem.startsWith(u8, full_path, cfg.root_path)) {
        std.debug.print("Security alert: Path {s} resolved outside root {s}\n", .{ full_path, cfg.root_path });
        try response_mod.Response.sendError(allocator, writer, .Forbidden, "Access Denied.");
        return;
    }

    // 2. Open the file
    const file = fs.openFileAbsolute(full_path, .{}) catch |err| {
        std.debug.print("Failed to open file {s}: {any}\n", .{ full_path, err });
        switch (err) {
            error.FileNotFound => {
                try response_mod.Response.sendError(allocator, writer, .NotFound, "File not found.");
                return;
            },
            error.AccessDenied => {
                try response_mod.Response.sendError(allocator, writer, .Forbidden, "Access denied.");
                return;
            },
            else => {
                try response_mod.Response.sendError(allocator, writer, .InternalServerError, "Error accessing file.");
                return;
            },
        }
    };
    defer file.close();

    // 3. Get file stats (for content length and to check if it's a directory)
    const stat = file.stat() catch |err| {
        std.debug.print("Failed to stat file {s}: {any}\n", .{ full_path, err });
        try response_mod.Response.sendError(allocator, writer, .InternalServerError, "Error stating file.");
        return;
    };

    if (stat.kind == .directory) {
        // For now, don't serve directories. Could implement directory listing later.
        std.debug.print("Attempt to access directory: {s}\n", .{full_path});
        try response_mod.Response.sendError(allocator, writer, .Forbidden, "Access to directories is forbidden.");
        return;
    }

    // 4. Set headers (Content-Type, Content-Length)
    resp.setStatus(.Ok);
    // TODO: Implement MIME type detection based on file extension
    // const mime_type = mime_mod.getFromPath(full_path) orelse "application/octet-stream";
    // For now, hardcode based on common extensions for testing
    var content_type: []const u8 = "application/octet-stream";
    if (mem.endsWith(u8, full_path, ".html")) {
        content_type = "text/html; charset=utf-8";
    } else if (mem.endsWith(u8, full_path, ".css")) {
        content_type = "text/css; charset=utf-8";
    } else if (mem.endsWith(u8, full_path, ".js")) {
        content_type = "application/javascript; charset=utf-8";
    } else if (mem.endsWith(u8, full_path, ".txt")) {
        content_type = "text/plain; charset=utf-8";
    }
    try resp.setHeader("Content-Type", content_type);
    // Content-Length will be set by sendStream

    // 5. Stream the file content
    std.debug.print("Streaming file {s} ({d} bytes) with type {s}\n", .{ full_path, stat.size, content_type });
    try resp.sendStream(writer, fs.File.Reader, file.reader(), stat.size);
}
