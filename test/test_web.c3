// Module: test_web
// Unit tests for embedded HTML dashboard, Prometheus exporter, and REST telemetry endpoints.
//
// Part of the Caisson distributed object storage engine.

module test_web;

import caisson::core;
import caisson::http;
import caisson::s3;
import caisson::web;

fn bool test_web_contains(String hay, String needle) {
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

fn void test_web_dashboard_html_generation() @test {
    String html = web::get_dashboard_html();
    assert(test_web_contains(html, "<!DOCTYPE html>"));
    assert(test_web_contains(html, "Caisson Storage Engine"));
    assert(test_web_contains(html, "Reed-Solomon"));
    assert(test_web_contains(html, "shards-grid"));
    assert(test_web_contains(html, "healShards()"));
}

fn void test_prometheus_metrics_formatting() @test {
    s3::S3Context ctx = s3::context_init("test_web_metrics_dir", 9000, false);

    http::HttpResponse resp = http::response_init();
    web::format_prometheus_metrics(&ctx, &resp);

    assert(resp.status_code == 200);
    String body_str = (String)resp.body.data[0 : resp.body.len];

    assert(test_web_contains(body_str, "caisson_storage_writes_total"));
    assert(test_web_contains(body_str, "caisson_storage_reads_total"));
    assert(test_web_contains(body_str, "caisson_scrubber_stripes_scanned_total"));
    assert(test_web_contains(body_str, "caisson_buckets_count"));

    resp.free();
    ctx.free();
}

fn void test_web_route_dispatching() @test {
    s3::S3Context ctx = s3::context_init("test_web_routes_dir", 9000, false);

    // 1. Health endpoint
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/api/health";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String body_str = (String)resp.body.data[0 : resp.body.len];
        assert(test_web_contains(body_str, "\"status\":\"HEALTHY\""));
        resp.free();
    }

    // 2. Telemetry endpoint
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/api/telemetry";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String body_str = (String)resp.body.data[0 : resp.body.len];
        assert(test_web_contains(body_str, "\"status\":\"ONLINE\""));
        resp.free();
    }

    // 3. HTML Dashboard endpoint
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/console";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String body_str = (String)resp.body.data[0 : resp.body.len];
        assert(test_web_contains(body_str, "<!DOCTYPE html>"));
        resp.free();
    }

    ctx.free();
}
