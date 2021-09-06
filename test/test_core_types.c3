// Module: test_core_types
// Unit tests for core endian converters, UUID generation, and bit twiddling.
//
// Part of the Caisson distributed object storage engine.

module test_core_types;

import caisson::core;

fn void test_u16_endian_roundtrip() @test {
    char[2] buf;
    core::write_u16_le(&buf[0], 0x1234);
    assert(buf[0] == 0x34);
    assert(buf[1] == 0x12);
    ushort val_le = core::read_u16_le(&buf[0]);
    assert(val_le == 0x1234);

    core::write_u16_be(&buf[0], 0x1234);
    assert(buf[0] == 0x12);
    assert(buf[1] == 0x34);
    ushort val_be = core::read_u16_be(&buf[0]);
    assert(val_be == 0x1234);
}

fn void test_u32_endian_roundtrip() @test {
    char[4] buf;
    core::write_u32_le(&buf[0], 0xDEADBEEF);
    assert(buf[0] == (char)0xEF);
    assert(buf[1] == (char)0xBE);
    assert(buf[2] == (char)0xAD);
    assert(buf[3] == (char)0xDE);
    uint val_le = core::read_u32_le(&buf[0]);
    assert(val_le == 0xDEADBEEF);

    core::write_u32_be(&buf[0], 0xDEADBEEF);
    assert(buf[0] == (char)0xDE);
    assert(buf[1] == (char)0xAD);
    assert(buf[2] == (char)0xBE);
    assert(buf[3] == (char)0xEF);
    uint val_be = core::read_u32_be(&buf[0]);
    assert(val_be == 0xDEADBEEF);
}

fn void test_u64_endian_roundtrip() @test {
    char[8] buf;
    ulong test_val = 0x0123456789ABCDEF;
    core::write_u64_le(&buf[0], test_val);
    ulong read_le = core::read_u64_le(&buf[0]);
    assert(read_le == test_val);

    core::write_u64_be(&buf[0], test_val);
    ulong read_be = core::read_u64_be(&buf[0]);
    assert(read_be == test_val);
}

fn void test_uuid_v4_generation() @test {
    core::RngState rng;
    rng.init(133742);

    core::Uuid u = core::uuid_v4(&rng);
    // Version 4 check
    assert((u.bytes[6] & 0xF0) == 0x40);
    // Variant check
    assert((u.bytes[8] & 0xC0) == 0x80);

    char[37] str;
    core::uuid_to_string(u, &str[0]);
    assert(str[8] == '-');
    assert(str[13] == '-');
    assert(str[18] == '-');
    assert(str[23] == '-');
    assert(str[14] == '4'); // version character
}
