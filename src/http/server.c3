// Module: caisson::http
// HTTP/1.1 connection dispatcher and request-response lifecycle coordinator.
//
// Part of the Caisson distributed object storage engine.

module caisson::http;

import caisson::core;
import std::io;

alias HttpHandler = fn void(HttpRequest* req, HttpResponse* resp, void* user_data);

struct HttpServer {
    ushort port;
    int listener_fd;
    bool is_running;
    HttpHandler handler;
    void* user_data;
}

fn HttpServer server_init(ushort port, HttpHandler handler, void* user_data) {
    return (HttpServer){
        .port = port,
        .listener_fd = -1,
        .is_running = false,
        .handler = handler,
        .user_data = user_data
    };
}

fn sz find_header_end(char* buf, usz len) {
    if (len < 4) return -1;
    for (usz i = 0; i <= len - 4; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
            return (sz)(i + 4);
        }
    }
    return -1;
}

fn long find_content_length(char* buf, usz len) {
    String s = (String)buf[0 : len];
    if (s.len < 16) return 0;
    for (usz i = 0; i <= s.len - 15; i++) {
        if (ascii_char_case_eq(s[i], 'c') &&
            ascii_char_case_eq(s[i + 1], 'o') &&
            ascii_char_case_eq(s[i + 2], 'n') &&
            ascii_char_case_eq(s[i + 3], 't') &&
            ascii_char_case_eq(s[i + 4], 'e') &&
            ascii_char_case_eq(s[i + 5], 'n') &&
            ascii_char_case_eq(s[i + 6], 't') &&
            s[i + 7] == '-' &&
            ascii_char_case_eq(s[i + 8], 'l') &&
            ascii_char_case_eq(s[i + 9], 'e') &&
            ascii_char_case_eq(s[i + 10], 'n') &&
            ascii_char_case_eq(s[i + 11], 'g') &&
            ascii_char_case_eq(s[i + 12], 't') &&
            ascii_char_case_eq(s[i + 13], 'h') &&
            s[i + 14] == ':') {
            usz val_start = i + 15;
            while (val_start < s.len && (s[val_start] == ' ' || s[val_start] == '\t')) val_start++;
            usz val_end = val_start;
            while (val_end < s.len && s[val_end] >= '0' && s[val_end] <= '9') val_end++;
            if (val_end > val_start) {
                return parse_long((String)s[val_start : val_end - val_start]);
            }
        }
    }
    return 0;
}

// Handles a single incoming TCP client connection:
// Reads headers and body, parses HTTP/1.1, invokes handler, serializes and sends response, and closes socket.
fn void HttpServer.process_client(&this, int client_fd) {
    const usz MAX_REQ_SIZE = 65536;
    char[MAX_REQ_SIZE] req_buf;
    sz bytes_read = 0;

    // Read until headers are fully received
    sz hdr_end = -1;
    while (bytes_read < (sz)MAX_REQ_SIZE) {
        sz n = 0;
        core::Result r = socket_read(client_fd, &req_buf[bytes_read], MAX_REQ_SIZE - (usz)bytes_read, &n);
        if (!r.is_ok() || n <= 0) break;
        bytes_read += n;

        hdr_end = find_header_end(&req_buf[0], (usz)bytes_read);
        if (hdr_end >= 0) break;
    }

    if (bytes_read <= 0 || hdr_end < 0) {
        socket_close(client_fd);
        return;
    }

    // Check if Content-Length requires reading more body payload
    long cl = find_content_length(&req_buf[0], (usz)hdr_end);
    if (cl > 0) {
        usz total_needed = (usz)hdr_end + (usz)cl;
        if (total_needed > MAX_REQ_SIZE) total_needed = MAX_REQ_SIZE;

        while ((usz)bytes_read < total_needed) {
            sz n = 0;
            core::Result r = socket_read(client_fd, &req_buf[bytes_read], total_needed - (usz)bytes_read, &n);
            if (!r.is_ok() || n <= 0) break;
            bytes_read += n;
        }
    }

    HttpRequest req;
    core::Result parse_res = parse_http_request(&req_buf[0], (usz)bytes_read, &req);

    HttpResponse resp = response_init();

    if (!parse_res.is_ok()) {
        resp.set_status(400, "Bad Request");
        resp.set_body_string("Invalid HTTP request syntax\n");
    } else if (this.handler != null) {
        this.handler(&req, &resp, this.user_data);
    } else {
        resp.set_status(404, "Not Found");
        resp.set_body_string("No handler registered\n");
    }

    core::Buffer wire_buf = core::buffer_init(2048);
    resp.serialize(&wire_buf);

    socket_write_all(client_fd, wire_buf.data, wire_buf.len);

    wire_buf.free();
    resp.free();
    socket_close(client_fd);
}

// Starts the server listener socket.
fn core::Result HttpServer.start(&this) {
    int lfd = -1;
    core::Result res = socket_listen(this.port, &lfd);
    if (!res.is_ok()) return res;

    this.listener_fd = lfd;
    this.is_running = true;
    return core::result_ok();
}

// Stops the server listener socket.
fn void HttpServer.stop(&this) {
    this.is_running = false;
    if (this.listener_fd >= 0) {
        socket_close(this.listener_fd);
        this.listener_fd = -1;
    }
}
