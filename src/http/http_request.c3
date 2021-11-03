// Module: caisson::http
// HTTP/1.1 request model, header table, and URI query parameter extraction.
//
// Part of the Caisson distributed object storage engine.

module caisson::http;

import caisson::core;

enum HttpMethod : int {
    GET,
    PUT,
    POST,
    DELETE,
    HEAD,
    OPTIONS,
    UNKNOWN
}

fn String method_to_string(HttpMethod m) {
    switch (m) {
        case HttpMethod.GET: return "GET";
        case HttpMethod.PUT: return "PUT";
        case HttpMethod.POST: return "POST";
        case HttpMethod.DELETE: return "DELETE";
        case HttpMethod.HEAD: return "HEAD";
        case HttpMethod.OPTIONS: return "OPTIONS";
        case HttpMethod.UNKNOWN: return "UNKNOWN";
    }
}

fn HttpMethod string_to_method(String s) {
    if (s == "GET") return HttpMethod.GET;
    if (s == "PUT") return HttpMethod.PUT;
    if (s == "POST") return HttpMethod.POST;
    if (s == "DELETE") return HttpMethod.DELETE;
    if (s == "HEAD") return HttpMethod.HEAD;
    if (s == "OPTIONS") return HttpMethod.OPTIONS;
    return HttpMethod.UNKNOWN;
}

struct HttpHeader {
    String name;
    String value;
}

struct ByteRange {
    long start;
    long end;
    bool is_suffix;
    bool is_valid;
}

const usz MAX_HTTP_HEADERS = 64;

struct HttpRequest {
    HttpMethod method;
    String path;
    String raw_query;
    HttpHeader[MAX_HTTP_HEADERS] headers;
    usz header_count;
    char* body;
    usz body_len;
    ByteRange range;
}

fn HttpRequest request_init() {
    return (HttpRequest){
        .method = HttpMethod.GET,
        .path = "",
        .raw_query = "",
        .header_count = 0,
        .body = null,
        .body_len = 0,
        .range = (ByteRange){ .start = 0, .end = -1, .is_suffix = false, .is_valid = false }
    };
}

// Case-insensitive ASCII character comparison.
fn bool ascii_char_case_eq(char a, char b) {
    char lower_a = (a >= 'A' && a <= 'Z') ? (char)(a + 32) : a;
    char lower_b = (b >= 'A' && b <= 'Z') ? (char)(b + 32) : b;
    return lower_a == lower_b;
}

// Case-insensitive ASCII string comparison.
fn bool ascii_case_eq(String a, String b) {
    if (a.len != b.len) return false;
    for (usz i = 0; i < a.len; i++) {
        if (!ascii_char_case_eq(a[i], b[i])) return false;
    }
    return true;
}

// Case-insensitive header lookup.
fn String HttpRequest.get_header(&this, String name) {
    for (usz i = 0; i < this.header_count; i++) {
        if (ascii_case_eq(this.headers[i].name, name)) {
            return this.headers[i].value;
        }
    }
    return "";
}

// Extracts value for a specific query parameter from raw query string.
// Example: raw_query="prefix=photos&max-keys=100", key="prefix" -> "photos"
fn String HttpRequest.get_query_param(&this, String key) {
    if (this.raw_query.len == 0 || key.len == 0) return "";

    usz pos = 0;
    while (pos < this.raw_query.len) {
        usz eq_pos = this.raw_query.len;
        usz amp_pos = this.raw_query.len;

        for (usz i = pos; i < this.raw_query.len; i++) {
            if (this.raw_query[i] == '=' && eq_pos == this.raw_query.len) {
                eq_pos = i;
            }
            if (this.raw_query[i] == '&') {
                amp_pos = i;
                break;
            }
        }

        if (eq_pos < amp_pos) {
            String param_key = (String)this.raw_query[pos : eq_pos - pos];
            if (param_key == key) {
                return (String)this.raw_query[eq_pos + 1 : amp_pos - (eq_pos + 1)];
            }
        } else {
            // Flag parameter without value: e.g. "?uploads"
            String param_key = (String)this.raw_query[pos : amp_pos - pos];
            if (param_key == key) {
                return "";
            }
        }

        pos = amp_pos + 1;
    }

    return "";
}

// Checks if a flag query parameter exists (e.g., "?uploads").
fn bool HttpRequest.has_query_param(&this, String key) {
    if (this.raw_query.len == 0 || key.len == 0) return false;

    usz pos = 0;
    while (pos < this.raw_query.len) {
        usz amp_pos = this.raw_query.len;
        for (usz i = pos; i < this.raw_query.len; i++) {
            if (this.raw_query[i] == '&') {
                amp_pos = i;
                break;
            }
        }

        usz eq_pos = amp_pos;
        for (usz i = pos; i < amp_pos; i++) {
            if (this.raw_query[i] == '=') {
                eq_pos = i;
                break;
            }
        }

        String param_key = (String)this.raw_query[pos : eq_pos - pos];
        if (param_key == key) return true;

        pos = amp_pos + 1;
    }

    return false;
}
