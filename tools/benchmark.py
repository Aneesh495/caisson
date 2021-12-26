#!/usr/bin/env python3
"""
Performance and latency percentile benchmarking harness for Caisson S3 gateway.
Measures p50, p95, p99 latencies, concurrency scaling, and throughput.

Part of the Caisson distributed object storage engine.
"""

import sys
import time
import urllib.request
import urllib.error
import threading
import statistics

class BenchmarkRunner:
    def __init__(self, base_url="http://127.0.0.1:9000"):
        self.base_url = base_url
        self.bucket = "bench-bucket"

    def setup(self):
        req = urllib.request.Request(f"{self.base_url}/{self.bucket}", method="PUT")
        try:
            with urllib.request.urlopen(req) as resp:
                pass
        except Exception:
            pass

    def run_workload(self, name, method, payload, num_requests, concurrency):
        latencies = []
        lock = threading.Lock()
        counter = [0]

        def worker():
            while True:
                with lock:
                    if counter[0] >= num_requests:
                        break
                    idx = counter[0]
                    counter[0] += 1

                url = f"{self.base_url}/{self.bucket}/obj_{idx}.bin"
                t0 = time.perf_counter()
                try:
                    req = urllib.request.Request(url, data=payload if method == "PUT" else None, method=method)
                    with urllib.request.urlopen(req) as resp:
                        resp.read()
                    elapsed = (time.perf_counter() - t0) * 1000.0 # ms
                    with lock:
                        latencies.append(elapsed)
                except Exception as e:
                    pass

        t_start = time.perf_counter()
        threads = [threading.Thread(target=worker) for _ in range(concurrency)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        total_time = time.perf_counter() - t_start

        if not latencies:
            return None

        latencies.sort()
        count = len(latencies)
        p50 = latencies[int(count * 0.50)]
        p95 = latencies[int(count * 0.95)]
        p99 = latencies[min(int(count * 0.99), count - 1)]
        avg = statistics.mean(latencies)
        rps = count / total_time
        mb_sec = (count * len(payload or b"")) / (1024.0 * 1024.0 * total_time)

        return {
            "name": name,
            "method": method,
            "size": len(payload or b""),
            "concurrency": concurrency,
            "count": count,
            "total_time": total_time,
            "rps": rps,
            "mb_sec": mb_sec,
            "avg": avg,
            "p50": p50,
            "p95": p95,
            "p99": p99
        }

def main():
    url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:9000"
    bench = BenchmarkRunner(url)
    bench.setup()

    print("\n" + "=" * 80)
    print("           CAISSON DISTRIBUTED OBJECT STORAGE BENCHMARK")
    print("=" * 80)
    print(f"Target: {url}\n")

    results = []

    # 1. 1KB Small Objects PUT
    payload_1k = b"X" * 1024
    r = bench.run_workload("1KB Objects PUT", "PUT", payload_1k, 500, 8)
    if r: results.append(r)

    # 2. 1KB Small Objects GET
    r = bench.run_workload("1KB Objects GET", "GET", payload_1k, 500, 8)
    if r: results.append(r)

    # 3. 64KB Medium Objects PUT
    payload_64k = b"M" * 65536
    r = bench.run_workload("64KB Objects PUT", "PUT", payload_64k, 200, 8)
    if r: results.append(r)

    # 4. 64KB Medium Objects GET
    r = bench.run_workload("64KB Objects GET", "GET", payload_64k, 200, 8)
    if r: results.append(r)

    print(f"{'Workload':<20} | {'Req/s':>9} | {'Throughput':>12} | {'Avg (ms)':>9} | {'p50 (ms)':>9} | {'p95 (ms)':>9} | {'p99 (ms)':>9}")
    print("-" * 92)
    for res in results:
        print(f"{res['name']:<20} | {res['rps']:>9.1f} | {res['mb_sec']:>9.2f} MB/s | {res['avg']:>9.2f} | {res['p50']:>9.2f} | {res['p95']:>9.2f} | {res['p99']:>9.2f}")
    print("=" * 92 + "\n")

if __name__ == "__main__":
    main()
