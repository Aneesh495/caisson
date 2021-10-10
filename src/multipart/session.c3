// Module: caisson::multipart
// Multipart upload session state, part tracking, and composite ETag models.
//
// Part of the Caisson distributed object storage engine.

module caisson::multipart;

import std::core::mem;
import caisson::core;

struct UploadPart {
    uint part_number;
    ulong size;
    char[33] etag;
    usz etag_len;
    long uploaded_at;
    bool occupied;
}

struct MultipartSession {
    char[40] upload_id;
    usz upload_id_len;
    char[64] bucket;
    usz bucket_len;
    char[256] key;
    usz key_len;
    long initiated_at;
    UploadPart[100] parts;
    uint part_count;
    bool completed;
    bool aborted;
    bool occupied;
}

fn MultipartSession session_init(
    String upload_id,
    String bucket,
    String key
) {
    MultipartSession s;
    s.upload_id_len = upload_id.len < 39 ? upload_id.len : 39;
    mem::copy(&s.upload_id[0], upload_id.ptr, (sz)s.upload_id_len);
    s.upload_id[s.upload_id_len] = '\0';

    s.bucket_len = bucket.len < 63 ? bucket.len : 63;
    mem::copy(&s.bucket[0], bucket.ptr, (sz)s.bucket_len);
    s.bucket[s.bucket_len] = '\0';

    s.key_len = key.len < 255 ? key.len : 255;
    mem::copy(&s.key[0], key.ptr, (sz)s.key_len);
    s.key[s.key_len] = '\0';

    s.initiated_at = core::current_time_seconds();
    s.part_count = 0;
    s.completed = false;
    s.aborted = false;
    s.occupied = true;

    for (uint i = 0; i < 100; i++) {
        s.parts[i].occupied = false;
    }

    return s;
}
