// Module: caisson
// Main application entrypoint and subcommand dispatcher.
//
// Part of the Caisson distributed object storage engine.

module caisson;

import std::io;
import caisson::cli;

fn void print_help() {
    io::printn("");
    io::printn("Caisson Distributed Object Storage Engine v1.0.0");
    io::printn("");
    io::printn("USAGE:");
    io::printn("  caisson <subcommand> [flags]");
    io::printn("");
    io::printn("SUBCOMMANDS:");
    io::printn("  server     Start S3 gateway daemon and web administrative console");
    io::printn("  bench      Run in-process Galois Field and storage microbenchmarks");
    io::printn("  inspect    Forensically decode and verify a Bitcask .data WAL log");
    io::printn("  scrub      Trigger storage bit-rot integrity scrubber pass");
    io::printn("  version    Print version and build target information");
    io::printn("  help       Print this help menu");
    io::printn("");
    io::printn("SERVER FLAGS:");
    io::printn("  --port, -p <num>      TCP port to bind listener (default: 9000)");
    io::printn("  --data-dir, -d <path> Directory path for persistent WAL logs (default: ./data)");
    io::printn("  --require-auth        Enforce AWS SigV4 cryptographic signature validation");
    io::printn("");
    io::printn("EXAMPLES:");
    io::printn("  caisson server --port 9000 --data-dir ./caisson_data");
    io::printn("  caisson bench");
    io::printn("  caisson inspect ./caisson_data/000000.data");
    io::printn("");
}

fn int main(String[] args) {
    cli::CliConfig cfg = cli::parse_cli_args(args);

    if (cfg.show_version) {
        io::printn("caisson version 1.0.0 (darwin-aarch64)");
        return 0;
    }

    if (cfg.show_help || cfg.subcommand == "help") {
        print_help();
        return 0;
    }

    if (cfg.subcommand == "server" || cfg.subcommand == "start") {
        return cli::run_server_command(&cfg);
    }

    if (cfg.subcommand == "bench") {
        return cli::run_bench_command();
    }

    if (cfg.subcommand == "inspect") {
        return cli::run_inspect_command(cfg.inspect_path);
    }

    if (cfg.subcommand == "scrub") {
        return cli::run_scrub_command(cfg.data_dir);
    }

    io::printfn("Unknown subcommand: '%s'. Run 'caisson help' for available commands.", cfg.subcommand);
    return 1;
}
