const std = @import("std");
const net = std.net;
const mem = std.mem;
const config_mod = @import("./config.zig");
const request_mod = @import("./http/request.zig");
const response_mod = @import("./http/response.zig");
const static_mod = @import("./http/static.zig");
const logger = @import("./utils/logger.zig");

// Connection type remains the same
const Connection = net.Server.Connection;

// Removed WorkerContext and the old Worker.run that used the queue

// Main entry point for a worker process
pub fn worker_process_main(allocator: mem.Allocator, config: config_mod.Config, worker_id_for_log: u32) !void {
    logger.info("Worker Process {d}: starting.", .{worker_id_for_log});
    defer logger.info("Worker Process {d}: stopping.", .{worker_id_for_log});

    const address = try net.Address.parseIp(config.listen_address, config.listen_port);

    // Critical: Use .reuse_port = true
    // Also, .reuse_address is generally good practice.
    var listener = try address.listen(.{
        .reuse_address = true,
        .reuse_port = true, // Allows multiple worker processes to listen on the same port
    });
    defer listener.deinit();

    logger.info("Worker Process {d}: listening on {s}:{d}", .{
        worker_id_for_log,
        config.listen_address,
        config.listen_port,
    });

    while (true) {
        const connection = listener.accept() catch |err| {
            // Handle accept errors. Some might be fatal, others (like EINTR if handling signals) might be recoverable.
            // If the listener was closed (e.g., during shutdown), accept will likely fail.
            if (err == error.NotListening or err == error.NetworkUnreachable or err == error.SocketNotConnected) {
                logger.info("Worker Process {d}: Listener closed or network issue ({s}), exiting accept loop.", .{ worker_id_for_log, @errorName(err) });
                break; // Exit loop on listener closure
            }
            logger.e("Worker Process {d}: failed to accept connection: {s}", .{ worker_id_for_log, @errorName(err) });
            // Depending on the error, might continue or break. For now, continue.
            continue;
        };

        logger.info("Worker Process {d}: accepted connection from {}", .{ worker_id_for_log, connection.address });

        // Use a child allocator for each connection if desired, or pass the main worker allocator
        handleConnection(allocator, &config, connection, worker_id_for_log) catch |err_handle| {
            logger.e("Worker Process {d}: error handling connection from {}: {s}", .{
                worker_id_for_log,
                connection.address,
                @errorName(err_handle),
            });
            // Ensure stream is closed even if handleConnection errors before its defer
            connection.stream.close();
        };
    }
}

// handleConnection remains largely the same, but logging should be aware it's in a worker process
fn handleConnection(
    allocator: mem.Allocator,
    cfg: *const config_mod.Config,
    connection: Connection,
    worker_id: u32,
) !void {
    defer {
        logger.debug("Worker {d}: Closing connection stream from: {}", .{ worker_id, connection.address });
        connection.stream.close();
        logger.debug("Worker {d}: Closed connection stream for: {}", .{ worker_id, connection.address });
    }

    var request = request_mod.Request.parse(connection.stream.reader()) catch |err| {
        logger.warn("Worker {d}: Failed to parse request from {}: {s}", .{ worker_id, connection.address, @errorName(err) });
        response_mod.Response.sendError(allocator, connection.stream.writer(), .BadRequest, "Invalid HTTP request.") catch |send_err| {
            logger.e("Worker {d}: Failed to send 400 error response: {s}", .{ worker_id, @errorName(send_err) });
        };
        return;
    };

    logger.info("Worker {d}: Parsed request from {}: {s} {s}", .{ worker_id, connection.address, @tagName(request.method), request.path[0..request.path_len] });

    var response = response_mod.Response.init(allocator);
    defer response.deinit();

    if (request.method == .GET) {
        static_mod.serveFile(allocator, cfg, &request, &response, connection.stream.writer()) catch |err| {
            logger.e("Worker {d}: Error serving static file '{s}' for {}: {s}", .{ worker_id, request.path[0..request.path_len], connection.address, @errorName(err) });
            if (!response.headers_sent) {
                const status_code = response_mod.StatusCode.InternalServerError;
                response_mod.Response.sendError(allocator, connection.stream.writer(), status_code, "Failed to serve content.") catch |send_err| {
                    logger.e("Worker {d}: Failed to send error response for static file: {s}", .{ worker_id, @errorName(send_err) });
                };
            }
        };
    } else {
        logger.warn("Worker {d}: Method {s} not allowed for path {s} from {}", .{ worker_id, @tagName(request.method), request.path[0..request.path_len], connection.address });
        response_mod.Response.sendError(allocator, connection.stream.writer(), .MethodNotAllowed, "Method not supported.") catch |send_err| {
            logger.e("Worker {d}: Failed to send 405 error response: {s}", .{ worker_id, @errorName(send_err) });
        };
    }
    logger.info("Worker {d}: Finished processing request for {s} from {}", .{ worker_id, request.path[0..request.path_len], connection.address });
}
