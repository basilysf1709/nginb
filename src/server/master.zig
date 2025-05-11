const std = @import("std");
const posix = std.posix;
const mem = std.mem;
const time = std.time;
const config_mod = @import("./config.zig");
const worker_mod = @import("./worker.zig");
const logger = @import("./utils/logger.zig");
// const cq_module = @import("./utils/concurrent_queue.zig"); // No longer needed
// const net = std.net; // No longer directly used for listening by master

pub const MasterError = error{
    ForkFailed,
    SignalSetupFailed,
    // SocketBindFailed, // Master no longer binds/listens directly
    // SocketListenFailed,
    // AcceptFailed,
    // ThreadSpawnFailed, // Using processes now
    // OutOfMemory, // Still possible
    // QueueSendFailed, // No queue
};

// To store worker PIDs
const WorkerPidList = std.ArrayList(posix.pid_t);

// Global variable to indicate shutdown, for signal handler
var global_shutdown_requested: bool = false;

fn sigintTermHandler(signum: i32) callconv(.C) void {
    _ = signum;
    logger.info("Master: SIGINT/SIGTERM received, initiating shutdown...", .{});
    global_shutdown_requested = true;
}

pub const Master = struct {
    allocator: mem.Allocator,
    config: config_mod.Config,
    worker_pids: WorkerPidList,

    pub fn init(allocator: mem.Allocator, app_config: config_mod.Config) !Master {
        logger.info("Initializing master process...", .{});

        // Master no longer creates a listening socket itself.
        // Workers will do this.
        return Master{
            .allocator = allocator,
            .config = app_config,
            .worker_pids = WorkerPidList.init(allocator),
        };
    }

    pub fn deinit(self: *Master) void {
        logger.info("Deinitializing master process...", .{});
        self.worker_pids.deinit();
        logger.info("Master deinitialized.", .{});
    }

    pub fn start(self: *Master) !void {
        logger.info("Master process starting with {d} worker processes.", .{self.config.worker_count});

        var sigaction_int = posix.Sigaction{
            .handler = .{ .handler = sigintTermHandler },
            .mask = posix.empty_sigset,
            .flags = 0,
        };
        var sigaction_term = posix.Sigaction{
            .handler = .{ .handler = sigintTermHandler },
            .mask = posix.empty_sigset,
            .flags = 0,
        };

        posix.sigaction(posix.SIG.INT, &sigaction_int, null);
        posix.sigaction(posix.SIG.TERM, &sigaction_term, null);

        var i: u32 = 0;
        while (i < self.config.worker_count) : (i += 1) {
            const worker_id_for_log = i; // For clearer logs from workers
            const pid = posix.fork() catch |err| {
                logger.fatal("Master: Failed to fork worker process {d}: {s}", .{ worker_id_for_log, @errorName(err) });
                // Attempt to kill already spawned children before exiting
                self.signalShutdownToWorkers();
                self.waitForWorkers();
                return MasterError.ForkFailed;
            };

            if (pid == 0) {
                // Child Process (Worker)
                // Child should not handle master's signals in the same way, or re-register.
                // For now, it inherits. If specific child signal handling is needed, add it here.

                // Ensure child has its own allocator if it needs to allocate independently of master's lifetime
                // For now, using the inherited allocator.
                worker_mod.worker_process_main(self.allocator, self.config, worker_id_for_log) catch |err| {
                    logger.fatal("Worker Process {d} exited with error: {s}", .{ worker_id_for_log, @errorName(err) });
                    posix.exit(1);
                };
                logger.info("Worker Process {d} exiting normally.", .{worker_id_for_log});
                posix.exit(0);
            } else {
                // Parent Process (Master)
                logger.info("Master: Worker process {d} spawned with PID {d}.", .{ worker_id_for_log, pid });
                try self.worker_pids.append(pid);
            }
        }

        // Master's main loop: monitor workers and handle shutdown
        logger.info("Master: All workers launched. Monitoring...", .{});
        while (self.worker_pids.items.len > 0 and !global_shutdown_requested) {
            const result = posix.waitpid(-1, 0);
            if (result.pid == 0) {
                // No child exited (due to WNOHANG)
                time.sleep(500 * 1000 * 1000); // Sleep 500ms then recheck
                continue;
            }
            if (result.pid > 0) {
                // A child exited
                logger.info("Master: Worker process PID {d} exited with status {d}.", .{ result.pid, result.status });
                // Remove from active PID list
                for (0..self.worker_pids.items.len) |idx| {
                    if (self.worker_pids.items[idx] == result.pid) {
                        _ = self.worker_pids.orderedRemove(idx);
                        break;
                    }
                }
            }
        }

        logger.info("Master: Shutdown sequence initiated or all workers exited.", .{});
        self.signalShutdownToWorkers();
        self.waitForWorkers();

        logger.info("Master: All workers terminated. Exiting.", .{});
    }

    fn signalShutdownToWorkers(self: *Master) void {
        logger.info("Master: Sending SIGTERM to all worker processes...", .{});
        for (self.worker_pids.items) |pid_val| {
            logger.debug("Master: Sending SIGTERM to PID {d}", .{pid_val});
            // posix.kill might return an error if process already exited, ignore for shutdown.
            posix.kill(pid_val, posix.SIG.TERM) catch |err| {
                logger.warn("Master: Failed to send SIGTERM to PID {d}: {s} (possibly already exited)", .{ pid_val, @errorName(err) });
            };
        }
    }

    fn waitForWorkers(self: *Master) void {
        logger.info("Master: Waiting for worker processes to terminate...", .{});
        // Wait for all known PIDs to exit
        // WNOHANG is not used here, so it blocks for each.
        // A timeout could be added.
        var remaining_workers = self.worker_pids.items.len;
        while (remaining_workers > 0) {
            const result = posix.waitpid(-1, 0);
            if (result.pid > 0) {
                logger.info("Master: Worker PID {d} confirmed terminated.", .{result.pid});
                remaining_workers -= 1;
                // Remove from list to avoid trying to kill again if this loop is re-entered
                for (0..self.worker_pids.items.len) |idx| {
                    if (self.worker_pids.items[idx] == result.pid) {
                        _ = self.worker_pids.orderedRemove(idx);
                        break;
                    }
                }
            }
            if (remaining_workers == 0) break;
        }
        self.worker_pids.clearRetainingCapacity(); // Clear the list
    }
};
