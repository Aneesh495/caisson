// Module: test_matrix
// Unit tests for GF(2^8) linear algebra, Gaussian elimination, and Cauchy matrices.
//
// Part of the Caisson distributed object storage engine.

module test_matrix;

import caisson::math;

fn void test_matrix_multiplication_and_identity() @test {
    math::gf_init();

    math::Matrix id = math::matrix_identity(3);
    defer id.free();

    math::Matrix a = math::matrix_init(3, 3);
    defer a.free();
    a.set(0, 0, 1); a.set(0, 1, 2); a.set(0, 2, 3);
    a.set(1, 0, 4); a.set(1, 1, 5); a.set(1, 2, 6);
    a.set(2, 0, 7); a.set(2, 1, 8); a.set(2, 2, 9);

    math::Matrix prod = a.multiply(id);
    defer prod.free();

    for (uint r = 0; r < 3; r++) {
        for (uint c = 0; c < 3; c++) {
            assert(prod.get(r, c) == a.get(r, c));
        }
    }
}

fn void test_matrix_inversion_gauss_jordan() @test {
    math::gf_init();

    math::Matrix a = math::matrix_init(3, 3);
    defer a.free();
    a.set(0, 0, 0x12); a.set(0, 1, 0x34); a.set(0, 2, 0x56);
    a.set(1, 0, 0x78); a.set(1, 1, 0x9A); a.set(1, 2, 0xBC);
    a.set(2, 0, 0xDE); a.set(2, 1, 0xF0); a.set(2, 2, 0x23);

    math::Matrix inv = a.invert();
    defer inv.free();

    assert(inv.rows == 3);
    assert(inv.cols == 3);

    // Verify A * A^-1 == Identity
    math::Matrix check = a.multiply(inv);
    defer check.free();

    for (uint r = 0; r < 3; r++) {
        for (uint c = 0; c < 3; c++) {
            char expected = (r == c) ? 1 : 0;
            assert(check.get(r, c) == expected);
        }
    }
}

fn void test_cauchy_matrix_invertibility() @test {
    math::gf_init();

    // Generate a 4x4 Cauchy matrix
    math::Matrix cauchy = math::cauchy_matrix(4, 4);
    defer cauchy.free();

    math::Matrix inv = cauchy.invert();
    defer inv.free();

    assert(inv.rows == 4);
    assert(inv.cols == 4);

    math::Matrix prod = cauchy.multiply(inv);
    defer prod.free();

    for (uint r = 0; r < 4; r++) {
        for (uint c = 0; c < 4; c++) {
            char expected = (r == c) ? 1 : 0;
            assert(prod.get(r, c) == expected);
        }
    }
}
