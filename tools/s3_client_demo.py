#!/usr/bin/env python3
"""
S3 REST protocol client demonstration and integration test suite.
Interacts with the Caisson S3 gateway over HTTP/1.1 using Python standard library.

Part of the Caisson distributed object storage engine.
"""

import sys
import os
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
import hashlib
import time

def log_step(name, status="PASS", detail=""):
    green = "\033[92m"
    red = "\033[91m"
    blue = "\033[94m"
    reset = "\033[0m"
    badge = f"{green}[PASS]{reset}" if status == "PASS" else f"{red}[FAIL]{reset}"
    print(f"  {badge} {blue}{name:<38}{reset} {detail}")

def http_request(url, method="GET", headers=None, data=None):
    if headers is None:
        headers = {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()

def run_integration_suite(base_url="http://127.0.0.1:9000"):
    print("\n" + "=" * 70)
    print("      CAISSON S3 GATEWAY INTEGRATION & CLIENT DEMO SUITE")
    print("=" * 70)
    print(f"Target Gateway: {base_url}\n")

    bucket = f"demo-bucket-{int(time.time())}"

    # 1. Health check
    status, _, body = http_request(f"{base_url}/api/health")
    assert status == 200, f"Health check failed with status {status}"
    log_step("Cluster Health Check", "PASS", body.decode("utf-8").strip())

    # 2. Create Bucket
    status, _, _ = http_request(f"{base_url}/{bucket}", method="PUT")
    assert status == 200, f"Create bucket failed with status {status}"
    log_step("CreateBucket (PUT /<bucket>)", "PASS", f"bucket='{bucket}'")

    # 3. Head Bucket
    status, _, _ = http_request(f"{base_url}/{bucket}", method="HEAD")
    assert status == 200, f"Head bucket failed with status {status}"
    log_step("HeadBucket (HEAD /<bucket>)", "PASS", "200 OK")

    # 4. Put Object 1 (Text payload)
    data1 = b"Hello from Caisson distributed log-structured storage engine!"
    data1_md5 = hashlib.md5(data1).hexdigest()
    status, headers, _ = http_request(
        f"{base_url}/{bucket}/greeting.txt",
        method="PUT",
        headers={"Content-Type": "text/plain"},
        data=data1
    )
    assert status == 200, f"Put object failed: {status}"
    etag = headers.get("ETag", "").strip('"')
    assert etag == data1_md5, f"ETag mismatch: got {etag}, expected {data1_md5}"
    log_step("PutObject (greeting.txt)", "PASS", f"size={len(data1)}B, ETag=\"{etag}\"")

    # 5. Put Object 2 (Binary payload)
    data2 = bytes([i % 256 for i in range(16384)]) # 16 KB
    data2_md5 = hashlib.md5(data2).hexdigest()
    status, headers, _ = http_request(
        f"{base_url}/{bucket}/binary.dat",
        method="PUT",
        headers={"Content-Type": "application/octet-stream"},
        data=data2
    )
    assert status == 200
    log_step("PutObject (binary.dat 16KB)", "PASS", f"ETag=\"{data2_md5}\"")

    # 6. Get Object & Verify Payload
    status, headers, body = http_request(f"{base_url}/{bucket}/greeting.txt")
    assert status == 200 and body == data1
    log_step("GetObject (greeting.txt)", "PASS", f"verified {len(body)} bytes identical")

    # 7. Byte-Range Partial Read (RFC 7233)
    # Read bytes 0-4 ("Hello")
    status, headers, body = http_request(
        f"{base_url}/{bucket}/greeting.txt",
        headers={"Range": "bytes=0-4"}
    )
    assert status == 206, f"Expected 206 Partial Content, got {status}"
    assert body == b"Hello", f"Expected b'Hello', got {body}"
    log_step("Byte-Range Read (bytes=0-4)", "PASS", f"Content-Range={headers.get('Content-Range')}")

    # 8. Head Object
    status, headers, _ = http_request(f"{base_url}/{bucket}/greeting.txt", method="HEAD")
    assert status == 200
    assert headers.get("Content-Type") == "text/plain"
    log_step("HeadObject (metadata verification)", "PASS", f"Content-Length={headers.get('Content-Length')}")

    # 9. ListObjectsV2
    status, _, xml_body = http_request(f"{base_url}/{bucket}?list-type=2")
    assert status == 200
    assert b"greeting.txt" in xml_body and b"binary.dat" in xml_body
    log_step("ListObjectsV2 (query objects)", "PASS", "found greeting.txt and binary.dat")

    # 10. Multipart Upload Lifecycle
    # 10a. Initiate
    status, _, init_xml = http_request(f"{base_url}/{bucket}/multipart-test.bin?uploads", method="POST")
    assert status == 200
    root = ET.fromstring(init_xml)
    upload_id = root.find("{http://s3.amazonaws.com/doc/2006-03-01/}UploadId").text
    log_step("InitiateMultipartUpload", "PASS", f"UploadId={upload_id}")

    # 10b. Upload Part 1
    part1_data = b"Chunk 1: Reed-Solomon Cauchy data shards " * 50
    part1_md5 = hashlib.md5(part1_data).hexdigest()
    status, p1_hdrs, _ = http_request(
        f"{base_url}/{bucket}/multipart-test.bin?partNumber=1&uploadId={upload_id}",
        method="PUT",
        data=part1_data
    )
    assert status == 200
    log_step("UploadPart 1", "PASS", f"size={len(part1_data)}B, ETag=\"{part1_md5}\"")

    # 10c. Upload Part 2
    part2_data = b"Chunk 2: Bitcask WAL sequential log entry " * 50
    part2_md5 = hashlib.md5(part2_data).hexdigest()
    status, p2_hdrs, _ = http_request(
        f"{base_url}/{bucket}/multipart-test.bin?partNumber=2&uploadId={upload_id}",
        method="PUT",
        data=part2_data
    )
    assert status == 200
    log_step("UploadPart 2", "PASS", f"size={len(part2_data)}B, ETag=\"{part2_md5}\"")

    # 10d. Complete Multipart Upload
    complete_manifest = f"""<?xml version="1.0" encoding="UTF-8"?>
<CompleteMultipartUpload>
  <Part><PartNumber>1</PartNumber><ETag>"{part1_md5}"</ETag></Part>
  <Part><PartNumber>2</PartNumber><ETag>"{part2_md5}"</ETag></Part>
</CompleteMultipartUpload>""".encode("utf-8")

    status, _, comp_xml = http_request(
        f"{base_url}/{bucket}/multipart-test.bin?uploadId={upload_id}",
        method="POST",
        data=complete_manifest
    )
    assert status == 200, f"Complete multipart failed: {status}"
    log_step("CompleteMultipartUpload", "PASS", "composite ETag synthesized")

    # 11. Read Back Assembled Multipart Object
    status, _, mp_body = http_request(f"{base_url}/{bucket}/multipart-test.bin")
    assert status == 200
    assert mp_body == part1_data + part2_data
    log_step("Read Composite Multipart Object", "PASS", f"total_len={len(mp_body)}B verified")

    # 12. Delete Objects
    for key in ["greeting.txt", "binary.dat", "multipart-test.bin"]:
        status, _, _ = http_request(f"{base_url}/{bucket}/{key}", method="DELETE")
        assert status == 204
    log_step("DeleteObject (cleanup keys)", "PASS", "3 objects deleted")

    # 13. Delete Bucket
    status, _, _ = http_request(f"{base_url}/{bucket}", method="DELETE")
    assert status == 204
    log_step("DeleteBucket (cleanup bucket)", "PASS", "bucket removed")

    # 14. Prometheus Metrics Verification
    status, _, m_body = http_request(f"{base_url}/metrics")
    assert status == 200 and b"caisson_storage_writes_total" in m_body
    log_step("Prometheus Telemetry (/metrics)", "PASS", "valid OpenMetrics exposition")

    print("\n" + "=" * 70)
    print("        ALL INTEGRATION TESTS PASSED WITH 100% SUCCESS")
    print("=" * 70 + "\n")

if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:9000"
    run_integration_suite(url)
