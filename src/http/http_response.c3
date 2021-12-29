// Module: caisson::http
// HTTP/1.1 response builder and wire-protocol serializer.
//
// Part of the Caisson distributed object storage engine.

module caisson::http;

import caisson::core;
import std::io;

struct HttpResponse {
    int status_code;
    String status_text;
    HttpHeader[MAX_HTTP_HEADERS] headers;
    usz header_count;
    core::Buffer body;
}

fn HttpResponse response_init() {
    return (HttpResponse){
        .status_code = 200,
        .status_text = "OK",
        .header_count = 0,
        .body = core::buffer_init(1024)
    };
}

fn void HttpResponse.free(&this) {
    this.body.free();
}

fn void HttpResponse.set_status(&this, int code, String text) {
    this.status_code = code;
    this.status_text = text;
}

fn bool HttpResponse.has_header(&this, String name) {
    for (usz i = 0; i < this.header_count; i++) {
        if (ascii_case_eq(this.headers[i].name, name)) return true;
    }
    return false;
}

fn void HttpResponse.add_header(&this, String name, String value) {
    if (this.header_count < MAX_HTTP_HEADERS) {
        this.headers[this.header_count] = (HttpHeader){
            .name = name,
            .value = value
        };
        this.header_count++;
    }
}

fn void HttpResponse.set_body_bytes(&this, char* data, usz len) {
    this.body.clear();
    if (data != null && len > 0) {
        this.body.append_bytes(data, len);
    }
}

fn void HttpResponse.set_body_string(&this, String text) {
    this.body.clear();
    if (text.len > 0) {
        this.body.append_string(text);
    }
}

// Converts integer to string digits in a buffer, returns length.
fn usz int_to_ascii(long n, char* out_buf) {
    if (n == 0) {
        out_buf[0] = '0';
        return 1;
    }
    char[32] tmp;
    usz i = 0;
    long val = n < 0 ? -n : n;
    while (val > 0) {
        tmp[i++] = (char)('0' + (val % 10));
        val /= 10;
    }
    usz out_idx = 0;
    if (n < 0) {
        out_buf[out_idx++] = '-';
    }
    while (i > 0) {
        out_buf[out_idx++] = tmp[--i];
    }
    return out_idx;
}

// Serializes the entire HTTP response into a destination Buffer.
fn void HttpResponse.serialize(&this, core::Buffer* out_buf) {
    // 1. Status line: HTTP/1.1 <code> <text>\r\n
    out_buf.append_string("HTTP/1.1 ");
    char[16] code_buf;
    usz code_len = int_to_ascii(this.status_code, &code_buf[0]);
    out_buf.append_bytes(&code_buf[0], code_len);
    out_buf.append_string(" ");
    out_buf.append_string(this.status_text);
    out_buf.append_string("\r\n");

    // 2. Server header
    out_buf.append_string("Server: Caisson/1.0.0\r\n");

    // 3. Date header
    char[32] date_str;
    core::format_rfc1123_date(core::current_time_seconds(), &date_str[0]);
    out_buf.append_string("Date: ");
    out_buf.append_bytes(&date_str[0], 29);
    out_buf.append_string("\r\n");

    // 4. Content-Length header (if not explicitly overridden by handler)
    if (!this.has_header("Content-Length")) {
        char[32] cl_buf;
        usz cl_len = int_to_ascii((long)this.body.len, &cl_buf[0]);
        out_buf.append_string("Content-Length: ");
        out_buf.append_bytes(&cl_buf[0], cl_len);
        out_buf.append_string("\r\n");
    }

    // 5. Connection header
    out_buf.append_string("Connection: close\r\n");

    // 6. Custom headers
    for (usz i = 0; i < this.header_count; i++) {
        out_buf.append_string(this.headers[i].name);
        out_buf.append_string(": ");
        out_buf.append_string(this.headers[i].value);
        out_buf.append_string("\r\n");
    }

    // End of headers
    out_buf.append_string("\r\n");

    // 7. Body
    if (this.body.len > 0) {
        out_buf.append_bytes(this.body.data, this.body.len);
    }
}
