const std = @import("std");
const mem = std.mem;
const config_mod = @import("./server/config.zig");
const master_mod = @import("./server/master.zig");
const logger = @import("./server/utils/logger.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger (master process will do this before forking)
    // Workers will inherit the logger setup.
    // For file logging, ensure the path is correct and writable.
    // const log_file = try std.fs.cwd().createFile("server.log", .{ .truncate = false }); // Example: append to server.log
    // defer log_file.close();
    // logger.initGlobalLogger(allocator, .DEBUG, log_file.writer());
    // For now, simple stdout logging:
    logger.initGlobalLogger(allocator, .DEBUG, null); // Log to stdout/stderr
    defer logger.deinitGlobalLogger();

    logger.info("Application starting...", .{});

    // Load configuration
    const config = try config_mod.Config.loadFromFile(allocator, "conf/server.conf");
    // defer config.deinit(allocator); // Deinit of config might be handled by master or if it's just data, not strictly needed here

    // Initialize Master
    var master = try master_mod.Master.init(allocator, config);
    defer master.deinit(); // Master deinit will handle cleanup

    // Start Master (which now forks and manages workers)
    try master.start();

    logger.info("Application shutting down.", .{});
}
