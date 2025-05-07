const std = @import("std");
const net = std.net;
const lb = @import("load_balancer.zig"); // Import the new module
const server_config = @import("server/config.zig"); // New import

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example of using the imported config
    var config = try server_config.Config.loadFromFile(allocator, "conf/server.conf");
    defer config.deinit(allocator);

    std.debug.print("Loaded config: workers = {d}, address = {s}, port = {d}\n", .{ config.worker_count, config.listen_address, config.listen_port });

    // --- Configuration (potentially from loaded config now) ---
    // const listen_ip = "0.0.0.0"; // Could come from config.listen_address
    // const listen_port: u16 = 8080; // Could come from config.listen_port

    // Define backend servers
    // In a real app, this might come from a config file or service discovery
    const backend_servers = [_]lb.Backend{
        lb.Backend.init("127.0.0.1", 8081),
        lb.Backend.init("127.0.0.1", 8082),
        lb.Backend.init("127.0.0.1", 8083),
    };
    // --- End Configuration ---

    // Parse the listen address
    const listen_address = try net.Address.parseIp(config.listen_address, config.listen_port);

    // Start the load balancer
    std.debug.print("Starting server on {s}:{d}...\n", .{ config.listen_address, config.listen_port });
    try lb.start(listen_address, &backend_servers);

    // This part is unreachable in the current loop structure of lb.start,
    // but good practice if start could return normally.
    std.debug.print("Server finished.\n", .{});
}
