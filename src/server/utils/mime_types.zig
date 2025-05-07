const std = @import("std");
const mem = std.mem;
const path = std.fs.path;

// This is a very basic dummy implementation.
// A real implementation would use a HashMap or a more extensive list.

const default_mime_type = "application/octet-stream";

const known_mime_types = .{
    .{ ".html", "text/html; charset=utf-8" },
    .{ ".htm", "text/html; charset=utf-8" },
    .{ ".css", "text/css; charset=utf-8" },
    .{ ".js", "application/javascript; charset=utf-8" },
    .{ ".json", "application/json; charset=utf-8" },
    .{ ".xml", "application/xml; charset=utf-8" },
    .{ ".txt", "text/plain; charset=utf-8" },
    .{ ".jpg", "image/jpeg" },
    .{ ".jpeg", "image/jpeg" },
    .{ ".png", "image/png" },
    .{ ".gif", "image/gif" },
    .{ ".svg", "image/svg+xml" },
    .{ ".ico", "image/x-icon" },
    .{ ".webp", "image/webp" },
    .{ ".pdf", "application/pdf" },
    .{ ".zip", "application/zip" },
    .{ ".gz", "application/gzip" },
    .{ ".tar", "application/x-tar" },
    .{ ".mp3", "audio/mpeg" },
    .{ ".ogg", "audio/ogg" },
    .{ ".wav", "audio/wav" },
    .{ ".mp4", "video/mp4" },
    .{ ".webm", "video/webm" },
};

pub fn getFromPath(file_path: []const u8) []const u8 {
    const extension_with_dot = path.extension(file_path);

    if (extension_with_dot.len == 0) {
        return default_mime_type;
    }

    // In a real app, you'd want a case-insensitive comparison for the extension.
    // For this dummy, we'll assume lowercase.
    // const lower_ext = ...; // convert to lowercase

    for (known_mime_types) |entry| {
        if (mem.eql(u8, entry[0], extension_with_dot)) {
            return entry[1];
        }
    }

    return default_mime_type;
}

test "getMimeType" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", getFromPath("index.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", getFromPath("/static/style.css"));
    try std.testing.expectEqualStrings("image/jpeg", getFromPath("image.JPG")); // Dummy doesn't handle case
    try std.testing.expectEqualStrings("application/octet-stream", getFromPath("archive.dat"));
    try std.testing.expectEqualStrings("application/octet-stream", getFromPath("noextension"));
    try std.testing.expectEqualStrings("application/pdf", getFromPath("document.pdf"));
}
