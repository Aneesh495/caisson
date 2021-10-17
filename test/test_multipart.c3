// Module: test_multipart
// Unit tests for S3 streaming multipart upload lifecycle and composite ETags.
//
// Part of the Caisson distributed object storage engine.

module test_multipart;

import caisson::core;
import caisson::multipart;

fn void test_multipart_lifecycle_and_composite_etag() @test {
    multipart::MultipartManager mgr = multipart::multipart_manager_init(16);
    defer mgr.free();

    char[40] upload_id_buf;
    core::Result init_res = mgr.initiate_upload("mybucket", "large_archive.tar.gz", &upload_id_buf[0]);
    assert(init_res.is_ok());

    String uid = (String)upload_id_buf[0:36];

    // Upload Part 1 (5 MB simulated)
    String part1_data = "Part 1 chunk binary payload simulating 5MB block";
    char[33] etag1_buf;
    core::Result p1_res = mgr.upload_part(uid, 1, part1_data.ptr, part1_data.len, &etag1_buf[0]);
    assert(p1_res.is_ok());
    String etag1 = (String)etag1_buf[0:32];

    // Upload Part 2
    String part2_data = "Part 2 chunk binary payload simulating another 5MB block";
    char[33] etag2_buf;
    core::Result p2_res = mgr.upload_part(uid, 2, part2_data.ptr, part2_data.len, &etag2_buf[0]);
    assert(p2_res.is_ok());
    String etag2 = (String)etag2_buf[0:32];

    // Verify out-of-order parts fail completion
    multipart::ClientPart[2] bad_parts;
    bad_parts[0] = (multipart::ClientPart){ .part_number = 2, .etag = etag2 };
    bad_parts[1] = (multipart::ClientPart){ .part_number = 1, .etag = etag1 };

    char[64] comp_etag_buf;
    core::Result bad_res = mgr.complete_upload(uid, &bad_parts[0], 2, &comp_etag_buf[0]);
    assert(bad_res.is_err(), "Non-ascending part numbers must be rejected");

    // Complete upload with properly ordered parts
    multipart::ClientPart[2] good_parts;
    good_parts[0] = (multipart::ClientPart){ .part_number = 1, .etag = etag1 };
    good_parts[1] = (multipart::ClientPart){ .part_number = 2, .etag = etag2 };

    core::Result good_res = mgr.complete_upload(uid, &good_parts[0], 2, &comp_etag_buf[0]);
    assert(good_res.is_ok());

    // Verify composite ETag format: "<md5>-2"
    assert(comp_etag_buf[32] == '-');
    assert(comp_etag_buf[33] == '2');
}

fn void test_multipart_abort() @test {
    multipart::MultipartManager mgr = multipart::multipart_manager_init(16);
    defer mgr.free();

    char[40] upload_id_buf;
    mgr.initiate_upload("mybucket", "abandoned.iso", &upload_id_buf[0]);
    String uid = (String)upload_id_buf[0:36];

    assert(mgr.active_count == 1);

    core::Result abort_res = mgr.abort_upload(uid);
    assert(abort_res.is_ok());
    assert(mgr.active_count == 0);
    assert(mgr.find_session(uid) == null);
}
