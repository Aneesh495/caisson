// Module: caisson::math
// Galois Field GF(2^8) finite field arithmetic using primitive polynomial 0x11D.
//
// Part of the Caisson distributed object storage engine.

module caisson::math;

import std::core::mem;

// Galois Field GF(2^8) lookup tables generated with primitive polynomial:
// x^8 + x^4 + x^3 + x^2 + 1 (binary: 100011101 = 0x11D).
// Generator alpha = 0x02.
struct Gf256 {
    char[512] exp_table;
    char[256] log_table;
    bool initialized;
}

Gf256 global_gf;

fn void gf_init() {
    if (global_gf.initialized) return;

    int poly = 0x11D;
    int x = 1;

    for (int i = 0; i < 255; i++) {
        global_gf.exp_table[i] = (char)x;
        global_gf.exp_table[i + 255] = (char)x;
        global_gf.log_table[x] = (char)i;
        x <<= 1;
        if ((x & 0x100) != 0) {
            x ^= poly;
        }
    }
    global_gf.log_table[0] = 0; // Undefined mathematically, set to 0 as sentinel
    global_gf.exp_table[510] = global_gf.exp_table[0];
    global_gf.exp_table[511] = global_gf.exp_table[1];
    global_gf.initialized = true;
}

// Field addition in GF(2^8) is bitwise XOR.
fn char gf_add(char a, char b) @inline {
    return (char)(a ^ b);
}

// Field subtraction in GF(2^8) is identical to addition (bitwise XOR).
fn char gf_sub(char a, char b) @inline {
    return (char)(a ^ b);
}

// Field multiplication in GF(2^8) via log/exp lookup tables.
fn char gf_mul(char a, char b) {
    if (!global_gf.initialized) gf_init();
    if (a == 0 || b == 0) return 0;

    int log_a = (int)((char)global_gf.log_table[(char)a]);
    int log_b = (int)((char)global_gf.log_table[(char)b]);
    return global_gf.exp_table[log_a + log_b];
}

// Field division in GF(2^8): a / b = exp(log(a) - log(b) mod 255).
fn char gf_div(char a, char b) {
    if (!global_gf.initialized) gf_init();
    if (b == 0) return 0; // Division by zero handled safely
    if (a == 0) return 0;

    int log_a = (int)((char)global_gf.log_table[(char)a]);
    int log_b = (int)((char)global_gf.log_table[(char)b]);
    int diff = log_a - log_b;
    if (diff < 0) diff += 255;
    return global_gf.exp_table[diff];
}

// Multiplicative inverse in GF(2^8): a^-1 such that a * a^-1 = 1.
fn char gf_inv(char a) {
    if (!global_gf.initialized) gf_init();
    if (a == 0) return 0;
    int log_a = (int)((char)global_gf.log_table[(char)a]);
    return global_gf.exp_table[255 - log_a];
}

// Exponentiation in GF(2^8): a^power.
fn char gf_pow(char a, int power) {
    if (!global_gf.initialized) gf_init();
    if (power == 0) return 1;
    if (a == 0) return 0;

    int log_a = (int)((char)global_gf.log_table[(char)a]);
    int p = (log_a * power) % 255;
    if (p < 0) p += 255;
    return global_gf.exp_table[p];
}

// Fast vector multiply-accumulate kernel: dst[i] ^= src[i] * scalar.
// Core computational inner loop for Reed-Solomon encoding and shard repair.
fn void gf_vec_mul_add(char* dst, char* src, char scalar, usz length) {
    if (scalar == 0 || length == 0) return;
    if (!global_gf.initialized) gf_init();

    if (scalar == 1) {
        // Fast path: scalar is identity element, simply XOR
        for (usz i = 0; i < length; i++) {
            dst[i] ^= src[i];
        }
        return;
    }

    int log_scalar = (int)((char)global_gf.log_table[(char)scalar]);
    char* exp_ptr = &global_gf.exp_table[0];
    char* log_ptr = &global_gf.log_table[0];

    for (usz i = 0; i < length; i++) {
        char s = src[i];
        if (s != 0) {
            int log_s = (int)((char)log_ptr[(char)s]);
            dst[i] ^= exp_ptr[log_s + log_scalar];
        }
    }
}

// Vector scaling kernel: dst[i] = src[i] * scalar.
fn void gf_vec_mul(char* dst, char* src, char scalar, usz length) {
    if (length == 0) return;
    if (!global_gf.initialized) gf_init();

    if (scalar == 0) {
        for (usz i = 0; i < length; i++) {
            dst[i] = 0;
        }
        return;
    }

    if (scalar == 1) {
        mem::copy(dst, src, (sz)length);
        return;
    }

    int log_scalar = (int)((char)global_gf.log_table[(char)scalar]);
    char* exp_ptr = &global_gf.exp_table[0];
    char* log_ptr = &global_gf.log_table[0];

    for (usz i = 0; i < length; i++) {
        char s = src[i];
        if (s == 0) {
            dst[i] = 0;
        } else {
            int log_s = (int)((char)log_ptr[(char)s]);
            dst[i] = exp_ptr[log_s + log_scalar];
        }
    }
}
