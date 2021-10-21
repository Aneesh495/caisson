// Module: caisson::cluster
// Consistent hashing ring with virtual nodes (vnodes) and shard failure domain isolation.
//
// Part of the Caisson distributed object storage engine.

module caisson::cluster;

import std::core::mem;
import caisson::core;
import caisson::hash;

struct Vnode {
    ulong token;
    uint drive_id;
}

struct HashRing {
    Vnode[256] vnodes;
    uint vnode_count;
    uint vnodes_per_drive;
    StorageDrive[16] drives;
    uint drive_count;
}

fn HashRing ring_init(uint vnodes_per_drive) {
    HashRing r;
    r.vnode_count = 0;
    r.vnodes_per_drive = vnodes_per_drive > 0 ? (vnodes_per_drive < 32 ? vnodes_per_drive : 32) : 16;
    r.drive_count = 0;
    for (uint i = 0; i < 16; i++) {
        r.drives[i].occupied = false;
    }
    return r;
}

fn void HashRing.add_drive(&this, uint drive_id, String mount_path, ulong capacity) {
    if (this.drive_count >= 16) return;

    uint d_idx = this.drive_count;
    this.drives[d_idx] = drive_init(drive_id, mount_path, capacity);
    this.drive_count++;

    // Generate virtual nodes distributed on 64-bit ring
    core::RngState rng;
    rng.init((ulong)drive_id * 10007 + 31337);

    for (uint v = 0; v < this.vnodes_per_drive && this.vnode_count < 256; v++) {
        ulong token = rng.next();
        uint pos = this.vnode_count;
        this.vnodes[pos] = (Vnode){ .token = token, .drive_id = drive_id };
        this.vnode_count++;

        // Insertion sort to maintain sorted ring order
        while (pos > 0 && this.vnodes[pos].token < this.vnodes[pos - 1].token) {
            Vnode tmp = this.vnodes[pos];
            this.vnodes[pos] = this.vnodes[pos - 1];
            this.vnodes[pos - 1] = tmp;
            pos--;
        }
    }
}

// Maps an object key to N distinct physical drives to guarantee failure domain isolation.
// Shards belonging to the same erasure stripe are never placed on the same physical drive.
fn uint HashRing.locate_shards(
    &this,
    String key,
    uint shard_count,
    uint* out_drive_ids
) {
    if (this.vnode_count == 0 || shard_count == 0) return 0;

    // Hash key to find starting point on the ring
    char[32] key_hash;
    hash::sha256_hash(key.ptr, key.len, &key_hash[0]);
    ulong key_token = core::read_u64_be(&key_hash[0]);

    // Binary search for first vnode with token >= key_token
    uint low = 0;
    uint high = this.vnode_count;
    while (low < high) {
        uint mid = low + (high - low) / 2;
        if (this.vnodes[mid].token >= key_token) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    if (low >= this.vnode_count) low = 0; // Wrap around ring

    uint placed = 0;
    uint ring_idx = low;
    uint steps = 0;

    while (placed < shard_count && steps < this.vnode_count) {
        uint candidate_drive = this.vnodes[ring_idx].drive_id;

        // Check if drive is already selected for this stripe
        bool already_selected = false;
        for (uint i = 0; i < placed; i++) {
            if (out_drive_ids[i] == candidate_drive) {
                already_selected = true;
                break;
            }
        }

        if (!already_selected) {
            out_drive_ids[placed] = candidate_drive;
            placed++;
        }

        ring_idx = (ring_idx + 1) % this.vnode_count;
        steps++;
    }

    return placed;
}
