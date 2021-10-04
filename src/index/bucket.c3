// Module: caisson::index
// Bucket catalog, DNS compliance verification, and regional registry.
//
// Part of the Caisson distributed object storage engine.

module caisson::index;

import std::core::mem;
import caisson::core;

struct Bucket {
    char[64] name;
    usz name_len;
    long created_at;
    char[32] region;
    usz region_len;
    bool versioning_enabled;
    ulong object_count;
    ulong total_bytes;
    bool occupied;
}

// Validates bucket naming conforming to Amazon S3 DNS compliance rules:
// - Length between 3 and 63 characters
// - Lowercase letters, numbers, hyphens, and periods
// - Must start and end with a letter or digit
// - Cannot contain adjacent periods or hyphens adjacent to periods
fn bool validate_bucket_name(String name) {
    if (name.len < 3 || name.len > 63) return false;

    char first = name[0];
    if (!((first >= 'a' && first <= 'z') || (first >= '0' && first <= '9'))) {
        return false;
    }

    char last = name[name.len - 1];
    if (!((last >= 'a' && last <= 'z') || (last >= '0' && last <= '9'))) {
        return false;
    }

    char prev = '\0';
    for (usz i = 0; i < name.len; i++) {
        char c = name[i];
        bool is_valid = (c >= 'a' && c <= 'z') ||
                        (c >= '0' && c <= '9') ||
                        (c == '-') || (c == '.');
        if (!is_valid) return false;

        if (c == '.' && prev == '.') return false; // Consecutive periods forbidden
        if (c == '.' && prev == '-') return false;
        if (c == '-' && prev == '.') return false;

        prev = c;
    }

    return true;
}

struct BucketRegistry {
    Bucket[128] buckets;
    uint count;
}

fn BucketRegistry bucket_registry_init() {
    BucketRegistry reg;
    reg.count = 0;
    for (uint i = 0; i < 128; i++) {
        reg.buckets[i].occupied = false;
        reg.buckets[i].object_count = 0;
        reg.buckets[i].total_bytes = 0;
    }
    return reg;
}

fn core::Result BucketRegistry.create_bucket(
    &this,
    String name,
    String region
) {
    if (!validate_bucket_name(name)) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid bucket name");
    }

    // Check for existing bucket
    for (uint i = 0; i < 128; i++) {
        if (this.buckets[i].occupied) {
            String bname = (String)this.buckets[i].name[0:this.buckets[i].name_len];
            if (bname == name) {
                return core::result_err(core::StorageError.ALREADY_EXISTS, "Bucket already exists");
            }
        }
    }

    // Allocate slot
    for (uint i = 0; i < 128; i++) {
        if (!this.buckets[i].occupied) {
            mem::copy(&this.buckets[i].name[0], name.ptr, (sz)name.len);
            this.buckets[i].name[name.len] = '\0';
            this.buckets[i].name_len = name.len;

            mem::copy(&this.buckets[i].region[0], region.ptr, (sz)region.len);
            this.buckets[i].region[region.len] = '\0';
            this.buckets[i].region_len = region.len;

            this.buckets[i].created_at = core::current_time_seconds();
            this.buckets[i].versioning_enabled = false;
            this.buckets[i].object_count = 0;
            this.buckets[i].total_bytes = 0;
            this.buckets[i].occupied = true;
            this.count++;
            return core::result_ok();
        }
    }

    return core::result_err(core::StorageError.CAPACITY_EXCEEDED, "Bucket limit exceeded");
}

fn Bucket* BucketRegistry.get_bucket(&this, String name) {
    for (uint i = 0; i < 128; i++) {
        if (this.buckets[i].occupied) {
            String bname = (String)this.buckets[i].name[0:this.buckets[i].name_len];
            if (bname == name) {
                return &this.buckets[i];
            }
        }
    }
    return null;
}

fn core::Result BucketRegistry.delete_bucket(&this, String name) {
    for (uint i = 0; i < 128; i++) {
        if (this.buckets[i].occupied) {
            String bname = (String)this.buckets[i].name[0:this.buckets[i].name_len];
            if (bname == name) {
                if (this.buckets[i].object_count > 0) {
                    return core::result_err(core::StorageError.INVALID_ARGUMENT, "Bucket not empty");
                }
                this.buckets[i].occupied = false;
                this.count--;
                return core::result_ok();
            }
        }
    }
    return core::result_err(core::StorageError.NOT_FOUND, "Bucket not found");
}
