// Module: caisson::core
// Structured logging, severity levels, ANSI color terminal formatting.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

import std::io;

enum LogLevel : int {
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL
}

struct Logger {
    LogLevel min_level;
    bool use_colors;
}

fn Logger logger_default() {
    return (Logger){ .min_level = LogLevel.INFO, .use_colors = true };
}

fn void Logger.set_level(&this, LogLevel level) {
    this.min_level = level;
}

fn void Logger.log(&this, LogLevel level, String tag, String message) {
    if (level < this.min_level) return;

    char[32] time_buf;
    long now = current_time_seconds();
    format_iso8601_extended(now, &time_buf[0]);
    String time_str = (String)time_buf[0:24];

    String lvl_str = "INFO";
    String color = "\x1b[32m"; // Green
    String reset = "\x1b[0m";

    switch (level) {
        case LogLevel.DEBUG:
            lvl_str = "DEBUG";
            color = "\x1b[36m"; // Cyan
        case LogLevel.INFO:
            lvl_str = "INFO ";
            color = "\x1b[32m"; // Green
        case LogLevel.WARN:
            lvl_str = "WARN ";
            color = "\x1b[33m"; // Yellow
        case LogLevel.ERROR:
            lvl_str = "ERROR";
            color = "\x1b[31m"; // Red
        case LogLevel.FATAL:
            lvl_str = "FATAL";
            color = "\x1b[35;1m"; // Magenta Bold
    }

    if (this.use_colors) {
        io::printfn("%s [%s%s%s] [%s] %s", time_str, color, lvl_str, reset, tag, message);
    } else {
        io::printfn("%s [%s] [%s] %s", time_str, lvl_str, tag, message);
    }
}

fn void Logger.debug(&this, String tag, String message) {
    this.log(LogLevel.DEBUG, tag, message);
}

fn void Logger.info(&this, String tag, String message) {
    this.log(LogLevel.INFO, tag, message);
}

fn void Logger.warn(&this, String tag, String message) {
    this.log(LogLevel.WARN, tag, message);
}

fn void Logger.error(&this, String tag, String message) {
    this.log(LogLevel.ERROR, tag, message);
}

fn void Logger.fatal(&this, String tag, String message) {
    this.log(LogLevel.FATAL, tag, message);
}
