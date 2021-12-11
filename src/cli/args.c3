// Module: caisson::cli
// Command-line flag parsing and configuration management.
//
// Part of the Caisson distributed object storage engine.

module caisson::cli;

import caisson::core;
import caisson::http;

struct CliConfig {
    String subcommand;
    ushort port;
    String data_dir;
    String inspect_path;
    bool require_auth;
    bool show_help;
    bool show_version;
}

fn CliConfig parse_cli_args(String[] args) {
    CliConfig cfg = (CliConfig){
        .subcommand = "help",
        .port = 9000,
        .data_dir = "./data",
        .inspect_path = "",
        .require_auth = false,
        .show_help = false,
        .show_version = false
    };

    if (args.len <= 1) {
        return cfg;
    }

    cfg.subcommand = args[1];

    if (cfg.subcommand == "--help" || cfg.subcommand == "-h" || cfg.subcommand == "help") {
        cfg.show_help = true;
        return cfg;
    }

    if (cfg.subcommand == "--version" || cfg.subcommand == "-v" || cfg.subcommand == "version") {
        cfg.show_version = true;
        return cfg;
    }

    usz i = 2;
    while (i < args.len) {
        String arg = args[i];

        if (arg == "--port" || arg == "-p") {
            if (i + 1 < args.len) {
                long p = http::parse_long(args[i + 1]);
                if (p > 0 && p <= 65535) {
                    cfg.port = (ushort)p;
                }
                i += 2;
                continue;
            }
        }

        if (arg == "--data-dir" || arg == "-d") {
            if (i + 1 < args.len) {
                cfg.data_dir = args[i + 1];
                i += 2;
                continue;
            }
        }

        if (arg == "--inspect" || arg == "-i") {
            if (i + 1 < args.len) {
                cfg.inspect_path = args[i + 1];
                i += 2;
                continue;
            }
        }

        if (arg == "--require-auth") {
            cfg.require_auth = true;
            i++;
            continue;
        }

        if (arg == "--help" || arg == "-h") {
            cfg.show_help = true;
            i++;
            continue;
        }

        // If inspecting file path is passed as positional argument
        if (cfg.subcommand == "inspect" && cfg.inspect_path.len == 0) {
            cfg.inspect_path = arg;
        }

        i++;
    }

    return cfg;
}
