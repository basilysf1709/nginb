# Zig Load Balancer

A simple TCP load balancer written in Zig. This project demonstrates basic network programming in Zig, including listening for connections, parsing client information, and distributing requests to backend servers based on a hashing algorithm.

## Architecture

The current architecture is a single-process load balancer that listens for incoming TCP connections and forwards them to one of several predefined backend servers.

### Conceptual Flow
mermaid
sequenceDiagram
participant C as Client
participant LB as Load Balancer
participant BE1 as Backend Server 1
participant BE2 as Backend Server 2
participant BEn as Backend Server N
C->>+LB: TCP Connection Request (e.g., HTTP)
LB->>LB: Get Client IP Address
LB->>LB: Hash Client IP
LB->>LB: Select Backend (IP Hash % Number of Backends)
Note over LB: Forwards to selected backend
LB->>BEn: Proxies Connection / Sends Data
BEn-->>LB: Response from Backend
LB-->>-C: Proxies Response / Sends Data



mermaid
graph LR
A[Project Root: nginb] --> B[src/]
A --> D[build.zig]
A --> F[.gitignore]
A --> G[README.md]
B --> H[main.zig]
B --> I[load_balancer.zig]

## Getting Started

### Prerequisites

*   Zig compiler (version 0.14.0 or compatible - based on recent error logs) installed. You can find installation instructions on the [official Zig website](https://ziglang.org/download/).

### Installation & Building

1.  **Clone the repository (if applicable, otherwise navigate to your project directory):**
    ```bash
    # git clone https://github.com/yourusername/nginb
    cd nginb
    ```

2.  **Build the executable:**
    ```bash
    zig build
    ```
    This will create an executable in the `zig-out/bin/` directory (e.g., `zig-out/bin/load_balancer_zig`).

### Running the Load Balancer

To run the load balancer:

```bash
zig build run
```

By default, it will listen on `0.0.0.0:8080`. The backend servers are currently hardcoded in `src/main.zig` to:
*   `127.0.0.1:8081`
*   `127.0.0.1:8082`
*   `127.0.0.1:8083`

### Testing

To run any unit tests defined in the project (currently none explicitly, but the build step is present):

```bash
zig build test
```

To test the load balancer manually, you can use a tool like `nc` (netcat) to connect to `127.0.0.1:8080` from different source IPs (or simulate by connecting multiple times from the same IP; the hashing will still distribute, though less obviously without diverse IPs).

Example:
```bash
nc 127.0.0.1 8080
```
You should receive a message like: `You've been routed to backend 127.0.0.1:808X`.

## Future Enhancements (Potential Roadmap)

*   **Actual Proxying:** Implement full TCP stream proxying to the selected backend server instead of just sending a message.
*   **Configuration File:** Load listen address, backend servers, and other settings from a configuration file (e.g., `conf/server.conf`).
*   **Health Checks:** Periodically check the health of backend servers and temporarily remove unhealthy ones from the rotation.
*   **More Sophisticated Load Balancing Algorithms:**
    *   Round Robin
    *   Least Connections
    *   Weighted algorithms
*   **Worker Processes:** For handling a higher volume of concurrent connections, implement a multi-process or multi-threaded architecture (Master/Worker model).
*   **HTTP Specifics:** If targeting HTTP, parse HTTP requests for more advanced routing (e.g., path-based, header-based).
*   **Static File Serving:** Add capability to serve static files directly.

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.