// Module: caisson::core
// Fixed-size chunk memory pool for streaming payloads and erasure stripes.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

import std::core::mem;

// Reusable block pool eliminating runtime allocations during high-throughput I/O.
struct BlockPool {
    char* storage;
    usz block_size;
    usz total_blocks;
    usz* free_indices;
    usz free_count;
    usz peak_active;
}

fn BlockPool pool_init(usz block_size, usz block_count) {
    usz bsz = block_size > 0 ? block_size : 65536;
    usz count = block_count > 0 ? block_count : 64;

    char* memory = (char*)mem::malloc((sz)(bsz * count));
    usz* indices = (usz*)mem::malloc((sz)(count * usz::size));

    for (usz i = 0; i < count; i++) {
        indices[i] = i;
    }

    return (BlockPool){
        .storage = memory,
        .block_size = bsz,
        .total_blocks = count,
        .free_indices = indices,
        .free_count = count,
        .peak_active = 0
    };
}

fn void BlockPool.free(&this) {
    if (this.storage != null) {
        mem::free(this.storage);
        this.storage = null;
    }
    if (this.free_indices != null) {
        mem::free(this.free_indices);
        this.free_indices = null;
    }
    this.total_blocks = 0;
    this.free_count = 0;
}

fn char* BlockPool.acquire(&this) {
    if (this.free_count == 0) {
        return null; // All pool blocks currently in use
    }

    this.free_count--;
    usz block_idx = this.free_indices[this.free_count];
    usz active = this.total_blocks - this.free_count;
    if (active > this.peak_active) {
        this.peak_active = active;
    }

    return this.storage + (block_idx * this.block_size);
}

fn bool BlockPool.release(&this, char* ptr) {
    if (ptr == null || this.storage == null) return false;

    usz offset = (usz)(ptr - this.storage);
    if (offset >= this.total_blocks * this.block_size) return false;
    if (offset % this.block_size != 0) return false;

    usz block_idx = offset / this.block_size;
    if (this.free_count >= this.total_blocks) return false;

    this.free_indices[this.free_count] = block_idx;
    this.free_count++;
    return true;
}

fn usz BlockPool.active_count(this) {
    return this.total_blocks - this.free_count;
}
