// Module: caisson::web
// Web administrative console, Prometheus metrics, and JSON health endpoints dispatcher.
//
// Part of the Caisson distributed object storage engine.

module caisson::web;

import caisson::core;
import caisson::http;
import caisson::s3;

fn bool str_has_substr(String hay, String needle) {
    if (needle.len > hay.len) return false;
    for (usz i = 0; i <= hay.len - needle.len; i++) {
        bool match = true;
        for (usz j = 0; j < needle.len; j++) {
            if (hay[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

// Determines if an incoming HTTP request is targeting the administrative console or telemetry.
fn bool is_web_or_telemetry_route(http::HttpRequest* req) {
    if (req.path == "/metrics") return true;
    if (req.path == "/api/health" || req.path == "/healthz") return true;
    if (req.path == "/api/telemetry") return true;
    if (req.path == "/console" || req.path == "/dashboard" || req.path == "/index.html") return true;

    if (req.path == "/" || req.path == "") {
        String accept_hdr = req.get_header("accept");
        if (str_has_substr(accept_hdr, "text/html")) return true;
    }

    return false;
}

// Handles administrative console and telemetry endpoints.
fn void handle_web_route(s3::S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp) {
    if (req.path == "/metrics") {
        format_prometheus_metrics(ctx, resp);
        return;
    }

    if (req.path == "/api/health" || req.path == "/healthz") {
        resp.set_status(200, "OK");
        resp.add_header("Content-Type", "application/json");
        resp.set_body_string("{\"status\":\"HEALTHY\",\"engine\":\"caisson\",\"version\":\"1.0.0\"}\n");
        return;
    }

    if (req.path == "/api/telemetry") {
        resp.set_status(200, "OK");
        resp.add_header("Content-Type", "application/json");

        core::Buffer b = core::buffer_init(512);
        b.append_string("{\"status\":\"ONLINE\",\"writes\":");
        char[32] num_buf;
        usz l = http::int_to_ascii((long)(ctx != null ? ctx.storage.total_writes : 0), &num_buf[0]);
        b.append_bytes(&num_buf[0], l);

        b.append_string(",\"reads\":");
        l = http::int_to_ascii((long)(ctx != null ? ctx.storage.total_reads : 0), &num_buf[0]);
        b.append_bytes(&num_buf[0], l);

        b.append_string(",\"buckets\":");
        l = http::int_to_ascii((long)(ctx != null ? ctx.bucket_reg.count : 0), &num_buf[0]);
        b.append_bytes(&num_buf[0], l);

        b.append_string(",\"objects\":");
        l = http::int_to_ascii((long)(ctx != null ? ctx.obj_index.count : 0), &num_buf[0]);
        b.append_bytes(&num_buf[0], l);

        b.append_string("}\n");

        resp.set_body_bytes(b.data, b.len);
        b.free();
        return;
    }

    // Default to interactive HTML dashboard
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "text/html; charset=utf-8");
    resp.set_body_string(get_dashboard_html());
}
