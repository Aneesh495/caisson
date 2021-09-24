// Module: caisson::hash
// RFC 1321 MD5 message-digest algorithm for Amazon S3 ETag verification.
//
// Part of the Caisson distributed object storage engine.

module caisson::hash;

import std::core::mem;
import caisson::core;

struct Md5Context {
    uint[4] state;
    ulong count;
    char[64] buffer;
}

fn uint rol32(uint val, uint shift) @inline {
    return (val << shift) | (val >> (32 - shift));
}

fn uint md5_ff(uint a, uint b, uint c, uint d, uint x, uint s, uint ac) @inline {
    a += ((b & c) | ((~b) & d)) + x + ac;
    return rol32(a, s) + b;
}

fn uint md5_gg(uint a, uint b, uint c, uint d, uint x, uint s, uint ac) @inline {
    a += ((b & d) | (c & (~d))) + x + ac;
    return rol32(a, s) + b;
}

fn uint md5_hh(uint a, uint b, uint c, uint d, uint x, uint s, uint ac) @inline {
    a += (b ^ c ^ d) + x + ac;
    return rol32(a, s) + b;
}

fn uint md5_ii(uint a, uint b, uint c, uint d, uint x, uint s, uint ac) @inline {
    a += (c ^ (b | (~d))) + x + ac;
    return rol32(a, s) + b;
}

fn void md5_transform(Md5Context* ctx, char* block) {
    uint a = ctx.state[0];
    uint b = ctx.state[1];
    uint c = ctx.state[2];
    uint d = ctx.state[3];
    uint[16] x;

    for (uint i = 0; i < 16; i++) {
        x[i] = core::read_u32_le(block + (i * 4));
    }

    // Round 1
    a = md5_ff(a, b, c, d, x[0], 7, 0xd76aa478);
    d = md5_ff(d, a, b, c, x[1], 12, 0xe8c7b756);
    c = md5_ff(c, d, a, b, x[2], 17, 0x242070db);
    b = md5_ff(b, c, d, a, x[3], 22, 0xc1bdceee);
    a = md5_ff(a, b, c, d, x[4], 7, 0xf57c0faf);
    d = md5_ff(d, a, b, c, x[5], 12, 0x4787c62a);
    c = md5_ff(c, d, a, b, x[6], 17, 0xa8304613);
    b = md5_ff(b, c, d, a, x[7], 22, 0xfd469501);
    a = md5_ff(a, b, c, d, x[8], 7, 0x698098d8);
    d = md5_ff(d, a, b, c, x[9], 12, 0x8b44f7af);
    c = md5_ff(c, d, a, b, x[10], 17, 0xffff5bb1);
    b = md5_ff(b, c, d, a, x[11], 22, 0x895cd7be);
    a = md5_ff(a, b, c, d, x[12], 7, 0x6b901122);
    d = md5_ff(d, a, b, c, x[13], 12, 0xfd987193);
    c = md5_ff(c, d, a, b, x[14], 17, 0xa679438e);
    b = md5_ff(b, c, d, a, x[15], 22, 0x49b40821);

    // Round 2
    a = md5_gg(a, b, c, d, x[1], 5, 0xf61e2562);
    d = md5_gg(d, a, b, c, x[6], 9, 0xc040b340);
    c = md5_gg(c, d, a, b, x[11], 14, 0x265e5a51);
    b = md5_gg(b, c, d, a, x[0], 20, 0xe9b6c7aa);
    a = md5_gg(a, b, c, d, x[5], 5, 0xd62f105d);
    d = md5_gg(d, a, b, c, x[10], 9, 0x02441453);
    c = md5_gg(c, d, a, b, x[15], 14, 0xd8a1e681);
    b = md5_gg(b, c, d, a, x[4], 20, 0xe7d3fbc8);
    a = md5_gg(a, b, c, d, x[9], 5, 0x21e1cde6);
    d = md5_gg(d, a, b, c, x[14], 9, 0xc33707d6);
    c = md5_gg(c, d, a, b, x[3], 14, 0xf4d50d87);
    b = md5_gg(b, c, d, a, x[8], 20, 0x455a14ed);
    a = md5_gg(a, b, c, d, x[13], 5, 0xa9e3e905);
    d = md5_gg(d, a, b, c, x[2], 9, 0xfcefa3f8);
    c = md5_gg(c, d, a, b, x[7], 14, 0x676f02d9);
    b = md5_gg(b, c, d, a, x[12], 20, 0x8d2a4c8a);

    // Round 3
    a = md5_hh(a, b, c, d, x[5], 4, 0xfffa3942);
    d = md5_hh(d, a, b, c, x[8], 11, 0x8771f681);
    c = md5_hh(c, d, a, b, x[11], 16, 0x6d9d6122);
    b = md5_hh(b, c, d, a, x[14], 23, 0xfde5380c);
    a = md5_hh(a, b, c, d, x[1], 4, 0xa4beea44);
    d = md5_hh(d, a, b, c, x[4], 11, 0x4bdecfa9);
    c = md5_hh(c, d, a, b, x[7], 16, 0xf6bb4b60);
    b = md5_hh(b, c, d, a, x[10], 23, 0xbebfbc70);
    a = md5_hh(a, b, c, d, x[13], 4, 0x289b7ec6);
    d = md5_hh(d, a, b, c, x[0], 11, 0xeaa127fa);
    c = md5_hh(c, d, a, b, x[3], 16, 0xd4ef3085);
    b = md5_hh(b, c, d, a, x[6], 23, 0x04881d05);
    a = md5_hh(a, b, c, d, x[9], 4, 0xd9d4d039);
    d = md5_hh(d, a, b, c, x[12], 11, 0xe6db99e5);
    c = md5_hh(c, d, a, b, x[15], 16, 0x1fa27cf8);
    b = md5_hh(b, c, d, a, x[2], 23, 0xc4ac5665);

    // Round 4
    a = md5_ii(a, b, c, d, x[0], 6, 0xf4292244);
    d = md5_ii(d, a, b, c, x[7], 10, 0x432aff97);
    c = md5_ii(c, d, a, b, x[14], 15, 0xab9423a7);
    b = md5_ii(b, c, d, a, x[5], 21, 0xfc93a039);
    a = md5_ii(a, b, c, d, x[12], 6, 0x655b59c3);
    d = md5_ii(d, a, b, c, x[3], 10, 0x8f0ccc92);
    c = md5_ii(c, d, a, b, x[10], 15, 0xffeff47d);
    b = md5_ii(b, c, d, a, x[1], 21, 0x85845dd1);
    a = md5_ii(a, b, c, d, x[8], 6, 0x6fa87e4f);
    d = md5_ii(d, a, b, c, x[15], 10, 0xfe2ce6e0);
    c = md5_ii(c, d, a, b, x[6], 15, 0xa3014314);
    b = md5_ii(b, c, d, a, x[13], 21, 0x4e0811a1);
    a = md5_ii(a, b, c, d, x[4], 6, 0xf7537e82);
    d = md5_ii(d, a, b, c, x[11], 10, 0xbd3af235);
    c = md5_ii(c, d, a, b, x[2], 15, 0x2ad7d2bb);
    b = md5_ii(b, c, d, a, x[9], 21, 0xeb86d391);

    ctx.state[0] += a;
    ctx.state[1] += b;
    ctx.state[2] += c;
    ctx.state[3] += d;
}

fn void md5_init(Md5Context* ctx) {
    ctx.state[0] = 0x67452301;
    ctx.state[1] = 0xefcdab89;
    ctx.state[2] = 0x98badcfe;
    ctx.state[3] = 0x10325476;
    ctx.count = 0;
}

fn void md5_update(Md5Context* ctx, char* data, usz len) {
    usz buffer_idx = (usz)(ctx.count & 0x3F);
    ctx.count += len;

    usz data_idx = 0;
    if (buffer_idx > 0 && buffer_idx + len >= 64) {
        usz fill = 64 - buffer_idx;
        mem::copy(&ctx.buffer[buffer_idx], data, (sz)fill);
        md5_transform(ctx, &ctx.buffer[0]);
        data_idx += fill;
        buffer_idx = 0;
    }

    while (data_idx + 64 <= len) {
        md5_transform(ctx, data + data_idx);
        data_idx += 64;
    }

    if (data_idx < len) {
        mem::copy(&ctx.buffer[buffer_idx], data + data_idx, (sz)(len - data_idx));
    }
}

fn void md5_final(Md5Context* ctx, char* out_digest) {
    ulong total_bits = ctx.count * 8;
    usz buffer_idx = (usz)(ctx.count & 0x3F);

    ctx.buffer[buffer_idx++] = (char)0x80;

    if (buffer_idx > 56) {
        while (buffer_idx < 64) {
            ctx.buffer[buffer_idx++] = 0;
        }
        md5_transform(ctx, &ctx.buffer[0]);
        buffer_idx = 0;
    }

    while (buffer_idx < 56) {
        ctx.buffer[buffer_idx++] = 0;
    }

    core::write_u64_le(&ctx.buffer[56], total_bits);
    md5_transform(ctx, &ctx.buffer[0]);

    for (uint i = 0; i < 4; i++) {
        core::write_u32_le(out_digest + (i * 4), ctx.state[i]);
    }
}

fn void md5_hash(char* data, usz len, char* out_digest) {
    Md5Context ctx;
    md5_init(&ctx);
    md5_update(&ctx, data, len);
    md5_final(&ctx, out_digest);
}

fn String md5_hex(char* data, usz len, char* out_hex) {
    char[16] digest;
    md5_hash(data, len, &digest[0]);
    return core::hex_encode(&digest[0], 16, out_hex);
}
