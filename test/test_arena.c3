// Module: test_arena
// Unit tests for bump arena memory allocations and scoped mark/restore.
//
// Part of the Caisson distributed object storage engine.

module test_arena;

import caisson::core;

fn void test_arena_basic_allocation() @test {
    core::Arena arena = core::arena_init(1024);
    defer arena.free();

    char* p1 = arena.alloc(128, 8);
    assert(p1 != null);
    assert(arena.allocation_count == 1);
    assert(arena.offset >= 128);

    char* p2 = arena.alloc(256, 16);
    assert(p2 != null);
    assert(arena.allocation_count == 2);

    // Scoped rollback test
    core::ArenaMarker marker = arena.mark();
    char* p3 = arena.alloc(64, 8);
    assert(p3 != null);
    assert(arena.allocation_count == 3);

    arena.restore(marker);
    assert(arena.allocation_count == 2);
    assert(arena.offset == marker.saved_offset);

    arena.reset();
    assert(arena.offset == 0);
    assert(arena.allocation_count == 0);
}
