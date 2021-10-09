// Module: test_index
// Unit tests for bucket DNS validation, object indexing, ListObjectsV2, and versioning.
//
// Part of the Caisson distributed object storage engine.

module test_index;

import caisson::core;
import caisson::index;

fn void test_bucket_dns_validation() @test {
    // Valid bucket names
    assert(index::validate_bucket_name("my-storage-bucket"));
    assert(index::validate_bucket_name("dataset.2026.logs"));
    assert(index::validate_bucket_name("abc"));

    // Invalid bucket names
    assert(!index::validate_bucket_name("ab"), "Too short (min 3 chars)");
    assert(!index::validate_bucket_name("MyBucket"), "Uppercase forbidden in S3");
    assert(!index::validate_bucket_name("-start-dash"), "Cannot start with hyphen");
    assert(!index::validate_bucket_name("end-dash-"), "Cannot end with hyphen");
    assert(!index::validate_bucket_name("double..period"), "Consecutive periods forbidden");
    assert(!index::validate_bucket_name("hyphen.-dot"), "Hyphen adjacent to dot forbidden");
}

fn void test_bucket_registry_lifecycle() @test {
    index::BucketRegistry reg = index::bucket_registry_init();

    core::Result c_res = reg.create_bucket("telemetry-logs", "us-east-1");
    assert(c_res.is_ok());

    index::Bucket* b = reg.get_bucket("telemetry-logs");
    assert(b != null);
    assert(b.name_len == 14);

    // Prevent duplicate creation
    core::Result dup_res = reg.create_bucket("telemetry-logs", "us-east-1");
    assert(dup_res.is_err());
    assert(dup_res.code == core::StorageError.ALREADY_EXISTS);

    // Delete bucket
    core::Result del_res = reg.delete_bucket("telemetry-logs");
    assert(del_res.is_ok());
    assert(reg.get_bucket("telemetry-logs") == null);
}

fn void test_list_objects_v2_prefix_and_delimiter() @test {
    index::ObjectIndex idx = index::object_index_init(64);
    defer idx.free();

    String b = "mybucket";
    idx.insert(index::object_meta_init(b, "photos/2026/vacation.jpg", 1024, "etag1", "image/jpeg"));
    idx.insert(index::object_meta_init(b, "photos/2026/beach.jpg", 2048, "etag2", "image/jpeg"));
    idx.insert(index::object_meta_init(b, "photos/2025/ski.jpg", 4096, "etag3", "image/jpeg"));
    idx.insert(index::object_meta_init(b, "documents/report.pdf", 8192, "etag4", "application/pdf"));
    idx.insert(index::object_meta_init(b, "readme.txt", 512, "etag5", "text/plain"));

    // Query 1: List with delimiter "/" and prefix "photos/"
    index::ListResult r1 = idx.list_objects_v2(b, "photos/", "/", "", 10);
    assert(r1.object_count == 0, "All items grouped into common prefixes");
    assert(r1.common_prefix_count == 2, "Should return photos/2026/ and photos/2025/");

    // Query 2: List with prefix "photos/2026/" without delimiter
    index::ListResult r2 = idx.list_objects_v2(b, "photos/2026/", "", "", 10);
    assert(r2.object_count == 2);
    assert(r2.common_prefix_count == 0);

    // Query 3: Max keys pagination limit
    index::ListResult r3 = idx.list_objects_v2(b, "", "", "", 2);
    assert(r3.object_count == 2);
    assert(r3.is_truncated == true);
    assert(r3.next_token_len > 0);
}

fn void test_versioning_mvcc_lifecycle() @test {
    index::VersionStore vs = index::version_store_init(64);
    defer vs.free();

    char[40] v1_buf;
    String v1 = vs.put_version("mybucket", "state.json", 100, "etag1", false, &v1_buf[0]);
    assert(v1.len == 36);

    index::VersionEntry* e1 = vs.get_latest("mybucket", "state.json");
    assert(e1 != null);
    assert(e1.is_latest == true);
    assert(e1.size == 100);

    // Write new version
    char[40] v2_buf;
    String v2 = vs.put_version("mybucket", "state.json", 250, "etag2", false, &v2_buf[0]);
    assert(v2.len == 36);
    assert(v1 != v2);

    index::VersionEntry* e2 = vs.get_latest("mybucket", "state.json");
    assert(e2 != null);
    assert(e2.is_latest == true);
    assert(e2.size == 250);
}
