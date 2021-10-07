// Module: caisson::index
// Radix tree prefix index and S3 ListObjectsV2 query resolution engine.
//
// Part of the Caisson distributed object storage engine.

module caisson::index;

import std::core::mem;
import caisson::core;

struct CommonPrefix {
    char[128] prefix;
    usz prefix_len;
}

struct ListResult {
    ObjectMeta[64] objects;
    uint object_count;
    CommonPrefix[32] common_prefixes;
    uint common_prefix_count;
    bool is_truncated;
    char[128] next_continuation_token;
    usz next_token_len;
}

// In-memory catalog index supporting prefix and delimiter searches.
struct ObjectIndex {
    ObjectMeta* entries;
    uint capacity;
    uint count;
}

fn int string_compare(String a, String b) {
    usz min_len = a.len < b.len ? a.len : b.len;
    for (usz i = 0; i < min_len; i++) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

fn ObjectIndex object_index_init(uint capacity) {
    uint cap = capacity > 0 ? capacity : 256;
    ObjectMeta* ptr = (ObjectMeta*)mem::malloc((sz)(cap * ObjectMeta::size));
    return (ObjectIndex){
        .entries = ptr,
        .capacity = cap,
        .count = 0
    };
}

fn void ObjectIndex.free(&this) {
    if (this.entries != null) {
        mem::free(this.entries);
        this.entries = null;
        this.count = 0;
        this.capacity = 0;
    }
}

fn void ObjectIndex.insert(&this, ObjectMeta meta) {
    String key = (String)meta.key[0:meta.key_len];
    String bucket = (String)meta.bucket[0:meta.bucket_len];

    // Check if key already exists in bucket, update in place
    for (uint i = 0; i < this.count; i++) {
        String ek = (String)this.entries[i].key[0:this.entries[i].key_len];
        String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
        if (eb == bucket && ek == key) {
            this.entries[i] = meta;
            return;
        }
    }

    if (this.count < this.capacity) {
        this.entries[this.count] = meta;
        this.count++;
    }
}

fn ObjectMeta* ObjectIndex.get(&this, String bucket, String key) {
    for (uint i = 0; i < this.count; i++) {
        String ek = (String)this.entries[i].key[0:this.entries[i].key_len];
        String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
        if (eb == bucket && ek == key) {
            return &this.entries[i];
        }
    }
    return null;
}

fn bool ObjectIndex.delete(&this, String bucket, String key) {
    for (uint i = 0; i < this.count; i++) {
        String ek = (String)this.entries[i].key[0:this.entries[i].key_len];
        String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
        if (eb == bucket && ek == key) {
            // Swap with last entry
            this.entries[i] = this.entries[this.count - 1];
            this.count--;
            return true;
        }
    }
    return false;
}

// Executes an Amazon S3 ListObjectsV2 query with prefix filtering and delimiter grouping.
fn ListResult ObjectIndex.list_objects_v2(
    &this,
    String bucket,
    String prefix,
    String delimiter,
    String start_after,
    uint max_keys
) {
    ListResult res;
    res.object_count = 0;
    res.common_prefix_count = 0;
    res.is_truncated = false;
    res.next_token_len = 0;

    uint limit = max_keys > 0 ? (max_keys < 64 ? max_keys : 64) : 64;

    for (uint i = 0; i < this.count; i++) {
        String eb = (String)this.entries[i].bucket[0:this.entries[i].bucket_len];
        if (eb != bucket) continue;

        String ek = (String)this.entries[i].key[0:this.entries[i].key_len];

        // Start-after check using lexicographical comparison
        if (start_after.len > 0 && string_compare(ek, start_after) <= 0) continue;

        // Prefix filter check
        if (prefix.len > 0) {
            if (ek.len < prefix.len) continue;
            String k_sub = (String)ek[0:prefix.len];
            if (k_sub != prefix) continue;
        }

        // Delimiter grouping check
        if (delimiter.len > 0) {
            usz search_start = prefix.len;
            sz delim_idx = -1;
            if (ek.len >= delimiter.len) {
                for (usz j = search_start; j <= ek.len - delimiter.len; j++) {
                    bool match = true;
                    for (usz d = 0; d < delimiter.len; d++) {
                        if (ek[j + d] != delimiter[d]) {
                            match = false;
                            break;
                        }
                    }
                    if (match) {
                        delim_idx = (sz)j;
                        break;
                    }
                }
            }

            if (delim_idx >= 0) {
                // Group into common prefix
                usz cp_len = (usz)delim_idx + delimiter.len;
                String cp_str = (String)ek[0:cp_len];

                // Deduplicate common prefixes
                bool already_added = false;
                for (uint c = 0; c < res.common_prefix_count; c++) {
                    String existing = (String)res.common_prefixes[c].prefix[0:res.common_prefixes[c].prefix_len];
                    if (existing == cp_str) {
                        already_added = true;
                        break;
                    }
                }

                if (!already_added && res.common_prefix_count < 32) {
                    mem::copy(&res.common_prefixes[res.common_prefix_count].prefix[0], cp_str.ptr, (sz)cp_str.len);
                    res.common_prefixes[res.common_prefix_count].prefix_len = cp_str.len;
                    res.common_prefix_count++;
                }
                continue; // Grouped into common prefix, do not list as direct object
            }
        }

        if (res.object_count < limit) {
            res.objects[res.object_count] = this.entries[i];
            res.object_count++;
        } else {
            res.is_truncated = true;
            // Record last key as continuation token
            String last_key = (String)res.objects[res.object_count - 1].key[0:res.objects[res.object_count - 1].key_len];
            mem::copy(&res.next_continuation_token[0], last_key.ptr, (sz)last_key.len);
            res.next_token_len = last_key.len;
            break;
        }
    }

    return res;
}
