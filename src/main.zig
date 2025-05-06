const std = @import("std");
const net = std.net;
const lb = @import("load_balancer.zig"); // Import the new module

pub fn main() !void {
    // --- Configuration ---
    const listen_ip = "0.0.0.0";
    const listen_port: u16 = 8080;

    // Define backend servers
    // In a real app, this might come from a config file or service discovery
    const backend_servers = [_]lb.Backend{
        lb.Backend.init("127.0.0.1", 8081),
        lb.Backend.init("127.0.0.1", 8082),
        lb.Backend.init("127.0.0.1", 8083),
    };
    // --- End Configuration ---

    // Parse the listen address
    const listen_address = try net.Address.parseIp(listen_ip, listen_port);

    // Start the load balancer
    std.debug.print("Starting load balancer...\n", .{});
    try lb.start(listen_address, &backend_servers);

    // This part is unreachable in the current loop structure of lb.start,
    // but good practice if start could return normally.
    std.debug.print("Load balancer finished.\n", .{});
}
