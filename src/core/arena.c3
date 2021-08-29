// Module: caisson::core
// High-performance bump arena allocator for request-scoped zero-overhead memory.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

import std::core::mem;

// Linear bump allocator for fast temporary allocations without heap fragmentation.
struct Arena {
    char* memory;
    usz capacity;
    usz offset;
    usz peak_offset;
    uint allocation_count;
}

fn Arena arena_init(usz capacity) {
    usz cap = capacity > 1024 ? capacity : 1024;
    char* mem = (char*)mem::malloc((sz)cap);
    return (Arena){
        .memory = mem,
        .capacity = cap,
        .offset = 0,
        .peak_offset = 0,
        .allocation_count = 0
    };
}

fn void Arena.free(&this) {
    if (this.memory != null) {
        mem::free(this.memory);
        this.memory = null;
        this.capacity = 0;
        this.offset = 0;
    }
}

fn char* Arena.alloc(&this, usz size, usz alignment) {
    if (size == 0 || this.memory == null) return null;

    usz align = alignment > 0 ? alignment : 8;
    usz current_addr = (usz)(this.memory + this.offset);
    usz aligned_addr = (current_addr + (align - 1)) & ~(align - 1);
    usz padding = aligned_addr - current_addr;

    usz total_needed = size + padding;
    if (this.offset + total_needed > this.capacity) {
        return null; // Arena capacity exhausted
    }

    char* result = this.memory + this.offset + padding;
    this.offset += total_needed;
    this.allocation_count++;

    if (this.offset > this.peak_offset) {
        this.peak_offset = this.offset;
    }

    return result;
}

fn char* Arena.alloc_zeroed(&this, usz size, usz alignment) {
    char* ptr = this.alloc(size, alignment);
    if (ptr != null) {
        for (usz i = 0; i < size; i++) {
            ptr[i] = 0;
        }
    }
    return ptr;
}

fn void Arena.reset(&this) {
    this.offset = 0;
    this.allocation_count = 0;
}

// Marker for nested scoped rollbacks.
struct ArenaMarker {
    usz saved_offset;
    uint saved_count;
}

fn ArenaMarker Arena.mark(this) {
    return (ArenaMarker){
        .saved_offset = this.offset,
        .saved_count = this.allocation_count
    };
}

fn void Arena.restore(&this, ArenaMarker marker) {
    if (marker.saved_offset <= this.offset) {
        this.offset = marker.saved_offset;
        this.allocation_count = marker.saved_count;
    }
}
