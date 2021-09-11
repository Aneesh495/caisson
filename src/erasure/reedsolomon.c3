// Module: caisson::erasure
// Systematic Reed-Solomon (K, M) erasure coding engine with Cauchy generator matrices.
//
// Part of the Caisson distributed object storage engine.

module caisson::erasure;

import std::core::mem;
import caisson::core;
import caisson::math;

// Systematic Reed-Solomon encoder and reconstructor over GF(2^8).
struct ReedSolomon {
    uint data_shards;
    uint parity_shards;
    uint total_shards;
    math::Matrix matrix;
}

fn ReedSolomon reedsolomon_init(uint data_shards, uint parity_shards) {
    uint k = data_shards > 0 ? data_shards : 4;
    uint m = parity_shards > 0 ? parity_shards : 2;
    uint total = k + m;

    math::gf_init();

    // Construct systematic generator matrix:
    // Top K x K block is Identity matrix I_K.
    // Bottom M x K block is Cauchy matrix C.
    math::Matrix gen = math::matrix_init(total, k);

    for (uint r = 0; r < k; r++) {
        gen.set(r, r, 1);
    }

    math::Matrix cauchy = math::cauchy_matrix(m, k);
    defer cauchy.free();

    for (uint r = 0; r < m; r++) {
        for (uint c = 0; c < k; c++) {
            gen.set(k + r, c, cauchy.get(r, c));
        }
    }

    return (ReedSolomon){
        .data_shards = k,
        .parity_shards = m,
        .total_shards = total,
        .matrix = gen
    };
}

fn void ReedSolomon.free(&this) {
    this.matrix.free();
    this.data_shards = 0;
    this.parity_shards = 0;
    this.total_shards = 0;
}

// Encodes K data shards into M parity shards.
// shards array must have size K + M, with shards[0..K-1] pointing to input data
// and shards[K..K+M-1] pointing to pre-allocated parity buffers of shard_size bytes.
fn core::Result ReedSolomon.encode(this, char** shards, usz shard_size) {
    if (shards == null || shard_size == 0) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid shard buffers");
    }

    uint k = this.data_shards;
    uint m = this.parity_shards;

    for (uint p = 0; p < m; p++) {
        char* parity_buf = shards[k + p];
        if (parity_buf == null) {
            return core::result_err(core::StorageError.INVALID_ARGUMENT, "Null parity buffer");
        }

        // Zero out parity buffer prior to accumulation
        for (usz i = 0; i < shard_size; i++) {
            parity_buf[i] = 0;
        }

        uint matrix_row = k + p;
        for (uint d = 0; d < k; d++) {
            char* data_buf = shards[d];
            if (data_buf == null) {
                return core::result_err(core::StorageError.INVALID_ARGUMENT, "Null data buffer");
            }
            char factor = this.matrix.get(matrix_row, d);
            math::gf_vec_mul_add(parity_buf, data_buf, factor, shard_size);
        }
    }

    return core::result_ok();
}

// Reconstructs missing data and parity shards from any surviving K shards.
// shard_present is an array of K + M booleans indicating which shards are intact.
fn core::Result ReedSolomon.reconstruct(this, char** shards, bool* shard_present, usz shard_size) {
    if (shards == null || shard_present == null || shard_size == 0) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Invalid arguments");
    }

    uint k = this.data_shards;
    uint m = this.parity_shards;
    uint total = this.total_shards;

    uint present_count = 0;
    for (uint i = 0; i < total; i++) {
        if (shard_present[i]) present_count++;
    }

    if (present_count < k) {
        return core::result_err(core::StorageError.UNRECOVERABLE_STRIPE,
                                "Insufficient surviving shards to reconstruct stripe");
    }

    // Check if all data shards are already present
    bool all_data_present = true;
    for (uint d = 0; d < k; d++) {
        if (!shard_present[d]) {
            all_data_present = false;
            break;
        }
    }

    if (all_data_present) {
        // Only parity shards are missing: re-encode directly from data shards
        return this.encode(shards, shard_size);
    }

    // One or more data shards are missing: invert surviving submatrix
    math::Matrix sub = math::matrix_init(k, k);
    defer sub.free();

    char** sub_shards = (char**)mem::malloc((sz)(k * (usz)char*::size));
    defer mem::free(sub_shards);

    uint sub_row = 0;
    for (uint i = 0; i < total && sub_row < k; i++) {
        if (shard_present[i]) {
            for (uint c = 0; c < k; c++) {
                sub.set(sub_row, c, this.matrix.get(i, c));
            }
            sub_shards[sub_row] = shards[i];
            sub_row++;
        }
    }

    math::Matrix inverted = sub.invert();
    defer inverted.free();

    if (inverted.rows == 0) {
        return core::result_err(core::StorageError.INTERNAL_ERROR, "Singular submatrix encountered");
    }

    // Allocate temporary buffers for missing data shards to avoid in-place corruption
    for (uint d = 0; d < k; d++) {
        if (!shard_present[d]) {
            char* recovered_buf = shards[d];
            for (usz i = 0; i < shard_size; i++) {
                recovered_buf[i] = 0;
            }

            for (uint r = 0; r < k; r++) {
                char factor = inverted.get(d, r);
                math::gf_vec_mul_add(recovered_buf, sub_shards[r], factor, shard_size);
            }
            shard_present[d] = true;
        }
    }

    // Reconstruct any missing parity shards now that all data shards are intact
    for (uint p = 0; p < m; p++) {
        uint shard_idx = k + p;
        if (!shard_present[shard_idx]) {
            char* parity_buf = shards[shard_idx];
            for (usz i = 0; i < shard_size; i++) {
                parity_buf[i] = 0;
            }

            for (uint d = 0; d < k; d++) {
                char factor = this.matrix.get(shard_idx, d);
                math::gf_vec_mul_add(parity_buf, shards[d], factor, shard_size);
            }
            shard_present[shard_idx] = true;
        }
    }

    return core::result_ok();
}
