// Module: caisson::s3
// RESTful request dispatcher and S3 path router.
//
// Part of the Caisson distributed object storage engine.

module caisson::s3;

import caisson::core;
import caisson::http;

// Decomposes an S3 path "/bucket/key" into bucket and object key parts.
fn void split_s3_path(String raw_path, String* out_bucket, String* out_key) {
    *out_bucket = "";
    *out_key = "";

    if (raw_path.len == 0 || raw_path == "/") return;

    usz start = (raw_path[0] == '/') ? 1 : 0;
    if (start >= raw_path.len) return;

    usz slash_pos = raw_path.len;
    for (usz i = start; i < raw_path.len; i++) {
        if (raw_path[i] == '/') {
            slash_pos = i;
            break;
        }
    }

    if (slash_pos == raw_path.len) {
        *out_bucket = (String)raw_path[start : raw_path.len - start];
    } else {
        *out_bucket = (String)raw_path[start : slash_pos - start];
        *out_key = (String)raw_path[slash_pos + 1 : raw_path.len - (slash_pos + 1)];
    }
}

// Main S3 request routing dispatcher callback for HttpServer.
fn void s3_route_request(http::HttpRequest* req, http::HttpResponse* resp, void* user_data) {
    if (user_data == null) {
        resp.set_status(500, "Internal Server Error");
        return;
    }

    S3Context* ctx = (S3Context*)user_data;

    // Root path: ListAllMyBuckets or Web Dashboard
    if (req.path.len == 0 || req.path == "/") {
        if (req.method == http::HttpMethod.GET) {
            handle_list_buckets(ctx, req, resp);
        } else {
            resp.set_status(405, "Method Not Allowed");
        }
        return;
    }

    String bucket = "";
    String key = "";
    split_s3_path(req.path, &bucket, &key);

    if (bucket.len == 0) {
        resp.set_status(400, "Bad Request");
        return;
    }

    // Bucket-level operations (key is empty)
    if (key.len == 0) {
        switch (req.method) {
            case http::HttpMethod.GET:
                handle_list_objects_v2(ctx, req, resp, bucket);
                break;
            case http::HttpMethod.PUT:
                handle_create_bucket(ctx, req, resp, bucket);
                break;
            case http::HttpMethod.DELETE:
                handle_delete_bucket(ctx, req, resp, bucket);
                break;
            case http::HttpMethod.HEAD:
                handle_head_bucket(ctx, req, resp, bucket);
                break;
            default:
                resp.set_status(405, "Method Not Allowed");
                break;
        }
        return;
    }

    // Object and multipart operations
    switch (req.method) {
        case http::HttpMethod.GET:
            handle_get_object(ctx, req, resp, bucket, key);
            break;

        case http::HttpMethod.HEAD:
            handle_head_object(ctx, req, resp, bucket, key);
            break;

        case http::HttpMethod.PUT:
            if (req.has_query_param("partNumber") && req.has_query_param("uploadId")) {
                String pnum_str = req.get_query_param("partNumber");
                uint pnum = (uint)http::parse_long(pnum_str);
                String uid = req.get_query_param("uploadId");
                handle_upload_part(ctx, req, resp, bucket, key, uid, pnum);
            } else {
                handle_put_object(ctx, req, resp, bucket, key);
            }
            break;

        case http::HttpMethod.DELETE:
            if (req.has_query_param("uploadId")) {
                String uid = req.get_query_param("uploadId");
                handle_abort_multipart(ctx, req, resp, bucket, key, uid);
            } else {
                handle_delete_object(ctx, req, resp, bucket, key);
            }
            break;

        case http::HttpMethod.POST:
            if (req.has_query_param("uploads")) {
                handle_initiate_multipart(ctx, req, resp, bucket, key);
            } else if (req.has_query_param("uploadId")) {
                String uid = req.get_query_param("uploadId");
                handle_complete_multipart(ctx, req, resp, bucket, key, uid);
            } else {
                resp.set_status(400, "Bad Request");
            }
            break;

        default:
            resp.set_status(405, "Method Not Allowed");
            break;
    }
}
