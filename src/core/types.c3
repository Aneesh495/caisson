// Module: caisson::core
// Types, constants, domain primitives, error definitions, and utility helpers.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

import std::math;
import std::core::mem;

// Error codes for storage, networking, protocol, and cryptographic operations.
enum StorageError : int {
    OK,
    NOT_FOUND,
    ALREADY_EXISTS,
    IO_ERROR,
    CORRUPTED_DATA,
    CHECKSUM_MISMATCH,
    INVALID_ARGUMENT,
    OUT_OF_MEMORY,
    CAPACITY_EXCEEDED,
    UNRECOVERABLE_STRIPE,
    AUTHENTICATION_FAILED,
    SIGNATURE_EXPIRED,
    MALFORMED_REQUEST,
    NOT_IMPLEMENTED,
    QUORUM_FAILED,
    LOCK_CONTENTION,
    PERMISSION_DENIED,
    INTERNAL_ERROR,
    CLOSED,
    EOF_REACHED
}

// Result structure pairing a status code with an optional message.
struct Result {
    StorageError code;
    String message;
}

fn Result result_ok() {
    return (Result){ .code = StorageError.OK, .message = "Operation completed successfully" };
}

fn Result result_err(StorageError code, String msg) {
    return (Result){ .code = code, .message = msg };
}

fn bool Result.is_ok(this) {
    return this.code == StorageError.OK;
}

fn bool Result.is_err(this) {
    return this.code != StorageError.OK;
}

// Storage size constants expressed in bytes.
const ulong BYTE = 1;
const ulong KILOBYTE = 1024 * BYTE;
const ulong MEGABYTE = 1024 * KILOBYTE;
const ulong GIGABYTE = 1024 * MEGABYTE;
const ulong TERABYTE = 1024 * GIGABYTE;

// Standard stripe sizing parameters for Reed-Solomon erasure encoding.
const uint DEFAULT_SHARD_SIZE = 64 * 1024; // 64 KB per shard stripe
const uint DEFAULT_DATA_SHARDS = 4;        // K = 4 data shards
const uint DEFAULT_PARITY_SHARDS = 2;      // M = 2 parity shards
const uint MAX_SHARDS_PER_STRIPE = 32;     // Upper limit on K + M

// Bit manipulation and endian helpers for multi-byte protocol wire formats.

fn ushort read_u16_le(char* ptr) {
    return (ushort)((uint)((char)ptr[0] & 0xFF) |
                    ((uint)((char)ptr[1] & 0xFF) << 8));
}

fn void write_u16_le(char* ptr, ushort val) {
    ptr[0] = (char)(val & 0xFF);
    ptr[1] = (char)((val >> 8) & 0xFF);
}

fn ushort read_u16_be(char* ptr) {
    return (ushort)(((uint)((char)ptr[0] & 0xFF) << 8) |
                    ((uint)((char)ptr[1] & 0xFF)));
}

fn void write_u16_be(char* ptr, ushort val) {
    ptr[0] = (char)((val >> 8) & 0xFF);
    ptr[1] = (char)(val & 0xFF);
}

fn uint read_u32_le(char* ptr) {
    return ((uint)((char)ptr[0] & 0xFF)) |
           (((uint)((char)ptr[1] & 0xFF)) << 8) |
           (((uint)((char)ptr[2] & 0xFF)) << 16) |
           (((uint)((char)ptr[3] & 0xFF)) << 24);
}

fn void write_u32_le(char* ptr, uint val) {
    ptr[0] = (char)(val & 0xFF);
    ptr[1] = (char)((val >> 8) & 0xFF);
    ptr[2] = (char)((val >> 16) & 0xFF);
    ptr[3] = (char)((val >> 24) & 0xFF);
}

fn uint read_u32_be(char* ptr) {
    return (((uint)((char)ptr[0] & 0xFF)) << 24) |
           (((uint)((char)ptr[1] & 0xFF)) << 16) |
           (((uint)((char)ptr[2] & 0xFF)) << 8) |
           ((uint)((char)ptr[3] & 0xFF));
}

fn void write_u32_be(char* ptr, uint val) {
    ptr[0] = (char)((val >> 24) & 0xFF);
    ptr[1] = (char)((val >> 16) & 0xFF);
    ptr[2] = (char)((val >> 8) & 0xFF);
    ptr[3] = (char)(val & 0xFF);
}

fn ulong read_u64_le(char* ptr) {
    ulong lo = (ulong)read_u32_le(ptr);
    ulong hi = (ulong)read_u32_le(ptr + 4);
    return lo | (hi << 32);
}

fn void write_u64_le(char* ptr, ulong val) {
    write_u32_le(ptr, (uint)(val & 0xFFFFFFFF));
    write_u32_le(ptr + 4, (uint)((val >> 32) & 0xFFFFFFFF));
}

fn ulong read_u64_be(char* ptr) {
    ulong hi = (ulong)read_u32_be(ptr);
    ulong lo = (ulong)read_u32_be(ptr + 4);
    return (hi << 32) | lo;
}

fn void write_u64_be(char* ptr, ulong val) {
    write_u32_be(ptr, (uint)((val >> 32) & 0xFFFFFFFF));
    write_u32_be(ptr + 4, (uint)(val & 0xFFFFFFFF));
}

// Fast pseudo-random number generator for UUID and nonces (XorShift64Star).
struct RngState {
    ulong state;
}

fn void RngState.init(&this, ulong seed) {
    this.state = seed != 0 ? seed : 0x853c49e6748fea9b;
}

fn ulong RngState.next(&this) {
    ulong x = this.state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    this.state = x;
    return x * 0x2545F4914F6CDD1D;
}

fn uint RngState.next_u32(&this) {
    return (uint)(this.next() >> 32);
}

fn double RngState.next_double(&this) {
    return (double)(this.next() >> 11) * (1.0 / 9007199254740992.0);
}

// RFC 4122 compliant UUID Version 4 generator.
struct Uuid {
    char[16] bytes;
}

fn Uuid uuid_v4(RngState* rng) {
    Uuid u;
    ulong r1 = rng.next();
    ulong r2 = rng.next();
    write_u64_le((char*)&u.bytes[0], r1);
    write_u64_le((char*)&u.bytes[8], r2);

    // Set version to 4: bits 12-15 of time_hi_and_version to 0100
    u.bytes[6] = (char)((u.bytes[6] & 0x0F) | 0x40);
    // Set variant to RFC 4122: bits 6-7 of clock_seq_hi_and_reserved to 10
    u.bytes[8] = (char)((u.bytes[8] & 0x3F) | 0x80);

    return u;
}

// Convert UUID bytes into standard 36-char string: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
fn void uuid_to_string(Uuid u, char* out_str) {
    const char[16] HEX_CHARS = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    };

    usz out_idx = 0;
    for (usz i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) {
            out_str[out_idx++] = '-';
        }
        char b = u.bytes[i];
        out_str[out_idx++] = HEX_CHARS[(b >> 4) & 0x0F];
        out_str[out_idx++] = HEX_CHARS[b & 0x0F];
    }
    out_str[36] = '\0';
}
