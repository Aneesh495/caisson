// Module: caisson::http
// POSIX stream socket abstractions for TCP listener and client connections.
//
// Part of the Caisson distributed object storage engine.

module caisson::http;

import caisson::core;
import std::io;

const int AF_INET = 2;
const int SOCK_STREAM = 1;
const int SOL_SOCKET_DARWIN = 0xffff;
const int SO_REUSEADDR_DARWIN = 0x0004;

struct SockaddrIn {
    char sin_len;
    char sin_family;
    ushort sin_port;
    uint sin_addr;
    char[8] sin_zero;
}

extern fn ushort htons(ushort hostshort);
extern fn int socket(int domain, int type, int protocol);
extern fn int setsockopt(int socket, int level, int option_name, void* option_value, uint option_len);
extern fn int bind(int socket, void* address, uint address_len);
extern fn int listen(int socket, int backlog);
extern fn int accept(int socket, void* address, uint* address_len);
extern fn sz read(int fd, void* buf, usz nbyte);
extern fn sz write(int fd, void* buf, usz nbyte);
extern fn int close(int fd);

// Binds and listens on specified TCP port on all interfaces (INADDR_ANY).
fn core::Result socket_listen(ushort port, int* out_fd) {
    if (out_fd == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid out_fd pointer");
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return core::result_err(core::StorageError.IO_ERROR, "Failed to create socket");
    }

    int opt = 1;
    setsockopt(fd, SOL_SOCKET_DARWIN, SO_REUSEADDR_DARWIN, &opt, 4);

    SockaddrIn addr;
    addr.sin_len = 16;
    addr.sin_family = (char)AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr = 0; // INADDR_ANY
    for (int i = 0; i < 8; i++) addr.sin_zero[i] = 0;

    if (bind(fd, &addr, SockaddrIn::size) != 0) {
        close(fd);
        return core::result_err(core::StorageError.IO_ERROR, "Failed to bind socket to port");
    }

    if (listen(fd, 128) != 0) {
        close(fd);
        return core::result_err(core::StorageError.IO_ERROR, "Failed to listen on socket");
    }

    *out_fd = fd;
    return core::result_ok();
}

// Accepts an incoming TCP connection.
fn core::Result socket_accept(int listener_fd, int* out_client_fd) {
    if (out_client_fd == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid client_fd pointer");
    }

    SockaddrIn client_addr;
    uint addr_len = SockaddrIn::size;
    int client_fd = accept(listener_fd, &client_addr, &addr_len);
    if (client_fd < 0) {
        return core::result_err(core::StorageError.IO_ERROR, "Failed to accept connection");
    }

    *out_client_fd = client_fd;
    return core::result_ok();
}

// Reads available data from socket into buffer.
fn core::Result socket_read(int fd, char* buf, usz max_len, sz* out_read) {
    if (buf == null || out_read == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid read parameters");
    }

    sz n = read(fd, buf, max_len);
    if (n < 0) {
        return core::result_err(core::StorageError.IO_ERROR, "Socket read error");
    }

    *out_read = n;
    return core::result_ok();
}

// Writes full buffer to socket, looping until complete.
fn core::Result socket_write_all(int fd, char* buf, usz len) {
    if (buf == null && len > 0) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid write parameters");
    }

    usz total_written = 0;
    while (total_written < len) {
        sz n = write(fd, buf + total_written, len - total_written);
        if (n <= 0) {
            return core::result_err(core::StorageError.IO_ERROR, "Socket write error");
        }
        total_written += (usz)n;
    }

    return core::result_ok();
}

// Closes socket file descriptor.
fn void socket_close(int fd) {
    if (fd >= 0) {
        close(fd);
    }
}
