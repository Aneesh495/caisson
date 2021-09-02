// Main entry point for Caisson distributed object storage engine.

module caisson;

import std::io;
import caisson::core;

fn void main(String[] args) {
    core::Logger log = core::logger_default();
    log.info("Server", "Caisson distributed object storage engine initializing");
}
