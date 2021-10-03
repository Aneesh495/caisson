// Module: caisson::storage
// Content-Addressable Storage (CAS) deduplication engine using cryptographic digests.
//
// Part of the Caisson distributed object storage engine.

module caisson::storage;

import std::core::mem;
import caisson::core;
import caisson::hash;

struct CasEntry {
    char[65] hash_hex;
    char[128] storage_key;
    usz storage_key_len;
    uint ref_count;
    ulong payload_size;
    bool occupied;
}

struct CasTable {
    CasEntry[256] entries;
    uint count;
    ulong duplicate_bytes_saved;
}

fn CasTable cas_init() {
    CasTable table;
    table.count = 0;
    table.duplicate_bytes_saved = 0;
    for (uint i = 0; i < 256; i++) {
        table.entries[i].occupied = false;
        table.entries[i].ref_count = 0;
    }
    return table;
}

// Ingests a payload into the CAS index, returning an existing storage key if deduplicated.
fn bool CasTable.put(
    &this,
    char* payload,
    usz payload_len,
    String target_key,
    char* out_existing_key,
    usz* out_key_len
) {
    if (payload == null || payload_len == 0) return false;

    char[65] digest_hex;
    String hex = hash::sha256_hex(payload, payload_len, &digest_hex[0]);

    // Check if duplicate already exists
    for (uint i = 0; i < 256; i++) {
        if (this.entries[i].occupied) {
            String entry_hex = (String)this.entries[i].hash_hex[0:64];
            if (entry_hex == hex) {
                // Duplicate found: increment ref count and return existing key
                this.entries[i].ref_count++;
                this.duplicate_bytes_saved += payload_len;

                mem::copy(out_existing_key, &this.entries[i].storage_key[0], (sz)this.entries[i].storage_key_len);
                *out_key_len = this.entries[i].storage_key_len;
                return true; // Was deduplicated
            }
        }
    }

    // Register new unique payload
    for (uint i = 0; i < 256; i++) {
        if (!this.entries[i].occupied) {
            mem::copy(&this.entries[i].hash_hex[0], hex.ptr, 64);
            this.entries[i].hash_hex[64] = '\0';

            usz klen = target_key.len < 127 ? target_key.len : 127;
            mem::copy(&this.entries[i].storage_key[0], target_key.ptr, (sz)klen);
            this.entries[i].storage_key[klen] = '\0';
            this.entries[i].storage_key_len = klen;

            this.entries[i].ref_count = 1;
            this.entries[i].payload_size = (ulong)payload_len;
            this.entries[i].occupied = true;
            this.count++;
            return false; // Unique, not deduplicated
        }
    }

    return false;
}
