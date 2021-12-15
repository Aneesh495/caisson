// Module: caisson::cli
// Storage engine and Galois Field erasure coding microbenchmark harness.
//
// Part of the Caisson distributed object storage engine.

module caisson::cli;

import std::io;
import std::core::mem;
import caisson::core;
import caisson::http;
import caisson::math;
import caisson::erasure;
import caisson::hash;
import caisson::storage;

fn int run_bench_command() {
    io::printn("");
    io::printn("================================================================================");
    io::printn("               CAISSON STORAGE ENGINE MICROBENCHMARK SUITE                      ");
    io::printn("================================================================================");
    io::printn("");

    // 1. GF(2^8) Vector Multiplication Benchmark
    {
        const usz BUF_SIZE = 16 * 1024 * 1024; // 16 MB
        char* src = (char*)mem::malloc((sz)BUF_SIZE);
        char* dst = (char*)mem::malloc((sz)BUF_SIZE);

        for (usz i = 0; i < BUF_SIZE; i++) src[i] = (char)(i & 0xFF);

        ulong t0 = core::monotonic_nanos();
        math::gf_vec_mul(src, dst, 0x57, BUF_SIZE);
        ulong t1 = core::monotonic_nanos();

        ulong elapsed_ns = t1 - t0;
        double secs = (double)elapsed_ns / 1000000000.0;
        double mb = (double)BUF_SIZE / (1024.0 * 1024.0);
        double gb_sec = (mb / 1024.0) / secs;

        io::printfn("[BENCH] GF(2^8) Vector Multiply (16 MB):    %8.2f ms  |  %6.2f GB/s", secs * 1000.0, gb_sec);

        mem::free(src);
        mem::free(dst);
    }

    // 2. CRC32C Hashing Throughput
    {
        const usz BUF_SIZE = 16 * 1024 * 1024; // 16 MB
        char* buf = (char*)mem::malloc((sz)BUF_SIZE);
        for (usz i = 0; i < BUF_SIZE; i++) buf[i] = (char)(i & 0x7F);

        ulong t0 = core::monotonic_nanos();
        uint crc = hash::crc32c_calculate(buf, BUF_SIZE);
        ulong t1 = core::monotonic_nanos();

        ulong elapsed_ns = t1 - t0;
        double secs = (double)elapsed_ns / 1000000000.0;
        double mb = (double)BUF_SIZE / (1024.0 * 1024.0);
        double gb_sec = (mb / 1024.0) / secs;

        io::printfn("[BENCH] CRC32C Hardware Checksum (16 MB):   %8.2f ms  |  %6.2f GB/s (CRC=0x%08X)", secs * 1000.0, gb_sec, crc);
        mem::free(buf);
    }

    // 3. SHA-256 Hashing Throughput
    {
        const usz BUF_SIZE = 8 * 1024 * 1024; // 8 MB
        char* buf = (char*)mem::malloc((sz)BUF_SIZE);
        for (usz i = 0; i < BUF_SIZE; i++) buf[i] = (char)(i & 0x3F);

        char[32] digest;
        ulong t0 = core::monotonic_nanos();
        hash::sha256_hash(buf, BUF_SIZE, &digest[0]);
        ulong t1 = core::monotonic_nanos();

        ulong elapsed_ns = t1 - t0;
        double secs = (double)elapsed_ns / 1000000000.0;
        double mb = (double)BUF_SIZE / (1024.0 * 1024.0);
        double mb_sec = mb / secs;

        io::printfn("[BENCH] SHA-256 Cryptographic Hash (8 MB):  %8.2f ms  |  %6.2f MB/s", secs * 1000.0, mb_sec);
        mem::free(buf);
    }

    // 4. Reed-Solomon RS(4, 2) Cauchy Encoding Throughput
    {
        erasure::ReedSolomon rs = erasure::reedsolomon_init(4, 2);
        const usz SHARD_SZ = 256 * 1024; // 256 KB per shard -> 1 MB data per stripe
        char*[6] shards;
        for (int i = 0; i < 6; i++) {
            shards[i] = (char*)mem::malloc((sz)SHARD_SZ);
            for (usz j = 0; j < SHARD_SZ; j++) shards[i][j] = (char)(((usz)i + j) & 0xFF);
        }

        const int ITERS = 40; // 40 MB data encoded
        ulong t0 = core::monotonic_nanos();
        for (int it = 0; it < ITERS; it++) {
            rs.encode(&shards[0], SHARD_SZ);
        }
        ulong t1 = core::monotonic_nanos();

        ulong elapsed_ns = t1 - t0;
        double secs = (double)elapsed_ns / 1000000000.0;
        double mb = (double)(ITERS * 4 * SHARD_SZ) / (1024.0 * 1024.0);
        double mb_sec = mb / secs;

        io::printfn("[BENCH] RS(4, 2) Cauchy Encode (40 MB):     %8.2f ms  |  %6.2f MB/s", secs * 1000.0, mb_sec);

        // 5. Reed-Solomon RS(4, 2) Dual Shard Failure Reconstruction
        bool[6] valid = { true, false, true, false, true, true }; // 2 failed shards
        ulong rt0 = core::monotonic_nanos();
        for (int it = 0; it < ITERS; it++) {
            rs.reconstruct(&shards[0], &valid[0], SHARD_SZ);
        }
        ulong rt1 = core::monotonic_nanos();

        ulong relapsed_ns = rt1 - rt0;
        double rsecs = (double)relapsed_ns / 1000000000.0;
        double rmb_sec = mb / rsecs;

        io::printfn("[BENCH] RS(4, 2) 2-Shard Repair (40 MB):    %8.2f ms  |  %6.2f MB/s", rsecs * 1000.0, rmb_sec);

        for (int i = 0; i < 6; i++) mem::free(shards[i]);
    }

    // 6. Bitcask Log-Structured Append & Read Benchmark
    {
        String bench_dir = "bench_bitcask_tmp";
        storage::Bitcask bc = storage::bitcask_open(bench_dir, 64 * 1024 * 1024);

        const int NUM_RECORDS = 1000;
        const usz VAL_SIZE = 4096; // 4 KB per record -> 4 MB total
        char* val = (char*)mem::malloc((sz)VAL_SIZE);
        for (usz i = 0; i < VAL_SIZE; i++) val[i] = (char)('A' + (i % 26));

        char[64] key_buf;

        // Append Benchmark
        ulong t0 = core::monotonic_nanos();
        for (int i = 0; i < NUM_RECORDS; i++) {
            usz k_len = http::int_to_ascii((long)i, &key_buf[0]);
            String k = (String)key_buf[0 : k_len];
            bc.put(k, val, VAL_SIZE);
        }
        ulong t1 = core::monotonic_nanos();

        ulong elapsed_ns = t1 - t0;
        double secs = (double)elapsed_ns / 1000000000.0;
        double mb = (double)(NUM_RECORDS * VAL_SIZE) / (1024.0 * 1024.0);
        double mb_sec = mb / secs;
        double iops = (double)NUM_RECORDS / secs;

        io::printfn("[BENCH] Bitcask Append WAL (1,000 x 4 KB):  %8.2f ms  |  %6.2f MB/s (%0.0f IOPS)", secs * 1000.0, mb_sec, iops);

        // Read Benchmark
        core::Buffer read_buf = core::buffer_init(VAL_SIZE);
        ulong rt0 = core::monotonic_nanos();
        for (int i = 0; i < NUM_RECORDS; i++) {
            usz k_len = http::int_to_ascii((long)i, &key_buf[0]);
            String k = (String)key_buf[0 : k_len];
            bc.get(k, &read_buf);
        }
        ulong rt1 = core::monotonic_nanos();

        ulong relapsed_ns = rt1 - rt0;
        double rsecs = (double)relapsed_ns / 1000000000.0;
        double read_iops = (double)NUM_RECORDS / rsecs;
        double latency_us = (relapsed_ns / 1000.0) / (double)NUM_RECORDS;

        io::printfn("[BENCH] Bitcask KeyDir Point Read:          %8.2f ms  |  %6.1f us latency (%0.0f IOPS)", rsecs * 1000.0, latency_us, read_iops);

        read_buf.free();
        mem::free(val);
        bc.close();
    }

    io::printn("");
    io::printn("================================================================================");
    io::printn("                 MICROBENCHMARK SUITE COMPLETED SUCCESSFULLY                    ");
    io::printn("================================================================================");
    io::printn("");

    return 0;
}
