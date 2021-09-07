// Module: caisson::math
// Linear algebra, Gaussian elimination, Cauchy and Vandermonde generator matrices over GF(2^8).
//
// Part of the Caisson distributed object storage engine.

module caisson::math;

import std::core::mem;

// Matrix structure over Galois Field GF(2^8).
struct Matrix {
    char* data;
    uint rows;
    uint cols;
}

fn Matrix matrix_init(uint rows, uint cols) {
    uint r = rows > 0 ? rows : 1;
    uint c = cols > 0 ? cols : 1;
    usz total = (usz)r * (usz)c;
    char* ptr = (char*)mem::malloc((sz)total);
    for (usz i = 0; i < total; i++) {
        ptr[i] = 0;
    }
    return (Matrix){ .data = ptr, .rows = r, .cols = c };
}

fn Matrix matrix_identity(uint size) {
    Matrix m = matrix_init(size, size);
    for (uint i = 0; i < size; i++) {
        m.set(i, i, 1);
    }
    return m;
}

fn void Matrix.free(&this) {
    if (this.data != null) {
        mem::free(this.data);
        this.data = null;
        this.rows = 0;
        this.cols = 0;
    }
}

fn char Matrix.get(this, uint r, uint c) {
    if (r >= this.rows || c >= this.cols || this.data == null) return 0;
    return this.data[r * this.cols + c];
}

fn void Matrix.set(&this, uint r, uint c, char val) {
    if (r >= this.rows || c >= this.cols || this.data == null) return;
    this.data[r * this.cols + c] = val;
}

fn void Matrix.swap_rows(&this, uint r1, uint r2) {
    if (r1 == r2 || r1 >= this.rows || r2 >= this.rows) return;
    for (uint c = 0; c < this.cols; c++) {
        char tmp = this.get(r1, c);
        this.set(r1, c, this.get(r2, c));
        this.set(r2, c, tmp);
    }
}

// Matrix multiplication in GF(2^8): C = A * B.
fn Matrix Matrix.multiply(this, Matrix other) {
    if (this.cols != other.rows) {
        return matrix_init(1, 1);
    }

    Matrix res = matrix_init(this.rows, other.cols);
    for (uint r = 0; r < this.rows; r++) {
        for (uint c = 0; c < other.cols; c++) {
            char sum = 0;
            for (uint k = 0; k < this.cols; k++) {
                char a_elem = this.get(r, k);
                char b_elem = other.get(k, c);
                sum ^= gf_mul(a_elem, b_elem);
            }
            res.set(r, c, sum);
        }
    }
    return res;
}

// Inverts a square matrix in GF(2^8) via Gauss-Jordan elimination with partial pivoting.
// Returns inverted matrix, or empty matrix if singular/uninvertible.
fn Matrix Matrix.invert(this) {
    if (this.rows != this.cols) {
        return matrix_init(0, 0);
    }

    uint n = this.rows;
    // Create augmented matrix [A | I] of dimensions n x (2n)
    Matrix aug = matrix_init(n, 2 * n);
    defer aug.free();

    for (uint r = 0; r < n; r++) {
        for (uint c = 0; c < n; c++) {
            aug.set(r, c, this.get(r, c));
        }
        aug.set(r, n + r, 1); // Identity block on right side
    }

    // Forward and backward elimination
    for (uint c = 0; c < n; c++) {
        // Pivot selection: find non-zero entry in current column
        uint pivot_row = c;
        while (pivot_row < n && aug.get(pivot_row, c) == 0) {
            pivot_row++;
        }

        if (pivot_row == n) {
            // Matrix is singular, cannot be inverted
            return matrix_init(0, 0);
        }

        if (pivot_row != c) {
            aug.swap_rows(c, pivot_row);
        }

        // Scale pivot row to make diagonal entry 1
        char pivot_val = aug.get(c, c);
        char pivot_inv = gf_inv(pivot_val);
        for (uint j = 0; j < 2 * n; j++) {
            aug.set(c, j, gf_mul(aug.get(c, j), pivot_inv));
        }

        // Eliminate column entries in all other rows
        for (uint r = 0; r < n; r++) {
            if (r == c) continue;
            char factor = aug.get(r, c);
            if (factor != 0) {
                for (uint j = 0; j < 2 * n; j++) {
                    char val = aug.get(r, j) ^ gf_mul(factor, aug.get(c, j));
                    aug.set(r, j, val);
                }
            }
        }
    }

    // Extract inverted right-hand matrix [I | A^-1]
    Matrix inv = matrix_init(n, n);
    for (uint r = 0; r < n; r++) {
        for (uint c = 0; c < n; c++) {
            inv.set(r, c, aug.get(r, n + c));
        }
    }

    return inv;
}

// Constructs a Cauchy distribution generator matrix:
// A[i, j] = 1 / (X[i] ^ Y[j])
// With disjoint subsets X and Y: X[i] = i, Y[j] = rows + j.
// Every square submatrix of a Cauchy matrix is guaranteed to be non-singular.
fn Matrix cauchy_matrix(uint rows, uint cols) {
    Matrix m = matrix_init(rows, cols);
    for (uint i = 0; i < rows; i++) {
        for (uint j = 0; j < cols; j++) {
            char x = (char)i;
            char y = (char)(rows + j);
            char diff = (char)(x ^ y);
            m.set(i, j, gf_inv(diff));
        }
    }
    return m;
}

// Constructs a systematic Vandermonde generator matrix.
fn Matrix vandermonde_matrix(uint rows, uint cols) {
    Matrix m = matrix_init(rows, cols);
    for (uint r = 0; r < rows; r++) {
        for (uint c = 0; c < cols; c++) {
            m.set(r, c, gf_pow((char)r, (int)c));
        }
    }
    return m;
}
