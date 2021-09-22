// Module: caisson::hash
// RFC 2104 HMAC-SHA256 message authentication code implementation.
//
// Part of the Caisson distributed object storage engine.

module caisson::hash;

import std::core::mem;
import caisson::core;

// Computes HMAC-SHA256 message authentication code across data using key.
fn void hmac_sha256(
    char* key,
    usz key_len,
    char* data,
    usz data_len,
    char* out_mac
) {
    char[64] k_pad;
    for (usz i = 0; i < 64; i++) {
        k_pad[i] = 0;
    }

    if (key_len > 64) {
        sha256_hash(key, key_len, &k_pad[0]);
    } else {
        mem::copy(&k_pad[0], key, (sz)key_len);
    }

    char[64] ipad;
    char[64] opad;
    for (usz i = 0; i < 64; i++) {
        ipad[i] = (char)(k_pad[i] ^ 0x36);
        opad[i] = (char)(k_pad[i] ^ 0x5C);
    }

    // Inner hash: SHA256(ipad || data)
    Sha256Context inner_ctx;
    sha256_init(&inner_ctx);
    sha256_update(&inner_ctx, &ipad[0], 64);
    sha256_update(&inner_ctx, data, data_len);
    char[32] inner_hash;
    sha256_final(&inner_ctx, &inner_hash[0]);

    // Outer hash: SHA256(opad || inner_hash)
    Sha256Context outer_ctx;
    sha256_init(&outer_ctx);
    sha256_update(&outer_ctx, &opad[0], 64);
    sha256_update(&outer_ctx, &inner_hash[0], 32);
    sha256_final(&outer_ctx, out_mac);
}

// Computes HMAC-SHA256 with 64-character lowercase hexadecimal string output.
fn String hmac_sha256_hex(
    char* key,
    usz key_len,
    char* data,
    usz data_len,
    char* out_hex
) {
    char[32] mac;
    hmac_sha256(key, key_len, data, data_len, &mac[0]);
    return core::hex_encode(&mac[0], 32, out_hex);
}
