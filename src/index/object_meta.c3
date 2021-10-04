// Module: caisson::index
// Object metadata representation, ETag tracking, and MIME content headers.
//
// Part of the Caisson distributed object storage engine.

module caisson::index;

import std::core::mem;
import caisson::core;

struct ObjectMeta {
    char[256] key;
    usz key_len;
    char[64] bucket;
    usz bucket_len;
    char[40] version_id;
    usz version_id_len;
    ulong size;
    char[33] etag;
    char[64] content_type;
    usz content_type_len;
    long last_modified;
    bool is_delete_marker;
    uint k_data;
    uint m_parity;
    usz shard_size;
}

fn ObjectMeta object_meta_init(
    String bucket,
    String key,
    ulong size,
    String etag,
    String content_type
) {
    ObjectMeta meta;
    meta.bucket_len = bucket.len < 63 ? bucket.len : 63;
    mem::copy(&meta.bucket[0], bucket.ptr, (sz)meta.bucket_len);
    meta.bucket[meta.bucket_len] = '\0';

    meta.key_len = key.len < 255 ? key.len : 255;
    mem::copy(&meta.key[0], key.ptr, (sz)meta.key_len);
    meta.key[meta.key_len] = '\0';

    meta.size = size;

    usz etag_len = etag.len < 32 ? etag.len : 32;
    mem::copy(&meta.etag[0], etag.ptr, (sz)etag_len);
    meta.etag[etag_len] = '\0';

    meta.content_type_len = content_type.len < 63 ? content_type.len : 63;
    if (meta.content_type_len > 0) {
        mem::copy(&meta.content_type[0], content_type.ptr, (sz)meta.content_type_len);
    } else {
        String def_ct = "application/octet-stream";
        mem::copy(&meta.content_type[0], def_ct.ptr, (sz)def_ct.len);
        meta.content_type_len = def_ct.len;
    }
    meta.content_type[meta.content_type_len] = '\0';

    meta.last_modified = core::current_time_seconds();
    meta.is_delete_marker = false;
    meta.version_id_len = 0;
    meta.version_id[0] = '\0';
    meta.k_data = 4;
    meta.m_parity = 2;
    meta.shard_size = 64 * 1024;

    return meta;
}
