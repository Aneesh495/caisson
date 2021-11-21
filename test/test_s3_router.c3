// Module: test_s3_router
// Unit tests for S3 URL routing, request dispatching, and REST CRUD lifecycles.
//
// Part of the Caisson distributed object storage engine.

module test_s3_router;

import caisson::core;
import caisson::http;
import caisson::s3;

fn bool test_router_str_contains(String hay, String needle) {
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

fn void test_s3_path_splitting() @test {
    String b = "";
    String k = "";

    s3::split_s3_path("/my-bucket", &b, &k);
    assert(b == "my-bucket");
    assert(k == "");

    s3::split_s3_path("/my-bucket/folder/nested/image.png", &b, &k);
    assert(b == "my-bucket");
    assert(k == "folder/nested/image.png");

    s3::split_s3_path("/", &b, &k);
    assert(b == "");
    assert(k == "");
}

fn void test_s3_full_rest_lifecycle() @test {
    String test_dir = "test_run_s3_router_dir";
    s3::S3Context ctx = s3::context_init(test_dir, 9000, false);

    // 1. Create bucket "vault"
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.PUT;
        req.path = "/vault";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        resp.free();
    }

    // 2. Head bucket
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.HEAD;
        req.path = "/vault";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        resp.free();
    }

    // 3. Put object "vault/keys.txt"
    String body_data = "caisson-distributed-secret-payload";
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.PUT;
        req.path = "/vault/keys.txt";
        req.body = body_data.ptr;
        req.body_len = body_data.len;

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String etag = resp.headers[0].value;
        assert(etag.len > 0);
        resp.free();
    }

    // 4. Get object "vault/keys.txt"
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/vault/keys.txt";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String fetched_body = (String)resp.body.data[0 : resp.body.len];
        assert(fetched_body == body_data);
        resp.free();
    }

    // 5. Get object with byte Range: bytes=0-6 ("caisson")
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/vault/keys.txt";
        req.range = (http::ByteRange){ .start = 0, .end = 6, .is_suffix = false, .is_valid = true };

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 206);
        String slice_body = (String)resp.body.data[0 : resp.body.len];
        assert(slice_body == "caisson");
        resp.free();
    }

    // 6. List objects in bucket
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.GET;
        req.path = "/vault";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 200);
        String list_xml = (String)resp.body.data[0 : resp.body.len];
        assert(test_router_str_contains(list_xml, "keys.txt"));
        resp.free();
    }

    // 7. Delete object
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.DELETE;
        req.path = "/vault/keys.txt";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 204);
        resp.free();
    }

    // 8. Delete bucket
    {
        http::HttpRequest req = http::request_init();
        req.method = http::HttpMethod.DELETE;
        req.path = "/vault";

        http::HttpResponse resp = http::response_init();
        s3::s3_route_request(&req, &resp, &ctx);

        assert(resp.status_code == 204);
        resp.free();
    }

    ctx.free();
}
