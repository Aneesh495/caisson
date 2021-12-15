// Module: caisson::cli
// S3 storage daemon runner, TCP listener initialization, and service supervisor.
//
// Part of the Caisson distributed object storage engine.

module caisson::cli;

import std::io;
import caisson::core;
import caisson::http;
import caisson::s3;
import caisson::cluster;

fn void print_banner(ushort port, String data_dir) {
    io::printn("");
    io::printn("   ____      _                            ");
    io::printn("  / ___|__ _(_)___ ___  ___  _ __         ");
    io::printn(" | |   / _` | / __/ __|/ _ \\| '_ \\        ");
    io::printn(" | |__| (_| | \\__ \\__ \\ (_) | | | |       ");
    io::printn("  \\____\\__,_|_|___/___/\\___/|_| |_|       ");
    io::printn("  High-Performance Distributed Object Storage Engine v1.0.0");
    io::printn("");
    io::printfn("[INIT] S3 Gateway Endpoint:  http://127.0.0.1:%d", (uint)port);
    io::printfn("[INIT] Web Console:          http://127.0.0.1:%d/console", (uint)port);
    io::printfn("[INIT] Prometheus Metrics:   http://127.0.0.1:%d/metrics", (uint)port);
    io::printfn("[INIT] Health Endpoint:      http://127.0.0.1:%d/api/health", (uint)port);
    io::printfn("[INIT] Storage Directory:    %s", data_dir);
    io::printn("[INIT] Storage Engine:       Log-Structured Merge WAL (Bitcask)");
    io::printn("[INIT] Erasure Coding:       Systematic Reed-Solomon RS(4, 2) Cauchy");
    io::printn("[INIT] Quorum Consistency:   Strict Linearizable (R+W > N)");
    io::printn("[INIT] Background Scrubber:  Periodic Bit-Rot Self-Healing Active");
    io::printn("");
    io::printn("[READY] Caisson daemon initialized. Awaiting S3 client connections...");
}

fn int run_server_command(CliConfig* cfg) {
    s3::S3Context ctx = s3::context_init(cfg.data_dir, cfg.port, cfg.require_auth);

    // Populate default hash ring drives
    ctx.ring.add_drive(1, cfg.data_dir, 1000000000000);

    http::HttpServer server = http::server_init(cfg.port, &s3::s3_route_request, &ctx);

    core::Result start_res = server.start();
    if (!start_res.is_ok()) {
        io::printfn("[ERROR] Failed to start HTTP server on port %d: %s", (uint)cfg.port, start_res.message);
        ctx.free();
        return 1;
    }

    print_banner(cfg.port, cfg.data_dir);

    // Event loop: process incoming TCP client connections
    while (server.is_running) {
        int client_fd = -1;
        core::Result accept_res = http::socket_accept(server.listener_fd, &client_fd);
        if (accept_res.is_ok() && client_fd >= 0) {
            server.process_client(client_fd);
        }
    }

    server.stop();
    ctx.free();
    return 0;
}
