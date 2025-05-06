const std = @import("std");

// Represents a backend server
pub const Backend = struct {
    host: []const u8,
    port: u16,

    pub fn init(host: []const u8, port: u16) Backend {
        return Backend{
            .host = host,
            .port = port,
        };
    }
};

// Simple hash function for IP addresses (or any byte slice)
fn hashBytes(data: []const u8) u64 {
    var hash: u64 = 5381;
    for (data) |byte| {
        hash = ((hash << 5) + hash) + byte; // djb2 hash
    }
    return hash;
}

// Selects a backend based on the client's IP address using hashing
fn selectBackend(client_ip: []const u8, backends: []const Backend) Backend {
    if (backends.len == 0) {
        // Handle the case with no backends gracefully, perhaps return an error or a default
        @panic("No backends configured!"); // Or return an error
    }
    const hash = hashBytes(client_ip);
    const backend_index = hash % backends.len;
    return backends[backend_index];
}

// Starts the load balancer listening loop
pub fn start(listen_address: std.net.Address, backends: []const Backend) !void {
    // Try the direct listening approach as shown in the blog example
    var listener = try listen_address.listen(.{});
    defer listener.deinit();

    std.debug.print("Load balancer listening on {any}...\n", .{listen_address});

    // Accept and handle connections
    while (true) {
        const conn = try listener.accept();
        defer conn.stream.close();

        // Get client address information
        const client_addr = conn.address;
        // Define a fixed-size buffer for the IP string
        var client_ip_buf: [64]u8 = undefined; // Use a fixed size buffer
        // Format the address into the buffer using std.fmt.bufPrint
        const client_ip_str = try std.fmt.bufPrint(&client_ip_buf, "{any}", .{client_addr});

        // Select backend based on client IP string
        const selected_backend = selectBackend(client_ip_str, backends);

        std.debug.print("Client {s} -> Backend {s}:{d}\n", .{ client_ip_str, selected_backend.host, selected_backend.port });

        // Send response to client
        const writer = conn.stream.writer();
        try writer.print("You've been routed to backend {s}:{d}\n", .{ selected_backend.host, selected_backend.port });
    }
}
