const std = @import("std");
const io = std.io;
const fs = std.fs;
const time = std.time;
const mem = std.mem;

pub const LogLevel = enum {
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .DEBUG => "DEBUG",
            .INFO => "INFO",
            .WARN => "WARN",
            .ERROR => "ERROR",
            .FATAL => "FATAL",
        };
    }
};

// Basic logger struct (not thread-safe in this dummy version)
pub const Logger = struct {
    allocator: mem.Allocator,
    min_level: LogLevel,
    writer: ?std.io.Writer,

    // For simplicity, this dummy logger won't manage file opening/closing itself.
    // It expects a ready writer.
    pub fn init(allocator: mem.Allocator, min_level: LogLevel, writer: ?std.io.Writer) Logger {
        return Logger{
            .allocator = allocator,
            .min_level = min_level,
            .writer = writer,
        };
    }

    // Dummy deinit, in a real logger, you might close a file handle
    pub fn deinit(self: *Logger) void {
        // If self.writer was an owned resource (e.g. an opened file), close it here.
        // For this dummy version, we assume the writer is managed externally.
        self.* = undefined;
    }

    fn log(self: *const Logger, comptime level: LogLevel, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.min_level)) {
            return;
        }

        if (self.writer) |w| {
            // Basic timestamp (not fully featured)
            const now = time.timestamp();
            const datetime = time.epochToCalendar(now);

            // In a real logger, you'd handle writer errors
            w.print("[{04}-{:02}-{:02} {:02}:{:02}:{:02}] [{s}] ", .{
                datetime.year,
                datetime.month,
                datetime.day,
                datetime.hour,
                datetime.minute,
                datetime.second,
                level.toString(),
            }) catch return; // Ignore error for dummy

            w.print(format, args) catch return; // Ignore error for dummy
            w.print("\n", .{}) catch return; // Ignore error for dummy
        } else {
            // Fallback to std.debug.print if no writer
            std.debug.print("[{s}] ", .{level.toString()});
            std.debug.print(format, args);
            std.debug.print("\n", .{});
        }
    }

    pub fn debug(self: *const Logger, comptime format: []const u8, args: anytype) void {
        self.log(.DEBUG, format, args);
    }

    pub fn info(self: *const Logger, comptime format: []const u8, args: anytype) void {
        self.log(.INFO, format, args);
    }

    pub fn warn(self: *const Logger, comptime format: []const u8, args: anytype) void {
        self.log(.WARN, format, args);
    }

    pub fn e(self: *const Logger, comptime format: []const u8, args: anytype) void {
        self.log(.ERROR, format, args);
    }

    pub fn fatal(self: *const Logger, comptime format: []const u8, args: anytype) void {
        self.log(.FATAL, format, args);
        // In a real fatal, you might os.exit(1) or panic
    }
};

// Global dummy logger instance (not recommended for complex apps, but simple for now)
// You would typically pass a logger instance around or use a thread-local one.
var global_logger: Logger = undefined;
var global_logger_initialized: bool = false;

pub fn initGlobalLogger(allocator: mem.Allocator, min_level: LogLevel, writer: ?std.io.Writer) void {
    global_logger = Logger.init(allocator, min_level, writer);
    global_logger_initialized = true;
}

pub fn deinitGlobalLogger() void {
    if (global_logger_initialized) {
        global_logger.deinit();
        global_logger_initialized = false;
    }
}

pub fn getGlobalLogger() *Logger {
    if (!global_logger_initialized) {
        // Fallback if not initialized, prints to debug output
        // This is not ideal, proper initialization is key.
        // For this dummy, we'll just let it use std.debug.print via its internal fallback.
        // A better dummy might initialize a temporary stdout logger here.
        global_logger = Logger{
            .allocator = std.heap.c_allocator, // Or some other default
            .min_level = .INFO,
            .writer = null, // Will cause fallback to std.debug.print
        };
        // global_logger_initialized = true; // Don't mark as initialized if it's a fallback
    }
    return &global_logger;
}

// Convenience functions using the global logger
pub fn debug(comptime format: []const u8, args: anytype) void {
    getGlobalLogger().debug(format, args);
}
pub fn info(comptime format: []const u8, args: anytype) void {
    getGlobalLogger().info(format, args);
}
pub fn warn(comptime format: []const u8, args: anytype) void {
    getGlobalLogger().warn(format, args);
}
pub fn e(comptime format: []const u8, args: anytype) void {
    getGlobalLogger().e(format, args);
}
pub fn fatal(comptime format: []const u8, args: anytype) void {
    getGlobalLogger().fatal(format, args);
}
