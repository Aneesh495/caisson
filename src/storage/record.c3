// Module: caisson::storage
// Bitcask append-only write-ahead log record serialization and CRC verification.
//
// Part of the Caisson distributed object storage engine.

module caisson::storage;

import caisson::core;
import caisson::hash;

// Bitcask persistent log record header (28 bytes fixed size).
// Wire layout:
// [CRC32C: 4B][Timestamp: 8B][KeySize: 4B][ValSize: 8B][Deleted: 1B][Reserved: 3B]
struct RecordHeader {
    uint checksum;
    long timestamp;
    uint key_size;
    ulong val_size;
    char is_deleted;
}

const usz RECORD_HEADER_SIZE = 28;

fn void serialize_record_header(RecordHeader h, char* out_buf) {
    core::write_u32_be(out_buf, h.checksum);
    core::write_u64_be(out_buf + 4, (ulong)h.timestamp);
    core::write_u32_be(out_buf + 12, h.key_size);
    core::write_u64_be(out_buf + 16, h.val_size);
    out_buf[24] = h.is_deleted;
    out_buf[25] = 0;
    out_buf[26] = 0;
    out_buf[27] = 0;
}

fn RecordHeader deserialize_record_header(char* in_buf) {
    return (RecordHeader){
        .checksum = core::read_u32_be(in_buf),
        .timestamp = (long)core::read_u64_be(in_buf + 4),
        .key_size = core::read_u32_be(in_buf + 12),
        .val_size = core::read_u64_be(in_buf + 16),
        .is_deleted = in_buf[24]
    };
}

// Hint file record header (28 bytes fixed size).
// Wire layout:
// [Timestamp: 8B][KeySize: 4B][ValSize: 8B][ValPos: 8B][Key: KeySize B]
struct HintHeader {
    long timestamp;
    uint key_size;
    ulong val_size;
    ulong val_pos;
}

const usz HINT_HEADER_SIZE = 28;

fn void serialize_hint_header(HintHeader h, char* out_buf) {
    core::write_u64_be(out_buf, (ulong)h.timestamp);
    core::write_u32_be(out_buf + 8, h.key_size);
    core::write_u64_be(out_buf + 12, h.val_size);
    core::write_u64_be(out_buf + 20, h.val_pos);
}

fn HintHeader deserialize_hint_header(char* in_buf) {
    return (HintHeader){
        .timestamp = (long)core::read_u64_be(in_buf),
        .key_size = core::read_u32_be(in_buf + 8),
        .val_size = core::read_u64_be(in_buf + 12),
        .val_pos = core::read_u64_be(in_buf + 20)
    };
}
