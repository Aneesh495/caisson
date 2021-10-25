// Module: caisson::cluster
// Background bit-rot integrity scrubber and automated Reed-Solomon auto-healing.
//
// Part of the Caisson distributed object storage engine.

module caisson::cluster;

import caisson::core;
import caisson::hash;
import caisson::erasure;

struct ScrubberMetrics {
    ulong stripes_scanned;
    ulong corrupt_shards_detected;
    ulong shards_repaired;
    ulong scan_duration_ms;
}

struct Scrubber {
    ScrubberMetrics metrics;
    bool is_running;
}

fn Scrubber scrubber_init() {
    return (Scrubber){
        .metrics = (ScrubberMetrics){
            .stripes_scanned = 0,
            .corrupt_shards_detected = 0,
            .shards_repaired = 0,
            .scan_duration_ms = 0
        },
        .is_running = false
    };
}

// Scans an in-memory stripe, verifies each shard against expected CRC32C,
// and auto-heals corrupted shards using the Reed-Solomon engine.
fn core::Result Scrubber.scrub_stripe(
    &this,
    erasure::ReedSolomon* rs,
    char** shards,
    uint* expected_crcs,
    bool* out_repaired,
    usz shard_size
) {
    if (rs == null || shards == null || expected_crcs == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid arguments to scrubber");
    }

    uint total = rs.total_shards;
    bool[32] shard_valid;
    bool[32] was_corrupt;
    uint healthy_count = 0;

    this.metrics.stripes_scanned++;

    for (uint i = 0; i < total; i++) {
        uint computed = hash::crc32c_calculate(shards[i], shard_size);
        if (computed == expected_crcs[i]) {
            shard_valid[i] = true;
            was_corrupt[i] = false;
            healthy_count++;
        } else {
            shard_valid[i] = false;
            was_corrupt[i] = true;
            this.metrics.corrupt_shards_detected++;
        }
    }

    if (healthy_count == total) {
        // Stripe is fully intact, no repair needed
        return core::result_ok();
    }

    if (healthy_count < rs.data_shards) {
        return core::result_err(core::StorageError.UNRECOVERABLE_STRIPE,
                                "Too many corrupted shards to repair stripe");
    }

    // Auto-heal missing or corrupted shards
    core::Result rec_res = rs.reconstruct(shards, &shard_valid[0], shard_size);
    if (rec_res.is_ok()) {
        for (uint i = 0; i < total; i++) {
            if (was_corrupt[i]) {
                this.metrics.shards_repaired++;
                if (out_repaired != null) out_repaired[i] = true;
                // Recompute updated checksum
                expected_crcs[i] = hash::crc32c_calculate(shards[i], shard_size);
            }
        }
    }

    return rec_res;
}
