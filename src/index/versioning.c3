// Module: caisson::index
// Multi-Version Concurrency Control (MVCC) and delete marker versioning engine.
//
// Part of the Caisson distributed object storage engine.

module caisson::index;

import std::core::mem;
import caisson::core;

struct VersionEntry {
    char[256] key;
    usz key_len;
    char[64] bucket;
    usz bucket_len;
    char[40] version_id;
    usz version_id_len;
    ulong size;
    char[33] etag;
    long last_modified;
    bool is_delete_marker;
    bool is_latest;
    bool occupied;
}

struct VersionStore {
    VersionEntry* entries;
    uint capacity;
    uint count;
    core::RngState rng;
}

fn VersionStore version_store_init(uint capacity) {
    uint cap = capacity > 0 ? capacity : 128;
    VersionEntry* ptr = (VersionEntry*)mem::malloc((sz)(cap * VersionEntry::size));
    for (uint i = 0; i < cap; i++) {
        ptr[i].occupied = false;
    }

    VersionStore vs;
    vs.entries = ptr;
    vs.capacity = cap;
    vs.count = 0;
    vs.rng.init(99912345);
    return vs;
}

fn void VersionStore.free(&this) {
    if (this.entries != null) {
        mem::free(this.entries);
        this.entries = null;
        this.count = 0;
        this.capacity = 0;
    }
}

// Inserts a new object version, generating a unique RFC 4122 version ID and setting is_latest = true.
fn String VersionStore.put_version(
    &this,
    String bucket,
    String key,
    ulong size,
    String etag,
    bool is_delete_marker,
    char* out_version_id
) {
    core::Uuid u = core::uuid_v4(&this.rng);
    core::uuid_to_string(u, out_version_id);
    String vid_str = (String)out_version_id[0:36];

    // Clear is_latest on any prior version of same key
    for (uint i = 0; i < this.capacity; i++) {
        if (this.entries[i].occupied) {
            String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
            String ek = (String)this.entries[i].key[0:this.entries[i].key_len];
            if (eb == bucket && ek == key) {
                this.entries[i].is_latest = false;
            }
        }
    }

    // Allocate slot
    for (uint i = 0; i < this.capacity; i++) {
        if (!this.entries[i].occupied) {
            usz blen = bucket.len < 63 ? bucket.len : 63;
            mem::copy(&this.entries[i].bucket[0], bucket.ptr, (sz)blen);
            this.entries[i].bucket[blen] = '\0';
            this.entries[i].bucket_len = blen;

            usz klen = key.len < 255 ? key.len : 255;
            mem::copy(&this.entries[i].key[0], key.ptr, (sz)klen);
            this.entries[i].key[klen] = '\0';
            this.entries[i].key_len = klen;

            mem::copy(&this.entries[i].version_id[0], out_version_id, 36);
            this.entries[i].version_id[36] = '\0';
            this.entries[i].version_id_len = 36;

            this.entries[i].size = size;

            usz elen = etag.len < 32 ? etag.len : 32;
            mem::copy(&this.entries[i].etag[0], etag.ptr, (sz)elen);
            this.entries[i].etag[elen] = '\0';

            this.entries[i].last_modified = core::current_time_seconds();
            this.entries[i].is_delete_marker = is_delete_marker;
            this.entries[i].is_latest = true;
            this.entries[i].occupied = true;
            this.count++;
            return vid_str;
        }
    }

    return "";
}

fn VersionEntry* VersionStore.get_latest(&this, String bucket, String key) {
    for (uint i = 0; i < this.capacity; i++) {
        if (this.entries[i].occupied && this.entries[i].is_latest) {
            String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
            String ek = (String)this.entries[i].key[0:this.entries[i].key_len];
            if (eb == bucket && ek == key) {
                return &this.entries[i];
            }
        }
    }
    return null;
}
