// Module: test_http
// Unit test suite for HTTP/1.1 request parser, range header decoding, and response serializer.
//
// Part of the Caisson distributed object storage engine.

module test_http;

import caisson::core;
import caisson::http;

fn bool test_str_contains(String hay, String needle) {
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

fn void test_http_parse_get_request() @test {
    String raw = "GET /photos?prefix=vacation/&max-keys=50 HTTP/1.1\r\n"
                 "Host: s3.amazonaws.com\r\n"
                 "User-Agent: aws-cli/2.15.0\r\n"
                 "Accept: */*\r\n\r\n";

    http::HttpRequest req;
    core::Result res = http::parse_http_request(raw.ptr, raw.len, &req);
    assert(res.is_ok());

    assert(req.method == http::HttpMethod.GET);
    assert(req.path == "/photos");
    assert(req.raw_query == "prefix=vacation/&max-keys=50");
    assert(req.get_query_param("prefix") == "vacation/");
    assert(req.get_query_param("max-keys") == "50");

    // Case-insensitive header lookups
    assert(req.get_header("host") == "s3.amazonaws.com");
    assert(req.get_header("HOST") == "s3.amazonaws.com");
    assert(req.get_header("Host") == "s3.amazonaws.com");
    assert(req.get_header("user-agent") == "aws-cli/2.15.0");
    assert(req.get_header("accept") == "*/*");
    assert(req.get_header("non-existent") == "");
}

fn void test_http_parse_put_with_body() @test {
    String raw = "PUT /backup/db.tar.gz HTTP/1.1\r\n"
                 "Host: 127.0.0.1:9000\r\n"
                 "Content-Length: 13\r\n"
                 "Content-Type: application/octet-stream\r\n"
                 "x-amz-storage-class: STANDARD\r\n\r\n"
                 "caisson-chunk";

    http::HttpRequest req;
    core::Result res = http::parse_http_request(raw.ptr, raw.len, &req);
    assert(res.is_ok());

    assert(req.method == http::HttpMethod.PUT);
    assert(req.path == "/backup/db.tar.gz");
    assert(req.body_len == 13);
    assert(req.body != null);

    String body_str = (String)req.body[0 : req.body_len];
    assert(body_str == "caisson-chunk");
    assert(req.get_header("content-type") == "application/octet-stream");
    assert(req.get_header("x-amz-storage-class") == "STANDARD");
}

fn void test_http_parse_range_headers() @test {
    String raw = "GET /bigfile.bin HTTP/1.1\r\n"
                 "Host: localhost\r\n"
                 "Range: bytes=1024-2047\r\n\r\n";

    http::HttpRequest req;
    core::Result res = http::parse_http_request(raw.ptr, raw.len, &req);
    assert(res.is_ok());

    assert(req.range.is_valid);
    assert(req.range.start == 1024);
    assert(req.range.end == 2047);
    assert(!req.range.is_suffix);

    // Test open-ended range
    http::ByteRange r2 = http::parse_byte_range("bytes=4096-");
    assert(r2.is_valid);
    assert(r2.start == 4096);
    assert(r2.end == -1);

    // Test suffix range
    http::ByteRange r3 = http::parse_byte_range("bytes=-512");
    assert(r3.is_valid);
    assert(r3.start == 512);
    assert(r3.is_suffix);
}

fn void test_http_response_serialization() @test {
    http::HttpResponse resp = http::response_init();
    resp.set_status(200, "OK");
    resp.add_header("ETag", "\"d41d8cd98f00b204e9800998ecf8427e\"");
    resp.add_header("Content-Type", "text/plain");
    resp.set_body_string("hello caisson storage");

    core::Buffer wire = core::buffer_init(512);
    resp.serialize(&wire);

    String wire_str = (String)wire.data[0 : wire.len];
    assert(test_str_contains(wire_str, "HTTP/1.1 200 OK\r\n"));
    assert(test_str_contains(wire_str, "Server: Caisson/1.0.0\r\n"));
    assert(test_str_contains(wire_str, "Content-Length: 21\r\n"));
    assert(test_str_contains(wire_str, "ETag: \"d41d8cd98f00b204e9800998ecf8427e\"\r\n"));
    assert(test_str_contains(wire_str, "hello caisson storage"));

    wire.free();
    resp.free();
}
