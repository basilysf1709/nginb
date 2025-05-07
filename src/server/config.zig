const std = @import("std");
const mem = std.mem;
const fs = std.fs; // For potential future file reading

// Step 1: Create basic config structure
pub const Config = struct {
    worker_count: u32,
    listen_address: []const u8, // This slice will point to memory allocated by loadFromFile
    listen_port: u16,
    root_path: []const u8, // This slice will point to memory allocated by loadFromFile

    // It's good practice to have a deinit if the struct allocates memory
    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.listen_address);
        allocator.free(self.root_path);
        self.* = undefined; // Optional: zero out the struct after freeing
    }

    // Dummy error for parsing
    const ParseError = error{
        InvalidFormat,
        MissingField,
        OutOfMemory,
        FileNotFound, // If we were reading a real file
    };

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        std.debug.print("Attempting to load config from path: {s}\n", .{path});

        // In a real scenario, you would read the file content from 'path'
        // For this dummy version, we'll use a hardcoded string
        // that vaguely resembles the JSON structure from info.txt
        const dummy_file_content =
            \\{
            \\  "worker_count": 8,
            \\  "listen_address": "127.0.0.1",
            \\  "listen_port": 8888,
            \\  "root_path": "/var/www/html"
            \\}
        ;

        // --- Super Simple Dummy Parsing Logic ---
        // This is NOT robust JSON parsing. It's just to use the parameters.
        var worker_count: u32 = 4; // Default
        var listen_address_str: []const u8 = "0.0.0.0"; // Default
        var listen_port: u16 = 8080; // Default
        var root_path_str: []const u8 = "./public"; // Default

        var lines = mem.tokenizeScalar(u8, dummy_file_content, '\n');
        while (lines.next()) |line| {
            const trimmed_line = mem.trim(u8, line, " \t,");
            if (mem.startsWith(u8, trimmed_line, "\"worker_count\"")) {
                // Extremely naive parsing
                const value_part = mem.splitScalar(u8, trimmed_line, ':').rest;
                const num_str = mem.trim(u8, value_part, " ");
                worker_count = std.fmt.parseInt(u32, num_str, 10) catch 4;
            } else if (mem.startsWith(u8, trimmed_line, "\"listen_address\"")) {
                const value_part = mem.splitScalar(u8, trimmed_line, ':').rest;
                const str_val = mem.trim(u8, value_part, " \"");
                listen_address_str = str_val; // This slice points into dummy_file_content
            } else if (mem.startsWith(u8, trimmed_line, "\"listen_port\"")) {
                const value_part = mem.splitScalar(u8, trimmed_line, ':').rest;
                const num_str = mem.trim(u8, value_part, " ");
                listen_port = std.fmt.parseInt(u16, num_str, 10) catch 8080;
            } else if (mem.startsWith(u8, trimmed_line, "\"root_path\"")) {
                const value_part = mem.splitScalar(u8, trimmed_line, ':').rest;
                const str_val = mem.trim(u8, value_part, " \"");
                root_path_str = str_val; // This slice points into dummy_file_content
            }
        }
        // --- End Super Simple Dummy Parsing Logic ---

        // Allocate memory for the strings that the Config struct will hold.
        // allocator.dupe makes a copy.
        const final_listen_address = try allocator.dupe(u8, listen_address_str);
        errdefer allocator.free(final_listen_address);

        const final_root_path = try allocator.dupe(u8, root_path_str);
        errdefer allocator.free(final_root_path);

        std.debug.print("Loaded dummy config: workers={d}, addr={s}, port={d}, root={s}\n", .{
            worker_count, final_listen_address, listen_port, final_root_path,
        });

        return Config{
            .worker_count = worker_count,
            .listen_address = final_listen_address,
            .listen_port = listen_port,
            .root_path = final_root_path,
        };
    }
};

// Example of how it might be used (and deinitialized)
// This would typically be in main.zig or similar
pub fn exampleUsage(allocator: std.mem.Allocator) !void {
    var config = try Config.loadFromFile(allocator, "conf/dummy.json");
    defer config.deinit(allocator);

    // ... use config ...
    std.debug.print("Using config: workers = {d}\n", .{config.worker_count});
}
