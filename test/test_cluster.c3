// Module: test_cluster
// Unit tests for consistent hashing ring, quorum policies, and background scrubbing.
//
// Part of the Caisson distributed object storage engine.

module test_cluster;

import std::core::mem;
import caisson::core;
import caisson::hash;
import caisson::erasure;
import caisson::cluster;

fn void test_hash_ring_shard_isolation() @test {
    cluster::HashRing ring = cluster::ring_init(16);

    ring.add_drive(1, "/mnt/disk1", 1000000000);
    ring.add_drive(2, "/mnt/disk2", 1000000000);
    ring.add_drive(3, "/mnt/disk3", 1000000000);
    ring.add_drive(4, "/mnt/disk4", 1000000000);
    ring.add_drive(5, "/mnt/disk5", 1000000000);
    ring.add_drive(6, "/mnt/disk6", 1000000000);

    assert(ring.drive_count == 6);
    assert(ring.vnode_count > 0);

    uint[6] selected_drives;
    uint count = ring.locate_shards("analytics/2026/dataset.parquet", 6, &selected_drives[0]);
    assert(count == 6);

    // Verify failure domain isolation invariant: all 6 shards must reside on 6 distinct drives
    for (uint i = 0; i < 6; i++) {
        for (uint j = i + 1; j < 6; j++) {
            assert(selected_drives[i] != selected_drives[j],
                   "Shards of same stripe must never share a physical drive");
        }
    }
}

fn void test_quorum_policy_linearizability() @test {
    cluster::QuorumPolicy q3 = cluster::quorum_policy_init(3);
    assert(q3.write_quorum == 2);
    assert(q3.read_quorum == 2);
    assert(q3.is_linearizable() == true);
    assert(q3.has_write_quorum(2) == true);
    assert(q3.has_write_quorum(1) == false);

    cluster::QuorumPolicy q5 = cluster::quorum_policy_init(5);
    assert(q5.write_quorum == 3);
    assert(q5.read_quorum == 3);
    assert(q5.is_linearizable() == true);
}

fn void test_scrubber_auto_heal_bit_rot() @test {
    uint k = 4;
    uint m = 2;
    uint total = k + m;
    usz shard_size = 128;

    erasure::ReedSolomon rs = erasure::reedsolomon_init(k, m);
    defer rs.free();

    char** shards = (char**)mem::malloc((sz)(total * (usz)char*::size));
    defer mem::free(shards);

    char** original = (char**)mem::malloc((sz)(total * (usz)char*::size));
    defer mem::free(original);

    uint[6] expected_crcs;

    for (uint i = 0; i < total; i++) {
        shards[i] = (char*)mem::malloc((sz)shard_size);
        original[i] = (char*)mem::malloc((sz)shard_size);
    }
    defer {
        for (uint i = 0; i < total; i++) {
            mem::free(shards[i]);
            mem::free(original[i]);
        }
    }

    for (uint i = 0; i < k; i++) {
        for (usz j = 0; j < shard_size; j++) {
            shards[i][j] = (char)(((usz)i * 31 + j * 7 + 3) & 0xFF);
        }
    }

    rs.encode(shards, shard_size);

    for (uint i = 0; i < total; i++) {
        expected_crcs[i] = hash::crc32c_calculate(shards[i], shard_size);
        mem::copy(original[i], shards[i], (sz)shard_size);
    }

    // Corrupt shard 1 with simulated bit-rot (flip bits)
    shards[1][10] ^= (char)0xFF;
    shards[1][11] ^= (char)0xAA;

    cluster::Scrubber scrubber = cluster::scrubber_init();
    bool[6] repaired;
    for (uint i = 0; i < 6; i++) repaired[i] = false;

    core::Result scrub_res = scrubber.scrub_stripe(&rs, shards, &expected_crcs[0], &repaired[0], shard_size);
    assert(scrub_res.is_ok());
    assert(scrubber.metrics.corrupt_shards_detected == 1);
    assert(scrubber.metrics.shards_repaired == 1);
    assert(repaired[1] == true);

    // Verify auto-healed shard matches bit-for-bit with original
    for (usz j = 0; j < shard_size; j++) {
        assert(shards[1][j] == original[1][j], "Scrubber must restore bit-exact original shard data");
    }
}
