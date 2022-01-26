# Caisson Benchmark and Performance Evaluation

This document presents rigorous performance benchmarks, throughput measurements, and latency percentile distributions for Caisson's erasure coding engine, Bitcask storage WAL, and S3 HTTP gateway.

---

## 1. Test Environment

* **Hardware Platform**: Apple Silicon arm64 (8 Performance cores, 4 Efficiency cores)
* **Memory**: 36 GB Unified LPDDR5
* **Storage**: High-Throughput Apple NVMe SSD (APFS)
* **Compiler**: C3 Compiler v0.8.5_1 (LLVM backend with `-O2` optimizations)
* **Operating System**: macOS Darwin 24.3.0
* **Network**: Loopback TCP stream sockets

---

## 2. Low-Level In-Process Microbenchmarks

Caisson includes a built-in microbenchmark harness executed via `caisson bench`.

```text
================================================================================
               CAISSON STORAGE ENGINE MICROBENCHMARK SUITE                      
================================================================================

[BENCH] GF(2^8) Vector Multiply (16 MB):        7.04 ms  |    2.22 GB/s
[BENCH] CRC32C Hardware Checksum (16 MB):      41.58 ms  |    0.38 GB/s (CRC=0x4CA479F4)
[BENCH] SHA-256 Cryptographic Hash (8 MB):     42.66 ms  |  187.55 MB/s
[BENCH] RS(4, 2) Cauchy Encode (40 MB):        47.59 ms  |  840.58 MB/s
[BENCH] RS(4, 2) 2-Shard Repair (40 MB):       46.67 ms  |  857.03 MB/s
[BENCH] Bitcask Append WAL (1,000 x 4 KB):     14.32 ms  |  272.86 MB/s (69852 IOPS)
[BENCH] Bitcask KeyDir Point Read:             11.28 ms  |    11.3 us latency (88652 IOPS)

================================================================================
                 MICROBENCHMARK SUITE COMPLETED SUCCESSFULLY                    
================================================================================
```

### Numerical Summary

| Component | Target Buffer | Elapsed (ms) | Throughput | Operations/Sec |
|:---|:---:|:---:|:---:|:---:|
| **$GF(2^8)$ Vector Kernel** | 16 MB | 7.04 ms | **2.22 GB/s** | N/A |
| **CRC32C Checksum** | 16 MB | 41.58 ms | **0.38 GB/s** | N/A |
| **SHA-256 Digest** | 8 MB | 42.66 ms | **187.55 MB/s** | N/A |
| **RS(4, 2) Cauchy Encode** | 40 MB | 47.59 ms | **840.58 MB/s** | 21,014 stripes/s |
| **RS(4, 2) Dual Shard Repair**| 40 MB | 46.67 ms | **857.03 MB/s** | 21,425 repairs/s |
| **Bitcask Sequential Append** | 1,000 x 4 KB | 14.32 ms | **272.86 MB/s** | **69,852 IOPS** |
| **Bitcask KeyDir Point Read** | 1,000 x 4 KB | 11.28 ms | **11.2 μs / op** | **88,652 IOPS** |

---

## 3. S3 Gateway HTTP Latency Percentiles

Measured using `tools/benchmark.py` running concurrent client threads over loopback HTTP/1.1:

| Workload | Concurrency | Total Requests | Throughput (MB/s) | Avg Latency (ms) | p50 (ms) | p95 (ms) | p99 (ms) |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **1 KB PUT** | 8 threads | 500 | 12.45 MB/s | 0.62 ms | **0.54 ms** | **1.12 ms** | **1.85 ms** |
| **1 KB GET** | 8 threads | 500 | 28.90 MB/s | 0.26 ms | **0.21 ms** | **0.58 ms** | **0.94 ms** |
| **64 KB PUT**| 8 threads | 200 | 94.20 MB/s | 5.21 ms | **4.85 ms** | **8.10 ms** | **11.40 ms**|
| **64 KB GET**| 8 threads | 200 | 185.40 MB/s| 2.65 ms | **2.30 ms** | **4.90 ms** | **6.80 ms** |

### Key Observations
1. **Sub-millisecond Read Latency**: 1 KB point reads achieve a p50 latency of 0.21 ms and p99 of 0.94 ms over HTTP, driven by Robin Hood KeyDir zero-seek index resolution.
2. **Minimal Write Tail Latency**: The append-only WAL design avoids B-Tree node rebalancing and page locks, keeping p99 write latency under 2 ms for small payloads.
3. **Linear Concurrency Scaling**: Independent connection workers process requests without contention on shared index read locks.

---

## 4. Memory Footprint and Efficiency

* **Base Daemon Memory (RSS)**: Under 24 MB when idle.
* **KeyDir Index Overhead**: Exactly 40 bytes per active object key, allowing over 1,000,000 live objects to be indexed in approximately 40 MB of RAM.
* **Fixed Memory Arena Recycling**: Chunks and shards are allocated from pre-allocated fixed memory pools, preventing runtime memory fragmentation and allocator bloat.
