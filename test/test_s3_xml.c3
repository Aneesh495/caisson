// Module: test_s3_xml
// Unit tests for AWS S3 XML response serializers and request payload parsers.
//
// Part of the Caisson distributed object storage engine.

module test_s3_xml;

import std::core::mem;
import caisson::core;
import caisson::http;
import caisson::index;
import caisson::multipart;
import caisson::s3;

fn bool test_xml_contains(String hay, String needle) {
    if (needle.len > hay.len) return false;
    for (usz i = 0; i <= hay.len - needle.len; i++) {
        bool match = true;
        for (usz j = 0; j < needle.len; j++) {
            if (hay[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn void test_s3_list_buckets_xml() @test {
    index::BucketRegistry reg = index::bucket_registry_init();
    reg.create_bucket("logs", "us-east-1");
    reg.create_bucket("backups", "us-east-1");

    http::HttpResponse resp = http::response_init();
    s3::format_list_buckets_xml(&resp, &reg);

    assert(resp.status_code == 200);
    String body_str = (String)resp.body.data[0 : resp.body.len];

    assert(test_xml_contains(body_str, "<ListAllMyBucketsResult"));
    assert(test_xml_contains(body_str, "<Name>logs</Name>"));
    assert(test_xml_contains(body_str, "<Name>backups</Name>"));

    resp.free();
}

fn void test_s3_list_objects_v2_xml() @test {
    index::ListResult list_res;
    list_res.object_count = 1;
    list_res.common_prefix_count = 1;
    list_res.is_truncated = false;

    list_res.objects[0] = index::object_meta_init(
        "my-bucket",
        "data/sample.csv",
        4096,
        "098f6bcd4621d373cade4e832627b4f6",
        "text/csv"
    );

    list_res.common_prefixes[0].prefix_len = 7;
    mem::copy(&list_res.common_prefixes[0].prefix[0], "images/", 7);

    http::HttpResponse resp = http::response_init();
    s3::format_list_objects_v2_xml(&resp, "my-bucket", "data/", 1000, &list_res);

    assert(resp.status_code == 200);
    String body_str = (String)resp.body.data[0 : resp.body.len];

    assert(test_xml_contains(body_str, "<ListBucketResult"));
    assert(test_xml_contains(body_str, "<Name>my-bucket</Name>"));
    assert(test_xml_contains(body_str, "<Key>data/sample.csv</Key>"));
    assert(test_xml_contains(body_str, "<Size>4096</Size>"));
    assert(test_xml_contains(body_str, "<Prefix>images/</Prefix>"));

    resp.free();
}

fn void test_s3_complete_multipart_xml_parser() @test {
    String xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                 "<CompleteMultipartUpload>\n"
                 "  <Part>\n"
                 "    <PartNumber>1</PartNumber>\n"
                 "    <ETag>\"a5857948b3011d37c600de871f35015b\"</ETag>\n"
                 "  </Part>\n"
                 "  <Part>\n"
                 "    <PartNumber>2</PartNumber>\n"
                 "    <ETag>\"1b2cf535f27731c974343645a3985328\"</ETag>\n"
                 "  </Part>\n"
                 "</CompleteMultipartUpload>\n";

    multipart::ClientPart[8] parts;
    uint count = 0;

    core::Result res = s3::parse_complete_multipart_xml(xml.ptr, xml.len, &parts[0], 8, &count);
    assert(res.is_ok());
    assert(count == 2);

    assert(parts[0].part_number == 1);
    assert(parts[0].etag == "a5857948b3011d37c600de871f35015b");

    assert(parts[1].part_number == 2);
    assert(parts[1].etag == "1b2cf535f27731c974343645a3985328");
}
