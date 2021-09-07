// Module: test_gf256
// Unit tests for Galois Field GF(2^8) field axioms and vector kernels.
//
// Part of the Caisson distributed object storage engine.

module test_gf256;

import caisson::math;

fn void test_gf_axioms_and_inverses() @test {
    math::gf_init();

    // Verify addition is XOR and self-inverse
    assert(math::gf_add(0x53, 0xCA) == (0x53 ^ 0xCA));
    assert(math::gf_add(0x7F, 0x7F) == 0);
    assert(math::gf_sub(0x7F, 0x7F) == 0);

    // Verify multiplication identity
    assert(math::gf_mul(0xAB, 1) == 0xAB);
    assert(math::gf_mul(0xAB, 0) == 0);

    // Verify multiplicative inverse for all 255 non-zero field elements
    for (int i = 1; i < 256; i++) {
        char elem = (char)i;
        char inv = math::gf_inv(elem);
        assert(inv != 0);
        char prod = math::gf_mul(elem, inv);
        assert(prod == 1, "Element multiplied by inverse must equal 1");
    }

    // Verify division
    assert(math::gf_div(0x42, 0x42) == 1);
    assert(math::gf_div(0, 0x55) == 0);
}

fn void test_gf_vector_operations() @test {
    math::gf_init();

    char[8] src = { 1, 2, 3, 4, 5, 6, 7, 8 };
    char[8] dst = { 0, 0, 0, 0, 0, 0, 0, 0 };

    // Scale by 1
    math::gf_vec_mul(&dst[0], &src[0], 1, 8);
    for (usz i = 0; i < 8; i++) {
        assert(dst[i] == src[i]);
    }

    // Multiply-accumulate with self-inverse
    char[8] acc = { 0, 0, 0, 0, 0, 0, 0, 0 };
    math::gf_vec_mul_add(&acc[0], &src[0], 0x3F, 8);
    math::gf_vec_mul_add(&acc[0], &src[0], 0x3F, 8);
    // XORing twice with same vector should return zero
    for (usz i = 0; i < 8; i++) {
        assert(acc[i] == 0);
    }
}
