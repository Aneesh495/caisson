// Module: caisson::auth
// AWS Signature Version 4 (SigV4) authenticator and canonical request processor.
//
// Part of the Caisson distributed object storage engine.

module caisson::auth;

import std::core::mem;
import caisson::core;
import caisson::hash;

// Derives the AWS SigV4 signing key through four successive HMAC-SHA256 stages:
// kDate    = HMAC("AWS4" + SecretKey, DateStamp)
// kRegion  = HMAC(kDate, Region)
// kService = HMAC(kRegion, Service)
// kSigning = HMAC(kService, "aws4_request")
fn void sigv4_derive_signing_key(
    String secret_key,
    String date_stamp,
    String region,
    String service,
    char* out_signing_key
) {
    char[128] key_buf;
    key_buf[0] = 'A';
    key_buf[1] = 'W';
    key_buf[2] = 'S';
    key_buf[3] = '4';
    mem::copy(&key_buf[4], secret_key.ptr, (sz)secret_key.len);
    usz key_len = 4 + secret_key.len;

    char[32] k_date;
    hash::hmac_sha256(&key_buf[0], key_len, date_stamp.ptr, date_stamp.len, &k_date[0]);

    char[32] k_region;
    hash::hmac_sha256(&k_date[0], 32, region.ptr, region.len, &k_region[0]);

    char[32] k_service;
    hash::hmac_sha256(&k_region[0], 32, service.ptr, service.len, &k_service[0]);

    String request_str = "aws4_request";
    hash::hmac_sha256(&k_service[0], 32, request_str.ptr, request_str.len, out_signing_key);
}

// Builds the AWS SigV4 StringToSign document:
// "AWS4-HMAC-SHA256\n" + RequestDateTime + "\n" + CredentialScope + "\n" + HashedCanonicalRequest
fn void sigv4_build_string_to_sign(
    String amz_date,
    String credential_scope,
    String canonical_request_hex,
    core::Buffer* out_buf
) {
    out_buf.clear();
    out_buf.append_string("AWS4-HMAC-SHA256\n");
    out_buf.append_string(amz_date);
    out_buf.append_byte('\n');
    out_buf.append_string(credential_scope);
    out_buf.append_byte('\n');
    out_buf.append_string(canonical_request_hex);
}

// Computes the expected 64-character hex signature for a given StringToSign.
fn String sigv4_calculate_signature(
    char* signing_key,
    String string_to_sign,
    char* out_hex
) {
    char[32] mac;
    hash::hmac_sha256(signing_key, 32, string_to_sign.ptr, string_to_sign.len, &mac[0]);
    return core::hex_encode(&mac[0], 32, out_hex);
}

// Constant-time string comparison to prevent timing side-channel attacks on signatures.
fn bool constant_time_equals(String a, String b) {
    if (a.len != b.len) return false;
    int diff = 0;
    for (usz i = 0; i < a.len; i++) {
        diff |= (int)(a[i] ^ b[i]);
    }
    return diff == 0;
}

// Complete SigV4 signature verification routine.
fn core::Result sigv4_verify_signature(
    String secret_key,
    String date_stamp,
    String region,
    String service,
    String amz_date,
    String canonical_request,
    String client_signature
) {
    if (client_signature.len != 64) {
        return core::result_err(core::StorageError.AUTHENTICATION_FAILED, "Malformed signature length");
    }

    char[32] signing_key;
    sigv4_derive_signing_key(secret_key, date_stamp, region, service, &signing_key[0]);

    char[65] req_hash_hex;
    String req_hex = hash::sha256_hex(canonical_request.ptr, canonical_request.len, &req_hash_hex[0]);

    core::Buffer scope_buf = core::buffer_init(64);
    defer scope_buf.free();
    scope_buf.append_string(date_stamp);
    scope_buf.append_byte('/');
    scope_buf.append_string(region);
    scope_buf.append_byte('/');
    scope_buf.append_string(service);
    scope_buf.append_string("/aws4_request");

    core::Buffer sts_buf = core::buffer_init(256);
    defer sts_buf.free();
    sigv4_build_string_to_sign(amz_date, scope_buf.as_string(), req_hex, &sts_buf);

    char[65] computed_sig_hex;
    String computed_sig = sigv4_calculate_signature(&signing_key[0], sts_buf.as_string(), &computed_sig_hex[0]);

    if (!constant_time_equals(computed_sig, client_signature)) {
        return core::result_err(core::StorageError.AUTHENTICATION_FAILED, "Signature does not match");
    }

    return core::result_ok();
}
