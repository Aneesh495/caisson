// Module: test_pool
// Unit tests for fixed-size chunk block memory pool.
//
// Part of the Caisson distributed object storage engine.

module test_pool;

import caisson::core;

fn void test_pool_acquire_and_release() @test {
    core::BlockPool pool = core::pool_init(1024, 4);
    defer pool.free();

    assert(pool.free_count == 4);
    assert(pool.active_count() == 0);

    char* b0 = pool.acquire();
    char* b1 = pool.acquire();
    assert(b0 != null);
    assert(b1 != null);
    assert(b0 != b1);
    assert(pool.active_count() == 2);

    bool rel0 = pool.release(b0);
    assert(rel0 == true);
    assert(pool.active_count() == 1);

    bool rel1 = pool.release(b1);
    assert(rel1 == true);
    assert(pool.active_count() == 0);
    assert(pool.free_count == 4);
}
