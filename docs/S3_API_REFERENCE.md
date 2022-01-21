# Caisson S3 REST API Reference

Caisson implements standard Amazon S3 REST protocol endpoints over HTTP/1.1. It can be used directly with `curl`, the official AWS CLI, Python `boto3`, Go `aws-sdk-go`, and MinIO Client (`mc`).

Default server address: `http://127.0.0.1:9000`

---

## 1. Bucket Operations

### ListAllMyBuckets
Returns a list of all buckets owned by the authenticated identity.
* **Method**: `GET`
* **Path**: `/`
* **Response**: `200 OK` (XML `ListAllMyBucketsResult`)

```bash
curl -i http://127.0.0.1:9000/
```

### CreateBucket
Creates a new storage bucket conforming to DNS naming rules.
* **Method**: `PUT`
* **Path**: `/<bucket>`
* **Response**: `200 OK`

```bash
curl -i -X PUT http://127.0.0.1:9000/analytics
```

### HeadBucket
Determines if a bucket exists and you have permission to access it.
* **Method**: `HEAD`
* **Path**: `/<bucket>`
* **Response**: `200 OK` (or `404 Not Found`)

```bash
curl -i -I http://127.0.0.1:9000/analytics
```

### DeleteBucket
Deletes an empty bucket.
* **Method**: `DELETE`
* **Path**: `/<bucket>`
* **Response**: `204 No Content` (or `409 BucketNotEmpty`)

```bash
curl -i -X DELETE http://127.0.0.1:9000/analytics
```

---

## 2. Object Operations

### PutObject
Uploads an object payload to a bucket. Computes MD5 checksum and returns standard S3 ETag.
* **Method**: `PUT`
* **Path**: `/<bucket>/<key>`
* **Headers**: `Content-Type`, `Content-Length`
* **Response**: `200 OK` (Header `ETag: "<md5>"`)

```bash
curl -i -X PUT http://127.0.0.1:9000/analytics/report.pdf \
     -H "Content-Type: application/pdf" \
     --data-binary @report.pdf
```

### GetObject
Retrieves an object from storage. Supports RFC 7233 byte ranges.
* **Method**: `GET`
* **Path**: `/<bucket>/<key>`
* **Optional Headers**: `Range: bytes=start-end`
* **Response**: `200 OK` (full object) or `206 Partial Content` (range slice)

```bash
# Full download
curl http://127.0.0.1:9000/analytics/report.pdf -o downloaded.pdf

# Byte-range read: first 1024 bytes
curl -i http://127.0.0.1:9000/analytics/report.pdf -H "Range: bytes=0-1023"
```

### HeadObject
Retrieves object metadata without transferring the payload body.
* **Method**: `HEAD`
* **Path**: `/<bucket>/<key>`
* **Response**: `200 OK` (`Content-Length`, `Content-Type`, `ETag`, `Accept-Ranges`)

```bash
curl -i -I http://127.0.0.1:9000/analytics/report.pdf
```

### DeleteObject
Deletes an object from a bucket.
* **Method**: `DELETE`
* **Path**: `/<bucket>/<key>`
* **Response**: `204 No Content`

```bash
curl -i -X DELETE http://127.0.0.1:9000/analytics/report.pdf
```

### ListObjectsV2
Returns object metadata matching an optional prefix and delimiter.
* **Method**: `GET`
* **Path**: `/<bucket>?list-type=2&prefix=<prefix>&delimiter=<delim>&max-keys=<n>`
* **Response**: `200 OK` (XML `ListBucketResult`)

```bash
curl http://127.0.0.1:9000/analytics?list-type=2&prefix=2026/&delimiter=/
```

---

## 3. Multipart Upload Lifecycle

For large objects (greater than 5 MB up to terabytes), multipart upload splits the upload into independent parts:

### Step 1: Initiate Multipart Upload
* **Method**: `POST`
* **Path**: `/<bucket>/<key>?uploads`
* **Response**: `200 OK` (XML containing `UploadId`)

```bash
curl -X POST http://127.0.0.1:9000/large/dataset.parquet?uploads
```

### Step 2: Upload Parts
* **Method**: `PUT`
* **Path**: `/<bucket>/<key>?partNumber=<n>&uploadId=<id>`
* **Response**: `200 OK` (Header `ETag: "<part_md5>"`)

```bash
curl -X PUT "http://127.0.0.1:9000/large/dataset.parquet?partNumber=1&uploadId=abc123" \
     --data-binary @part1.bin
```

### Step 3: Complete Multipart Upload
* **Method**: `POST`
* **Path**: `/<bucket>/<key>?uploadId=<id>`
* **Payload**: XML manifest listing part numbers and ETags:
  ```xml
  <CompleteMultipartUpload>
    <Part><PartNumber>1</PartNumber><ETag>"..."</ETag></Part>
    <Part><PartNumber>2</PartNumber><ETag>"..."</ETag></Part>
  </CompleteMultipartUpload>
  ```
* **Response**: `200 OK` (Composite ETag `<hash>-<part_count>`)

```bash
curl -X POST "http://127.0.0.1:9000/large/dataset.parquet?uploadId=abc123" \
     -H "Content-Type: application/xml" \
     --data-binary @manifest.xml
```

### Step 4: Abort Multipart Upload
* **Method**: `DELETE`
* **Path**: `/<bucket>/<key>?uploadId=<id>`
* **Response**: `204 No Content`

---

## 4. Administrative and Telemetry Endpoints

### Prometheus Metrics
* **Path**: `/metrics`
* **Response**: Standard OpenMetrics / Prometheus plaintext exposition:
  ```text
  caisson_storage_writes_total 1250
  caisson_storage_reads_total 8940
  caisson_scrubber_stripes_scanned_total 450
  caisson_scrubber_shards_repaired_total 2
  caisson_buckets_count 4
  caisson_objects_count 1245
  ```

### Cluster Health Check
* **Path**: `/api/health`
* **Response**: `{"status":"HEALTHY","engine":"caisson","version":"1.0.0"}`

### Live Web Console
* **Path**: `/console` or `/dashboard`
* **Response**: Self-contained dark-theme HTML5 administrative dashboard with interactive Reed-Solomon auto-healing playground.
