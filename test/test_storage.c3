// Module: test_storage
// Unit tests for Bitcask storage engine, Robin Hood KeyDir, and CAS deduplication.
//
// Part of the Caisson distributed object storage engine.

module test_storage;

import caisson::core;
import caisson::storage;

fn void test_keydir_robin_hood_operations() @test {
    storage::KeyDir kd = storage::keydir_init(8);
    defer kd.free();

    kd.put("alpha", 1, 100, 50, 1000);
    kd.put("beta", 1, 150, 60, 1001);
    kd.put("gamma", 2, 210, 70, 1002);

    assert(kd.count == 3);

    storage::KeyDirEntry* e_alpha = kd.get("alpha");
    assert(e_alpha != null);
    assert(e_alpha.file_id == 1);
    assert(e_alpha.val_pos == 100);

    storage::KeyDirEntry* e_beta = kd.get("beta");
    assert(e_beta != null);
    assert(e_beta.val_pos == 150);

    // Test update in place
    kd.put("alpha", 3, 500, 80, 2000);
    assert(kd.count == 3);
    storage::KeyDirEntry* e_alpha2 = kd.get("alpha");
    assert(e_alpha2.val_pos == 500);

    // Test backward-shift deletion
    bool del_beta = kd.delete("beta");
    assert(del_beta == true);
    assert(kd.count == 2);
    assert(kd.get("beta") == null);
    assert(kd.get("gamma") != null);
}

fn void test_bitcask_put_get_delete_lifecycle() @test {
    String test_dir = "/tmp/caisson_test_bitcask";
    storage::Bitcask bc = storage::bitcask_open(test_dir, 1024 * 1024);
    defer bc.close();

    String val1 = "Hello, Bitcask storage engine in C3!";
    core::Result put_res = bc.put("test_key_1", val1.ptr, val1.len);
    assert(put_res.is_ok());

    core::Buffer read_buf = core::buffer_init(64);
    defer read_buf.free();

    core::Result get_res = bc.get("test_key_1", &read_buf);
    assert(get_res.is_ok());
    assert(read_buf.as_string() == val1);

    // Test deletion
    core::Result del_res = bc.delete("test_key_1");
    assert(del_res.is_ok());

    core::Result get_del = bc.get("test_key_1", &read_buf);
    assert(get_del.is_err());
    assert(get_del.code == core::StorageError.NOT_FOUND);
}

fn void test_cas_deduplication() @test {
    storage::CasTable cas = storage::cas_init();

    String payload = "Identical binary payload block";
    char[128] out_key;
    usz out_klen = 0;

    bool dedup1 = cas.put(payload.ptr, payload.len, "obj_v1", &out_key[0], &out_klen);
    assert(dedup1 == false, "First insertion must be unique");

    bool dedup2 = cas.put(payload.ptr, payload.len, "obj_v2", &out_key[0], &out_klen);
    assert(dedup2 == true, "Second insertion with same content must be deduplicated");
    assert(out_klen == 6);
    String existing_key = (String)out_key[0:6];
    assert(existing_key == "obj_v1");
    assert(cas.duplicate_bytes_saved == payload.len);
}
