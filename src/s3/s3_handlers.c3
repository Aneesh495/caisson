// Module: caisson::s3
// S3 REST operation handlers: bucket management, object CRUD, range reads, and multipart uploads.
//
// Part of the Caisson distributed object storage engine.

module caisson::s3;

import std::core::mem;
import caisson::core;
import caisson::hash;
import caisson::http;
import caisson::index;
import caisson::multipart;

// Helper to construct composite storage key: "b:<bucket>/<key>"
fn String make_storage_key(String bucket, String key, char* out_buf) {
    out_buf[0] = 'b';
    out_buf[1] = ':';
    usz idx = 2;
    if (bucket.len > 0) {
        mem::copy(out_buf + idx, bucket.ptr, (sz)bucket.len);
        idx += bucket.len;
    }
    out_buf[idx++] = '/';
    if (key.len > 0) {
        mem::copy(out_buf + idx, key.ptr, (sz)key.len);
        idx += key.len;
    }
    return (String)out_buf[0 : idx];
}

// Helper to construct multipart part key: "mp:<upload_id>/<part_number>"
fn String make_part_key(String upload_id, uint part_number, char* out_buf) {
    out_buf[0] = 'm';
    out_buf[1] = 'p';
    out_buf[2] = ':';
    usz idx = 3;
    mem::copy(out_buf + idx, upload_id.ptr, (sz)upload_id.len);
    idx += upload_id.len;
    out_buf[idx++] = '/';
    char[16] num_buf;
    usz n_len = http::int_to_ascii((long)part_number, &num_buf[0]);
    mem::copy(out_buf + idx, &num_buf[0], (sz)n_len);
    idx += n_len;
    return (String)out_buf[0 : idx];
}

// GET / -> ListAllMyBuckets
fn void handle_list_buckets(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp) {
    format_list_buckets_xml(resp, &ctx.bucket_reg);
}

// PUT /<bucket> -> CreateBucket
fn void handle_create_bucket(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket) {
    if (!index::validate_bucket_name(bucket)) {
        format_s3_error(resp, "InvalidBucketName", bucket, "");
        return;
    }

    core::Result res = ctx.bucket_reg.create_bucket(bucket, "us-east-1");
    if (!res.is_ok()) {
        format_s3_error(resp, "BucketAlreadyExists", bucket, "");
        return;
    }

    resp.set_status(200, "OK");
    resp.add_header("Location", bucket);
}

// DELETE /<bucket> -> DeleteBucket
fn void handle_delete_bucket(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket) {
    core::Result res = ctx.bucket_reg.delete_bucket(bucket);
    if (!res.is_ok()) {
        if (res.code == core::StorageError.NOT_FOUND) {
            format_s3_error(resp, "NoSuchBucket", bucket, "");
        } else {
            format_s3_error(resp, "BucketNotEmpty", bucket, "");
        }
        return;
    }

    resp.set_status(204, "No Content");
}

// HEAD /<bucket> -> HeadBucket
fn void handle_head_bucket(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    resp.set_status(200, "OK");
}

// GET /<bucket>?list-type=2 -> ListObjectsV2
fn void handle_list_objects_v2(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    String prefix = req.get_query_param("prefix");
    String delimiter = req.get_query_param("delimiter");
    String max_keys_str = req.get_query_param("max-keys");
    uint max_keys = 1000;
    if (max_keys_str.len > 0) {
        long mk = http::parse_long(max_keys_str);
        if (mk > 0 && mk <= 1000) max_keys = (uint)mk;
    }

    index::ListResult list_res = ctx.obj_index.list_objects_v2(bucket, prefix, delimiter, "", max_keys);
    format_list_objects_v2_xml(resp, bucket, prefix, max_keys, &list_res);
}

// PUT /<bucket>/<key> -> PutObject
fn void handle_put_object(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket, String key) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    // Compute MD5 hex checksum for ETag
    char[16] digest;
    hash::md5_hash(req.body, req.body_len, &digest[0]);
    char[33] md5_hex;
    String etag = core::hex_encode(&digest[0], 16, &md5_hex[0]);

    char[512] sk_buf;
    String storage_key = make_storage_key(bucket, key, &sk_buf[0]);

    core::Result put_res = ctx.storage.put(storage_key, req.body, req.body_len);
    if (!put_res.is_ok()) {
        format_s3_error(resp, "InternalError", key, "");
        return;
    }

    String ct = req.get_header("content-type");
    if (ct.len == 0) ct = "application/octet-stream";

    index::ObjectMeta meta = index::object_meta_init(bucket, key, (ulong)req.body_len, etag, ct);
    ctx.obj_index.insert(meta);

    resp.set_status(200, "OK");
    char[64] quoted_etag;
    quoted_etag[0] = '"';
    mem::copy(&quoted_etag[1], etag.ptr, (sz)etag.len);
    quoted_etag[1 + etag.len] = '"';
    resp.add_header("ETag", (String)quoted_etag[0 : 2 + etag.len]);
}

// GET /<bucket>/<key> -> GetObject (supports RFC 7233 byte ranges)
fn void handle_get_object(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket, String key) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    index::ObjectMeta* meta = ctx.obj_index.get(bucket, key);
    if (meta == null) {
        format_s3_error(resp, "NoSuchKey", key, "");
        return;
    }

    char[512] sk_buf;
    String storage_key = make_storage_key(bucket, key, &sk_buf[0]);

    core::Buffer val_buf = core::buffer_init(1024);
    core::Result get_res = ctx.storage.get(storage_key, &val_buf);
    if (!get_res.is_ok()) {
        val_buf.free();
        format_s3_error(resp, "NoSuchKey", key, "");
        return;
    }

    char[64] quoted_etag;
    quoted_etag[0] = '"';
    mem::copy(&quoted_etag[1], &meta.etag[0], (sz)meta.etag_len);
    quoted_etag[1 + meta.etag_len] = '"';
    resp.add_header("ETag", (String)quoted_etag[0 : 2 + meta.etag_len]);

    String ct = (String)meta.content_type[0:meta.content_type_len];
    resp.add_header("Content-Type", ct);
    resp.add_header("Accept-Ranges", "bytes");

    // Check for Range request
    if (req.range.is_valid && val_buf.len > 0) {
        long start = req.range.start;
        long end = req.range.end;

        if (req.range.is_suffix) {
            // Suffix range: last N bytes
            if (start > (long)val_buf.len) start = (long)val_buf.len;
            start = (long)val_buf.len - start;
            end = (long)val_buf.len - 1;
        } else {
            if (end == -1 || end >= (long)val_buf.len) {
                end = (long)val_buf.len - 1;
            }
        }

        if (start < 0 || start > end || start >= (long)val_buf.len) {
            format_s3_error(resp, "InvalidRange", key, "");
            val_buf.free();
            return;
        }

        usz slice_len = (usz)(end - start + 1);
        resp.set_status(206, "Partial Content");

        // Format Content-Range: bytes start-end/total
        core::Buffer cr_b = core::buffer_init(64);
        cr_b.append_string("bytes ");
        char[16] num_buf;
        usz l = http::int_to_ascii(start, &num_buf[0]);
        cr_b.append_bytes(&num_buf[0], l);
        cr_b.append_string("-");
        l = http::int_to_ascii(end, &num_buf[0]);
        cr_b.append_bytes(&num_buf[0], l);
        cr_b.append_string("/");
        l = http::int_to_ascii((long)val_buf.len, &num_buf[0]);
        cr_b.append_bytes(&num_buf[0], l);

        resp.add_header("Content-Range", (String)cr_b.data[0 : cr_b.len]);
        resp.set_body_bytes(val_buf.data + start, slice_len);

        cr_b.free();
    } else {
        resp.set_status(200, "OK");
        resp.set_body_bytes(val_buf.data, val_buf.len);
    }

    val_buf.free();
}

// HEAD /<bucket>/<key> -> HeadObject
fn void handle_head_object(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket, String key) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    index::ObjectMeta* meta = ctx.obj_index.get(bucket, key);
    if (meta == null) {
        format_s3_error(resp, "NoSuchKey", key, "");
        return;
    }

    resp.set_status(200, "OK");
    char[64] quoted_etag;
    quoted_etag[0] = '"';
    mem::copy(&quoted_etag[1], &meta.etag[0], (sz)meta.etag_len);
    quoted_etag[1 + meta.etag_len] = '"';
    resp.add_header("ETag", (String)quoted_etag[0 : 2 + meta.etag_len]);

    String ct = (String)meta.content_type[0:meta.content_type_len];
    resp.add_header("Content-Type", ct);
    resp.add_header("Accept-Ranges", "bytes");

    char[32] sz_buf;
    usz sz_l = http::int_to_ascii((long)meta.size, &sz_buf[0]);
    resp.add_header("Content-Length", (String)sz_buf[0 : sz_l]);
}

// DELETE /<bucket>/<key> -> DeleteObject
fn void handle_delete_object(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket, String key) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    char[512] sk_buf;
    String storage_key = make_storage_key(bucket, key, &sk_buf[0]);

    ctx.storage.delete(storage_key);
    ctx.obj_index.delete(bucket, key);

    resp.set_status(204, "No Content");
}

// POST /<bucket>/<key>?uploads -> CreateMultipartUpload
fn void handle_initiate_multipart(S3Context* ctx, http::HttpRequest* req, http::HttpResponse* resp, String bucket, String key) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    char[37] upload_id_buf;
    core::Result res = ctx.mp_manager.initiate_upload(bucket, key, &upload_id_buf[0]);
    if (!res.is_ok()) {
        format_s3_error(resp, "InternalError", key, "");
        return;
    }

    String uid_str = (String)upload_id_buf[0:36];
    format_initiate_multipart_xml(resp, bucket, key, uid_str);
}

// PUT /<bucket>/<key>?partNumber=X&uploadId=Y -> UploadPart
fn void handle_upload_part(
    S3Context* ctx,
    http::HttpRequest* req,
    http::HttpResponse* resp,
    String bucket,
    String key,
    String upload_id,
    uint part_number
) {
    char[33] etag_buf;
    core::Result res = ctx.mp_manager.upload_part(upload_id, part_number, req.body, req.body_len, &etag_buf[0]);
    if (!res.is_ok()) {
        if (res.code == core::StorageError.NOT_FOUND) {
            format_s3_error(resp, "NoSuchUpload", upload_id, "");
        } else {
            format_s3_error(resp, "InvalidPart", key, "");
        }
        return;
    }

    // Persist part bytes in Bitcask storage WAL
    char[128] pk_buf;
    String part_key = make_part_key(upload_id, part_number, &pk_buf[0]);
    ctx.storage.put(part_key, req.body, req.body_len);

    String out_etag = (String)etag_buf[0:32];
    resp.set_status(200, "OK");
    char[64] quoted_etag;
    quoted_etag[0] = '"';
    mem::copy(&quoted_etag[1], out_etag.ptr, (sz)out_etag.len);
    quoted_etag[1 + out_etag.len] = '"';
    resp.add_header("ETag", (String)quoted_etag[0 : 2 + out_etag.len]);
}

// POST /<bucket>/<key>?uploadId=Y -> CompleteMultipartUpload
fn void handle_complete_multipart(
    S3Context* ctx,
    http::HttpRequest* req,
    http::HttpResponse* resp,
    String bucket,
    String key,
    String upload_id
) {
    index::Bucket* b = ctx.bucket_reg.get_bucket(bucket);
    if (b == null) {
        format_s3_error(resp, "NoSuchBucket", bucket, "");
        return;
    }

    const uint MAX_PARTS = 100;
    multipart::ClientPart[MAX_PARTS] parts;
    uint part_count = 0;

    core::Result xml_res = parse_complete_multipart_xml(req.body, req.body_len, &parts[0], MAX_PARTS, &part_count);
    if (!xml_res.is_ok() || part_count == 0) {
        format_s3_error(resp, "InvalidPart", key, "");
        return;
    }

    char[64] composite_etag_buf;
    core::Result comp_res = ctx.mp_manager.complete_upload(
        upload_id,
        &parts[0],
        part_count,
        &composite_etag_buf[0]
    );

    if (!comp_res.is_ok()) {
        format_s3_error(resp, "InvalidPart", key, "");
        return;
    }

    usz etag_len = 0;
    while (composite_etag_buf[etag_len] != '\0' && etag_len < 63) etag_len++;
    String composite_etag = (String)composite_etag_buf[0 : etag_len];

    // Assemble stored parts into one contiguous object
    core::Buffer assembled = core::buffer_init(4096);
    for (uint i = 0; i < part_count; i++) {
        char[128] pk_buf;
        String part_key = make_part_key(upload_id, parts[i].part_number, &pk_buf[0]);
        core::Buffer p_buf = core::buffer_init(1024);
        core::Result r = ctx.storage.get(part_key, &p_buf);
        if (r.is_ok()) {
            assembled.append_bytes(p_buf.data, p_buf.len);
            ctx.storage.delete(part_key);
        }
        p_buf.free();
    }

    // Persist complete object into Bitcask WAL
    char[512] sk_buf;
    String storage_key = make_storage_key(bucket, key, &sk_buf[0]);
    ctx.storage.put(storage_key, assembled.data, assembled.len);

    // Record composite object in index
    index::ObjectMeta meta = index::object_meta_init(bucket, key, (ulong)assembled.len, composite_etag, "application/octet-stream");
    ctx.obj_index.insert(meta);

    format_complete_multipart_xml(resp, bucket, key, composite_etag);
    assembled.free();
}

// DELETE /<bucket>/<key>?uploadId=Y -> AbortMultipartUpload
fn void handle_abort_multipart(
    S3Context* ctx,
    http::HttpRequest* req,
    http::HttpResponse* resp,
    String bucket,
    String key,
    String upload_id
) {
    core::Result res = ctx.mp_manager.abort_upload(upload_id);
    if (!res.is_ok()) {
        format_s3_error(resp, "NoSuchUpload", upload_id, "");
        return;
    }

    for (uint p = 1; p <= 100; p++) {
        char[128] pk_buf;
        String part_key = make_part_key(upload_id, p, &pk_buf[0]);
        ctx.storage.delete(part_key);
    }

    resp.set_status(204, "No Content");
}
