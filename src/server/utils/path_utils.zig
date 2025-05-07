const std = @import("std");
const mem = std.mem;
const fs = std.fs; // For fs.path if needed, though std.Path is preferred

// Dummy path utility functions

/// Normalizes a path.
/// This is a very basic dummy:
/// - Replaces backslashes with forward slashes (for cross-platform conceptual consistency)
/// - Removes trailing slashes (unless it's just "/")
/// - Does NOT resolve ".." or "." or multiple slashes yet.
pub fn normalize(allocator: mem.Allocator, p: []const u8) ![]const u8 {
    if (p.len == 0) return try allocator.dupe(u8, "");

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit(); // Only deinit if an error occurs before toOwnedSlice

    for (p) |char| {
        if (char == '\\') {
            try result.append('/');
        } else {
            try result.append(char);
        }
    }

    // Remove trailing slash unless it's the only character
    while (result.items.len > 1 and result.items[result.items.len - 1] == '/') {
        _ = result.pop();
    }

    return result.toOwnedSlice();
}

/// Joins path components.
/// This is a very basic dummy:
/// - Ensures a single '/' between components.
/// - Does NOT handle absolute paths in `rest` intelligently yet.
pub fn join(allocator: mem.Allocator, base: []const u8, rest: []const u8) ![]const u8 {
    if (base.len == 0) return try allocator.dupe(u8, rest);
    if (rest.len == 0) return try allocator.dupe(u8, base);

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try result.appendSlice(base);

    const base_ends_with_slash = base[base.len - 1] == '/';
    const rest_starts_with_slash = rest[0] == '/';

    if (base_ends_with_slash and rest_starts_with_slash) {
        try result.appendSlice(rest[1..]);
    } else if (!base_ends_with_slash and !rest_starts_with_slash) {
        try result.append('/');
        try result.appendSlice(rest);
    } else {
        try result.appendSlice(rest);
    }

    return result.toOwnedSlice();
}

/// Basic security check for path traversal.
/// This is a VERY basic dummy and not a complete security solution.
/// It just checks for ".." components.
pub fn isSafe(p: []const u8) bool {
    if (mem.indexOf(u8, p, "..")) |_| {
        // A real check would normalize the path and ensure it doesn't go above a root.
        // For this dummy, any ".." is considered potentially unsafe.
        return false;
    }
    return true;
}

test "normalize path" {
    const allocator = std.testing.allocator;
    const n1 = try normalize(allocator, "/foo/bar/");
    defer allocator.free(n1);
    try std.testing.expectEqualStrings("/foo/bar", n1);

    const n2 = try normalize(allocator, "foo\\bar");
    defer allocator.free(n2);
    try std.testing.expectEqualStrings("foo/bar", n2);

    const n3 = try normalize(allocator, "/");
    defer allocator.free(n3);
    try std.testing.expectEqualStrings("/", n3);

    const n4 = try normalize(allocator, "");
    defer allocator.free(n4);
    try std.testing.expectEqualStrings("", n4);
}

test "join path" {
    const allocator = std.testing.allocator;
    const j1 = try join(allocator, "/foo", "bar");
    defer allocator.free(j1);
    try std.testing.expectEqualStrings("/foo/bar", j1);

    const j2 = try join(allocator, "/foo/", "/bar");
    defer allocator.free(j2);
    try std.testing.expectEqualStrings("/foo/bar", j2);

    const j3 = try join(allocator, "foo", "bar");
    defer allocator.free(j3);
    try std.testing.expectEqualStrings("foo/bar", j3);

    const j4 = try join(allocator, "/foo", "");
    defer allocator.free(j4);
    try std.testing.expectEqualStrings("/foo", j4);

    const j5 = try join(allocator, "", "bar");
    defer allocator.free(j5);
    try std.testing.expectEqualStrings("bar", j5);
}

test "isSafe path" {
    try std.testing.expect(isSafe("/foo/bar"));
    try std.testing.expect(!isSafe("/foo/../bar"));
    try std.testing.expect(!isSafe("../secret"));
}
