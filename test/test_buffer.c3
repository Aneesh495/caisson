// Module: test_buffer
// Unit tests for dynamic byte buffer operations and transforms.
//
// Part of the Caisson distributed object storage engine.

module test_buffer;

import caisson::core;

fn void test_buffer_append_and_growth() @test {
    core::Buffer b = core::buffer_init(8);
    defer b.free();

    assert(b.len == 0);
    assert(b.cap >= 8);

    b.append_string("Hello, Caisson!");
    assert(b.len == 15);
    assert(b.starts_with("Hello"));
    assert(b.find_subsequence("Caisson", 7) == 7);
    assert(b.find_subsequence("NotFound", 8) == -1);

    b.append_u32_le(0xCAFE);
    assert(b.len == 19);
}

fn void test_buffer_hex_transforms() @test {
    char[4] raw = { (char)0xDE, (char)0xAD, (char)0xBE, (char)0xEF };
    char[9] hex_out;
    String encoded = core::hex_encode(&raw[0], 4, &hex_out[0]);
    assert(encoded.len == 8);
    assert(encoded == "deadbeef");

    char[4] decoded;
    usz dec_len = core::hex_decode(encoded, &decoded[0], 4);
    assert(dec_len == 4);
    assert(decoded[0] == (char)0xDE);
    assert(decoded[1] == (char)0xAD);
    assert(decoded[2] == (char)0xBE);
    assert(decoded[3] == (char)0xEF);
}

fn void test_buffer_base64_transforms() @test {
    char[3] raw = { 'M', 'a', 'n' };
    char[8] b64_out;
    usz out_len = core::base64_encode(&raw[0], 3, &b64_out[0], 8);
    assert(out_len == 4);
    assert(b64_out[0] == 'T');
    assert(b64_out[1] == 'W');
    assert(b64_out[2] == 'F');
    assert(b64_out[3] == 'u');
}
