const std = @import("std");
const io = std.io;
const fs = std.fs;
// const time = std.time; // We'll use ctime for timestamp string
const mem = std.mem;

// Import C's time.h
const ctime = @cImport({
    @cInclude("time.h");
    // Define _POSIX_C_SOURCE or similar if your time.h needs it for asctime_r/localtime_r
    // For basic asctime/localtime, it might not be needed.
    // e.g. @cDefine("_POSIX_C_SOURCE", "199309L");
});

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
    writer: ?std.fs.File.Writer,

    // For simplicity, this dummy logger won't manage file opening/closing itself.
    // It expects a ready writer.
    pub fn init(allocator: mem.Allocator, min_level: LogLevel, writer: ?std.fs.File.Writer) Logger {
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
            // Get current time using C functions
            var now_c: ctime.time_t = undefined;
            _ = ctime.time(&now_c); // Get current epoch time

            // Convert to local time structure
            // Using localtime_r for thread-safety if available and preferred.
            // Otherwise, localtime is simpler but not thread-safe without external locking.
            // For this example, let's try with localtime first.
            // If localtime_r is needed:
            // var timeinfo_s: ctime.struct_tm = undefined;
            // const timeinfo = ctime.localtime_r(&now_c, &timeinfo_s);
            const timeinfo_ptr = ctime.localtime(&now_c); // Returns a pointer to a static internal buffer

            if (timeinfo_ptr == null) {
                // Fallback or error logging if localtime fails
                w.print("[UNKNOWN_TIME] [{s}] ", .{level.toString()}) catch return;
            } else {
                // Format time using asctime or strftime
                // asctime produces a fixed format string: "Www Mmm dd hh:mm:ss yyyy\n"
                // We need to be careful with the newline from asctime.
                // strftime offers more control.
                // For simplicity with asctime, and removing its newline:
                var time_str_buffer: [26]u8 = undefined; // asctime format is 24 chars + null + potential newline

                // Using strftime for custom format "[YYYY-MM-DD HH:MM:SS]"
                const bytes_formatted = ctime.strftime(&time_str_buffer, time_str_buffer.len, "[%Y-%m-%d %H:%M:%S]", timeinfo_ptr);

                if (bytes_formatted == 0) {
                    // strftime failed or buffer too small
                    w.print("[FORMAT_TIME_ERR] [{s}] ", .{level.toString()}) catch return;
                } else {
                    w.print("{s} [{s}] ", .{ time_str_buffer[0..bytes_formatted], level.toString() }) catch return;
                }
            }

            w.print(format, args) catch return;
            w.print("\n", .{}) catch return;
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

pub fn initGlobalLogger(allocator: mem.Allocator, min_level: LogLevel, writer: ?std.fs.File.Writer) void {
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
