// Module: caisson::http
// Zero-copy RFC 7230 HTTP/1.1 stream and request parser.
//
// Part of the Caisson distributed object storage engine.

module caisson::http;

import caisson::core;
import std::io;

// Parses an integer from a byte slice.
fn long parse_long(String s) {
    long result = 0;
    bool neg = false;
    usz i = 0;
    if (s.len > 0 && s[0] == '-') {
        neg = true;
        i = 1;
    }
    for (; i < s.len; i++) {
        if (s[i] < '0' || s[i] > '9') break;
        result = result * 10 + (long)(s[i] - '0');
    }
    return neg ? -result : result;
}

// Parses standard HTTP Range header value: e.g. "bytes=0-1023", "bytes=500-", "bytes=-200".
fn ByteRange parse_byte_range(String header_val) {
    ByteRange range = (ByteRange){ .start = 0, .end = -1, .is_suffix = false, .is_valid = false };
    if (header_val.len < 7) return range;

    // Check "bytes=" prefix
    String prefix = (String)header_val[0:6];
    if (prefix != "bytes=") return range;

    String spec = (String)header_val[6 : header_val.len - 6];
    usz dash_pos = spec.len;
    for (usz i = 0; i < spec.len; i++) {
        if (spec[i] == '-') {
            dash_pos = i;
            break;
        }
    }

    if (dash_pos == spec.len) return range;

    if (dash_pos == 0) {
        // Suffix range: "-500"
        String suffix_str = (String)spec[1 : spec.len - 1];
        range.start = parse_long(suffix_str);
        range.end = -1;
        range.is_suffix = true;
        range.is_valid = true;
        return range;
    }

    String start_str = (String)spec[0 : dash_pos];
    range.start = parse_long(start_str);

    if (dash_pos + 1 < spec.len) {
        String end_str = (String)spec[dash_pos + 1 : spec.len - (dash_pos + 1)];
        range.end = parse_long(end_str);
    } else {
        range.end = -1;
    }

    range.is_valid = true;
    return range;
}

// Trims leading and trailing spaces/tabs from a string slice.
fn String trim_http_spaces(String s) {
    if (s.len == 0) return s;
    usz start = 0;
    while (start < s.len && (s[start] == ' ' || s[start] == '\t')) {
        start++;
    }
    usz end = s.len;
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r')) {
        end--;
    }
    return (String)s[start : end - start];
}

// Parses raw HTTP buffer into an HttpRequest struct.
fn core::Result parse_http_request(char* buf, usz len, HttpRequest* out_req) {
    if (buf == null || len < 4 || out_req == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid HTTP parse inputs");
    }

    *out_req = request_init();

    // 1. Locate end of request line
    usz req_line_end = len;
    for (usz i = 0; i < len - 1; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n') {
            req_line_end = i;
            break;
        }
    }
    if (req_line_end == len) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Malformed HTTP request line");
    }

    // 2. Parse request line: METHOD URI HTTP/1.1
    String line = (String)buf[0 : req_line_end];
    usz first_sp = line.len;
    usz second_sp = line.len;

    for (usz i = 0; i < line.len; i++) {
        if (line[i] == ' ') {
            if (first_sp == line.len) {
                first_sp = i;
            } else if (second_sp == line.len) {
                second_sp = i;
                break;
            }
        }
    }

    if (first_sp == line.len || second_sp == line.len) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid HTTP request line tokens");
    }

    String method_str = (String)line[0 : first_sp];
    out_req.method = string_to_method(method_str);

    String uri_str = (String)line[first_sp + 1 : second_sp - (first_sp + 1)];
    usz qmark_pos = uri_str.len;
    for (usz i = 0; i < uri_str.len; i++) {
        if (uri_str[i] == '?') {
            qmark_pos = i;
            break;
        }
    }

    if (qmark_pos < uri_str.len) {
        out_req.path = (String)uri_str[0 : qmark_pos];
        out_req.raw_query = (String)uri_str[qmark_pos + 1 : uri_str.len - (qmark_pos + 1)];
    } else {
        out_req.path = uri_str;
        out_req.raw_query = "";
    }

    // 3. Parse headers until \r\n\r\n
    usz cursor = req_line_end + 2;
    usz header_end = len;

    while (cursor < len - 1) {
        if (buf[cursor] == '\r' && buf[cursor + 1] == '\n') {
            // End of headers
            header_end = cursor + 2;
            break;
        }

        usz line_end = len;
        for (usz i = cursor; i < len - 1; i++) {
            if (buf[i] == '\r' && buf[i + 1] == '\n') {
                line_end = i;
                break;
            }
        }
        if (line_end == len) break;

        String hline = (String)buf[cursor : line_end - cursor];
        usz colon_pos = hline.len;
        for (usz i = 0; i < hline.len; i++) {
            if (hline[i] == ':') {
                colon_pos = i;
                break;
            }
        }

        if (colon_pos < hline.len && out_req.header_count < MAX_HTTP_HEADERS) {
            String name = (String)hline[0 : colon_pos];
            String val = trim_http_spaces((String)hline[colon_pos + 1 : hline.len - (colon_pos + 1)]);
            out_req.headers[out_req.header_count] = (HttpHeader){
                .name = name,
                .value = val
            };
            out_req.header_count++;
        }

        cursor = line_end + 2;
    }

    // 4. Parse Range header if present
    String range_hdr = out_req.get_header("range");
    if (range_hdr.len > 0) {
        out_req.range = parse_byte_range(range_hdr);
    }

    // 5. Body slice tracking
    if (header_end < len) {
        out_req.body = buf + header_end;
        out_req.body_len = len - header_end;

        // If Content-Length header is present, clamp body length
        String cl_str = out_req.get_header("content-length");
        if (cl_str.len > 0) {
            long cl = parse_long(cl_str);
            if (cl >= 0 && (usz)cl <= out_req.body_len) {
                out_req.body_len = (usz)cl;
            }
        }
    } else {
        out_req.body = null;
        out_req.body_len = 0;
    }

    return core::result_ok();
}
