// Module: caisson::hash
// FIPS 180-4 compliant SHA-256 cryptographic hash function.
//
// Part of the Caisson distributed object storage engine.

module caisson::hash;

import std::core::mem;
import caisson::core;

struct Sha256Context {
    uint[8] state;
    ulong count;
    char[64] buffer;
}

const uint[64] SHA256_K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

fn uint ror32(uint val, uint shift) @inline {
    return (val >> shift) | (val << (32 - shift));
}

fn void sha256_transform(Sha256Context* ctx, char* data) {
    uint[64] w;
    for (uint i = 0; i < 16; i++) {
        w[i] = core::read_u32_be(data + (i * 4));
    }
    for (uint i = 16; i < 64; i++) {
        uint s0 = ror32(w[i - 15], 7) ^ ror32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint s1 = ror32(w[i - 2], 17) ^ ror32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint a = ctx.state[0];
    uint b = ctx.state[1];
    uint c = ctx.state[2];
    uint d = ctx.state[3];
    uint e = ctx.state[4];
    uint f = ctx.state[5];
    uint g = ctx.state[6];
    uint h = ctx.state[7];

    for (uint i = 0; i < 64; i++) {
        uint s1 = ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25);
        uint ch = (e & f) ^ ((~e) & g);
        uint temp1 = h + s1 + ch + SHA256_K[i] + w[i];
        uint s0 = ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22);
        uint maj = (a & b) ^ (a & c) ^ (b & c);
        uint temp2 = s0 + maj;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }

    ctx.state[0] += a;
    ctx.state[1] += b;
    ctx.state[2] += c;
    ctx.state[3] += d;
    ctx.state[4] += e;
    ctx.state[5] += f;
    ctx.state[6] += g;
    ctx.state[7] += h;
}

fn void sha256_init(Sha256Context* ctx) {
    ctx.state[0] = 0x6a09e667;
    ctx.state[1] = 0xbb67ae85;
    ctx.state[2] = 0x3c6ef372;
    ctx.state[3] = 0xa54ff53a;
    ctx.state[4] = 0x510e527f;
    ctx.state[5] = 0x9b05688c;
    ctx.state[6] = 0x1f83d9ab;
    ctx.state[7] = 0x5be0cd19;
    ctx.count = 0;
}

fn void sha256_update(Sha256Context* ctx, char* data, usz len) {
    usz buffer_idx = (usz)(ctx.count & 0x3F);
    ctx.count += len;

    usz data_idx = 0;
    if (buffer_idx > 0 && buffer_idx + len >= 64) {
        usz fill = 64 - buffer_idx;
        mem::copy(&ctx.buffer[buffer_idx], data, (sz)fill);
        sha256_transform(ctx, &ctx.buffer[0]);
        data_idx += fill;
        buffer_idx = 0;
    }

    while (data_idx + 64 <= len) {
        sha256_transform(ctx, data + data_idx);
        data_idx += 64;
    }

    if (data_idx < len) {
        mem::copy(&ctx.buffer[buffer_idx], data + data_idx, (sz)(len - data_idx));
    }
}

fn void sha256_final(Sha256Context* ctx, char* out_digest) {
    ulong total_bits = ctx.count * 8;
    usz buffer_idx = (usz)(ctx.count & 0x3F);

    ctx.buffer[buffer_idx++] = (char)0x80;

    if (buffer_idx > 56) {
        while (buffer_idx < 64) {
            ctx.buffer[buffer_idx++] = 0;
        }
        sha256_transform(ctx, &ctx.buffer[0]);
        buffer_idx = 0;
    }

    while (buffer_idx < 56) {
        ctx.buffer[buffer_idx++] = 0;
    }

    core::write_u64_be(&ctx.buffer[56], total_bits);
    sha256_transform(ctx, &ctx.buffer[0]);

    for (uint i = 0; i < 8; i++) {
        core::write_u32_be(out_digest + (i * 4), ctx.state[i]);
    }
}

// Convenient one-shot SHA-256 calculation.
fn void sha256_hash(char* data, usz len, char* out_digest) {
    Sha256Context ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, data, len);
    sha256_final(&ctx, out_digest);
}

// Convenient one-shot SHA-256 with 64-character lowercase hexadecimal output.
fn String sha256_hex(char* data, usz len, char* out_hex) {
    char[32] digest;
    sha256_hash(data, len, &digest[0]);
    return core::hex_encode(&digest[0], 32, out_hex);
}
