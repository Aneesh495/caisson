// Module: test_crypto
// Unit tests for CRC32C, SHA-256, HMAC, MD5, and AWS SigV4 signature verification.
//
// Part of the Caisson distributed object storage engine.

module test_crypto;

import caisson::core;
import caisson::hash;
import caisson::auth;

fn void test_crc32c_standard_vector() @test {
    String test_input = "123456789";
    uint crc = hash::crc32c_calculate(test_input.ptr, test_input.len);
    // Standard Castagnoli CRC32C of "123456789" is 0xE3069283
    assert(crc == 0xE3069283, "CRC32C must match standard Castagnoli test vector");
}

fn void test_sha256_standard_vectors() @test {
    // Vector 1: empty string
    char[65] hex_out1;
    String hex1 = hash::sha256_hex("", 0, &hex_out1[0]);
    assert(hex1 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

    // Vector 2: "abc"
    char[65] hex_out2;
    String hex2 = hash::sha256_hex("abc", 3, &hex_out2[0]);
    assert(hex2 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

fn void test_hmac_sha256_standard_vector() @test {
    String key = "key";
    String data = "The quick brown fox jumps over the lazy dog";
    char[65] hex_out;
    String mac_hex = hash::hmac_sha256_hex(key.ptr, key.len, data.ptr, data.len, &hex_out[0]);
    // Standard HMAC-SHA256 vector
    assert(mac_hex == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8");
}

fn void test_md5_standard_vectors() @test {
    // Vector 1: empty string
    char[33] hex_out1;
    String hex1 = hash::md5_hex("", 0, &hex_out1[0]);
    assert(hex1 == "d41d8cd98f00b204e9800998ecf8427e");

    // Vector 2: "abc"
    char[33] hex_out2;
    String hex2 = hash::md5_hex("abc", 3, &hex_out2[0]);
    assert(hex2 == "900150983cd24fb0d6963f7d28e17f72");
}

fn void test_sigv4_signing_and_verification() @test {
    String secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    String date_stamp = "20130524";
    String amz_date = "20130524T000000Z";
    String region = "us-east-1";
    String service = "s3";

    String canonical_request =
        "GET\n"
        "/test.txt\n"
        "\n"
        "host:examplebucket.s3.amazonaws.com\n"
        "range:bytes=0-9\n"
        "x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n"
        "x-amz-date:20130524T000000Z\n"
        "\n"
        "host;range;x-amz-content-sha256;x-amz-date\n"
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    // Expected signature computed from canonical request
    char[32] signing_key;
    auth::sigv4_derive_signing_key(secret, date_stamp, region, service, &signing_key[0]);

    char[65] req_hash_hex;
    String req_hex = hash::sha256_hex(canonical_request.ptr, canonical_request.len, &req_hash_hex[0]);

    core::Buffer scope_buf = core::buffer_init(64);
    defer scope_buf.free();
    scope_buf.append_string("20130524/us-east-1/s3/aws4_request");

    core::Buffer sts_buf = core::buffer_init(256);
    defer sts_buf.free();
    auth::sigv4_build_string_to_sign(amz_date, scope_buf.as_string(), req_hex, &sts_buf);

    char[65] computed_sig_hex;
    String computed_sig = auth::sigv4_calculate_signature(&signing_key[0], sts_buf.as_string(), &computed_sig_hex[0]);
    assert(computed_sig.len == 64);

    // Verify roundtrip authentication passes
    core::Result v_res = auth::sigv4_verify_signature(
        secret, date_stamp, region, service, amz_date, canonical_request, computed_sig
    );
    assert(v_res.is_ok(), "SigV4 verification must succeed with valid credentials and request");

    // Verify tampering with signature fails
    char[64] tampered;
    for (usz i = 0; i < 64; i++) tampered[i] = computed_sig[i];
    tampered[0] = (char)(tampered[0] == 'a' ? 'b' : 'a');
    String tampered_sig = (String)tampered[0:64];

    core::Result fail_res = auth::sigv4_verify_signature(
        secret, date_stamp, region, service, amz_date, canonical_request, tampered_sig
    );
    assert(fail_res.is_err(), "Tampered signature must fail authentication");
}
