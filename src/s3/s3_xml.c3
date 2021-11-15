// Module: caisson::s3
// AWS S3 standard XML response serialization and multipart payload parsing.
//
// Part of the Caisson distributed object storage engine.

module caisson::s3;

import caisson::core;
import caisson::http;
import caisson::index;
import caisson::multipart;

// Formats ListAllMyBuckets XML response.
fn void format_list_buckets_xml(http::HttpResponse* resp, index::BucketRegistry* reg) {
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "application/xml");

    core::Buffer b = core::buffer_init(1024);
    b.append_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    b.append_string("<ListAllMyBucketsResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">\n");
    b.append_string("  <Owner>\n");
    b.append_string("    <ID>caisson-root</ID>\n");
    b.append_string("    <DisplayName>caisson-root</DisplayName>\n");
    b.append_string("  </Owner>\n");
    b.append_string("  <Buckets>\n");

    if (reg != null) {
        for (uint i = 0; i < 128; i++) {
            if (reg.buckets[i].occupied) {
                b.append_string("    <Bucket>\n");
                b.append_string("      <Name>");
                String bname = (String)reg.buckets[i].name[0:reg.buckets[i].name_len];
                b.append_string(bname);
                b.append_string("</Name>\n");
                b.append_string("      <CreationDate>");
                char[32] iso_date;
                core::format_iso8601_basic(reg.buckets[i].created_at, &iso_date[0]);
                b.append_bytes(&iso_date[0], 16);
                b.append_string("</CreationDate>\n");
                b.append_string("    </Bucket>\n");
            }
        }
    }

    b.append_string("  </Buckets>\n");
    b.append_string("</ListAllMyBucketsResult>\n");

    resp.set_body_bytes(b.data, b.len);
    b.free();
}

// Formats ListObjectsV2 XML response.
fn void format_list_objects_v2_xml(
    http::HttpResponse* resp,
    String bucket_name,
    String prefix,
    uint max_keys,
    index::ListResult* list_res
) {
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "application/xml");

    core::Buffer b = core::buffer_init(2048);
    b.append_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    b.append_string("<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">\n");

    b.append_string("  <Name>");
    b.append_string(bucket_name);
    b.append_string("</Name>\n");

    b.append_string("  <Prefix>");
    b.append_string(prefix);
    b.append_string("</Prefix>\n");

    b.append_string("  <KeyCount>");
    char[16] count_buf;
    usz c_len = http::int_to_ascii((long)list_res.object_count, &count_buf[0]);
    b.append_bytes(&count_buf[0], c_len);
    b.append_string("</KeyCount>\n");

    b.append_string("  <MaxKeys>");
    char[16] mk_buf;
    usz mk_len = http::int_to_ascii((long)max_keys, &mk_buf[0]);
    b.append_bytes(&mk_buf[0], mk_len);
    b.append_string("</MaxKeys>\n");

    b.append_string("  <IsTruncated>");
    b.append_string(list_res.is_truncated ? "true" : "false");
    b.append_string("</IsTruncated>\n");

    for (uint i = 0; i < list_res.object_count; i++) {
        index::ObjectMeta* e = &list_res.objects[i];
        b.append_string("  <Contents>\n");
        b.append_string("    <Key>");
        String key_str = (String)e.key[0:e.key_len];
        b.append_string(key_str);
        b.append_string("</Key>\n");

        b.append_string("    <LastModified>");
        char[32] iso_date;
        core::format_iso8601_basic(e.last_modified, &iso_date[0]);
        b.append_bytes(&iso_date[0], 16);
        b.append_string("</LastModified>\n");

        b.append_string("    <ETag>\"");
        String etag_str = (String)e.etag[0:e.etag_len];
        b.append_string(etag_str);
        b.append_string("\"</ETag>\n");

        b.append_string("    <Size>");
        char[32] sz_buf;
        usz sz_len = http::int_to_ascii((long)e.size, &sz_buf[0]);
        b.append_bytes(&sz_buf[0], sz_len);
        b.append_string("</Size>\n");

        b.append_string("    <StorageClass>STANDARD</StorageClass>\n");
        b.append_string("  </Contents>\n");
    }

    for (uint i = 0; i < list_res.common_prefix_count; i++) {
        b.append_string("  <CommonPrefixes>\n");
        b.append_string("    <Prefix>");
        String p_str = (String)list_res.common_prefixes[i].prefix[0:list_res.common_prefixes[i].prefix_len];
        b.append_string(p_str);
        b.append_string("</Prefix>\n");
        b.append_string("  </CommonPrefixes>\n");
    }

    b.append_string("</ListBucketResult>\n");

    resp.set_body_bytes(b.data, b.len);
    b.free();
}

// Formats InitiateMultipartUpload XML response.
fn void format_initiate_multipart_xml(
    http::HttpResponse* resp,
    String bucket,
    String key,
    String upload_id
) {
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "application/xml");

    core::Buffer b = core::buffer_init(512);
    b.append_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    b.append_string("<InitiateMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">\n");
    b.append_string("  <Bucket>");
    b.append_string(bucket);
    b.append_string("</Bucket>\n");
    b.append_string("  <Key>");
    b.append_string(key);
    b.append_string("</Key>\n");
    b.append_string("  <UploadId>");
    b.append_string(upload_id);
    b.append_string("</UploadId>\n");
    b.append_string("</InitiateMultipartUploadResult>\n");

    resp.set_body_bytes(b.data, b.len);
    b.free();
}

// Formats CompleteMultipartUpload XML response.
fn void format_complete_multipart_xml(
    http::HttpResponse* resp,
    String bucket,
    String key,
    String composite_etag
) {
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "application/xml");

    core::Buffer b = core::buffer_init(512);
    b.append_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    b.append_string("<CompleteMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">\n");
    b.append_string("  <Location>/");
    b.append_string(bucket);
    b.append_string("/");
    b.append_string(key);
    b.append_string("</Location>\n");
    b.append_string("  <Bucket>");
    b.append_string(bucket);
    b.append_string("</Bucket>\n");
    b.append_string("  <Key>");
    b.append_string(key);
    b.append_string("</Key>\n");
    b.append_string("  <ETag>\"");
    b.append_string(composite_etag);
    b.append_string("\"</ETag>\n");
    b.append_string("</CompleteMultipartUploadResult>\n");

    resp.set_body_bytes(b.data, b.len);
    b.free();
}

// Parses CompleteMultipartUpload XML request payload into an array of ClientPart.
fn core::Result parse_complete_multipart_xml(
    char* xml_data,
    usz xml_len,
    multipart::ClientPart* out_parts,
    uint max_parts,
    uint* out_part_count
) {
    if (xml_data == null || xml_len == 0 || out_parts == null || out_part_count == null) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid XML parser arguments");
    }

    String xml = (String)xml_data[0 : xml_len];
    uint count = 0;
    usz cursor = 0;

    while (cursor < xml.len && count < max_parts) {
        // Find <Part>
        String part_tag = "<Part>";
        usz part_pos = xml.len;
        for (usz i = cursor; i <= xml.len - part_tag.len; i++) {
            if ((String)xml[i : part_tag.len] == part_tag) {
                part_pos = i;
                break;
            }
        }
        if (part_pos == xml.len) break;

        // Find </Part>
        String end_part_tag = "</Part>";
        usz end_part_pos = xml.len;
        for (usz i = part_pos + part_tag.len; i <= xml.len - end_part_tag.len; i++) {
            if ((String)xml[i : end_part_tag.len] == end_part_tag) {
                end_part_pos = i;
                break;
            }
        }
        if (end_part_pos == xml.len) break;

        String part_content = (String)xml[part_pos + part_tag.len : end_part_pos - (part_pos + part_tag.len)];

        // Find <PartNumber>...</PartNumber>
        String pnum_open = "<PartNumber>";
        String pnum_close = "</PartNumber>";
        usz pnum_start = part_content.len;
        usz pnum_end = part_content.len;

        for (usz i = 0; i <= part_content.len - pnum_open.len; i++) {
            if ((String)part_content[i : pnum_open.len] == pnum_open) {
                pnum_start = i + pnum_open.len;
                break;
            }
        }
        for (usz i = pnum_start; i <= part_content.len - pnum_close.len; i++) {
            if ((String)part_content[i : pnum_close.len] == pnum_close) {
                pnum_end = i;
                break;
            }
        }

        // Find <ETag>...</ETag>
        String etag_open = "<ETag>";
        String etag_close = "</ETag>";
        usz etag_start = part_content.len;
        usz etag_end = part_content.len;

        for (usz i = 0; i <= part_content.len - etag_open.len; i++) {
            if ((String)part_content[i : etag_open.len] == etag_open) {
                etag_start = i + etag_open.len;
                break;
            }
        }
        for (usz i = etag_start; i <= part_content.len - etag_close.len; i++) {
            if ((String)part_content[i : etag_close.len] == etag_close) {
                etag_end = i;
                break;
            }
        }

        if (pnum_start < pnum_end && etag_start < etag_end) {
            String pnum_str = (String)part_content[pnum_start : pnum_end - pnum_start];
            uint pnum = (uint)http::parse_long(pnum_str);

            String etag_raw = (String)part_content[etag_start : etag_end - etag_start];
            // Strip outer quotes from ETag if present
            if (etag_raw.len >= 2 && etag_raw[0] == '"' && etag_raw[etag_raw.len - 1] == '"') {
                etag_raw = (String)etag_raw[1 : etag_raw.len - 2];
            }

            out_parts[count] = (multipart::ClientPart){
                .part_number = pnum,
                .etag = etag_raw
            };
            count++;
        }

        cursor = end_part_pos + end_part_tag.len;
    }

    *out_part_count = count;
    return core::result_ok();
}
