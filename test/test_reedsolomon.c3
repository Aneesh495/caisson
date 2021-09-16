// Module: test_reedsolomon
// Unit tests for systematic Reed-Solomon (K, M) erasure encoding, fault recovery, and striping.
//
// Part of the Caisson distributed object storage engine.

module test_reedsolomon;

import std::core::mem;
import caisson::core;
import caisson::erasure;

fn void test_reedsolomon_4_2_recovery() @test {
    uint k = 4;
    uint m = 2;
    uint total = k + m;
    usz shard_size = 256;

    erasure::ReedSolomon rs = erasure::reedsolomon_init(k, m);
    defer rs.free();

    char** shards = (char**)mem::malloc((sz)(total * (usz)char*::size));
    defer mem::free(shards);

    char** original_data = (char**)mem::malloc((sz)(k * (usz)char*::size));
    defer mem::free(original_data);

    bool* present = (bool*)mem::malloc((sz)(total * (usz)bool::size));
    defer mem::free(present);

    for (uint i = 0; i < total; i++) {
        shards[i] = (char*)mem::malloc((sz)shard_size);
        present[i] = true;
    }
    defer {
        for (uint i = 0; i < total; i++) {
            mem::free(shards[i]);
        }
    }

    for (uint i = 0; i < k; i++) {
        original_data[i] = (char*)mem::malloc((sz)shard_size);
        for (usz j = 0; j < shard_size; j++) {
            char val = (char)(((usz)i * 37 + j * 13 + 5) & 0xFF);
            shards[i][j] = val;
            original_data[i][j] = val;
        }
    }
    defer {
        for (uint i = 0; i < k; i++) {
            mem::free(original_data[i]);
        }
    }

    // Step 1: Systematic encode
    core::Result enc_res = rs.encode(shards, shard_size);
    assert(enc_res.is_ok());

    // Step 2: Test 1 data shard lost (shard 0)
    for (uint i = 0; i < total; i++) present[i] = true;
    present[0] = false;
    for (usz j = 0; j < shard_size; j++) shards[0][j] = 0;

    core::Result rec_res1 = rs.reconstruct(shards, present, shard_size);
    assert(rec_res1.is_ok());
    for (usz j = 0; j < shard_size; j++) {
        assert(shards[0][j] == original_data[0][j], "Recovered shard 0 must match original");
    }

    // Step 3: Test 2 data shards lost (shards 1 and 3)
    for (uint i = 0; i < total; i++) present[i] = true;
    present[1] = false;
    present[3] = false;
    for (usz j = 0; j < shard_size; j++) {
        shards[1][j] = 0;
        shards[3][j] = 0;
    }

    core::Result rec_res2 = rs.reconstruct(shards, present, shard_size);
    assert(rec_res2.is_ok());
    for (usz j = 0; j < shard_size; j++) {
        assert(shards[1][j] == original_data[1][j], "Recovered shard 1 must match original");
        assert(shards[3][j] == original_data[3][j], "Recovered shard 3 must match original");
    }

    // Step 4: Test 1 data shard + 1 parity shard lost (shards 2 and 4)
    for (uint i = 0; i < total; i++) present[i] = true;
    present[2] = false;
    present[4] = false;
    for (usz j = 0; j < shard_size; j++) {
        shards[2][j] = 0;
        shards[4][j] = 0;
    }

    core::Result rec_res3 = rs.reconstruct(shards, present, shard_size);
    assert(rec_res3.is_ok());
    for (usz j = 0; j < shard_size; j++) {
        assert(shards[2][j] == original_data[2][j], "Recovered shard 2 must match original");
    }

    // Step 5: Test 3 shards lost (shards 0, 1, 2) exceeding M=2 fault tolerance
    for (uint i = 0; i < total; i++) present[i] = true;
    present[0] = false;
    present[1] = false;
    present[2] = false;

    core::Result rec_res4 = rs.reconstruct(shards, present, shard_size);
    assert(rec_res4.is_err(), "Must fail when surviving shards < K");
    assert(rec_res4.code == core::StorageError.UNRECOVERABLE_STRIPE);
}

fn void test_reedsolomon_6_3_triple_failure_recovery() @test {
    uint k = 6;
    uint m = 3;
    uint total = k + m;
    usz shard_size = 128;

    erasure::ReedSolomon rs = erasure::reedsolomon_init(k, m);
    defer rs.free();

    char** shards = (char**)mem::malloc((sz)(total * (usz)char*::size));
    defer mem::free(shards);

    char** original_data = (char**)mem::malloc((sz)(k * (usz)char*::size));
    defer mem::free(original_data);

    bool* present = (bool*)mem::malloc((sz)(total * (usz)bool::size));
    defer mem::free(present);

    for (uint i = 0; i < total; i++) {
        shards[i] = (char*)mem::malloc((sz)shard_size);
        present[i] = true;
    }
    defer {
        for (uint i = 0; i < total; i++) {
            mem::free(shards[i]);
        }
    }

    for (uint i = 0; i < k; i++) {
        original_data[i] = (char*)mem::malloc((sz)shard_size);
        for (usz j = 0; j < shard_size; j++) {
            char val = (char)(((usz)i * 41 + j * 17 + 9) & 0xFF);
            shards[i][j] = val;
            original_data[i][j] = val;
        }
    }
    defer {
        for (uint i = 0; i < k; i++) {
            mem::free(original_data[i]);
        }
    }

    core::Result enc_res = rs.encode(shards, shard_size);
    assert(enc_res.is_ok());

    // Destroy 3 shards simultaneously: shards 0, 2, and 4
    present[0] = false;
    present[2] = false;
    present[4] = false;
    for (usz j = 0; j < shard_size; j++) {
        shards[0][j] = 0;
        shards[2][j] = 0;
        shards[4][j] = 0;
    }

    core::Result rec_res = rs.reconstruct(shards, present, shard_size);
    assert(rec_res.is_ok());

    for (usz j = 0; j < shard_size; j++) {
        assert(shards[0][j] == original_data[0][j]);
        assert(shards[2][j] == original_data[2][j]);
        assert(shards[4][j] == original_data[4][j]);
    }
}

fn void test_stripe_split_and_assemble() @test {
    uint k = 4;
    usz shard_size = 64;
    usz payload_len = 150; // Not a multiple of shard_size or K

    char[150] payload;
    for (usz i = 0; i < payload_len; i++) {
        payload[i] = (char)('A' + (i % 26));
    }

    char** data_shards = (char**)mem::malloc((sz)(k * (usz)char*::size));
    defer mem::free(data_shards);

    for (uint i = 0; i < k; i++) {
        data_shards[i] = (char*)mem::malloc((sz)shard_size);
    }
    defer {
        for (uint i = 0; i < k; i++) {
            mem::free(data_shards[i]);
        }
    }

    erasure::stripe_split_payload(&payload[0], payload_len, k, shard_size, data_shards);

    char[150] recovered;
    erasure::stripe_assemble_payload(data_shards, k, shard_size, payload_len, &recovered[0]);

    for (usz i = 0; i < payload_len; i++) {
        assert(recovered[i] == payload[i]);
    }
}
