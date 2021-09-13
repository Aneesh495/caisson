// Module: caisson::erasure
// Object striping, stripe headers, padding, and assembly pipeline.
//
// Part of the Caisson distributed object storage engine.

module caisson::erasure;

import std::core::mem;
import caisson::core;

const uint STRIPE_MAGIC = 0x43414953; // "CAIS" in ASCII
const ushort STRIPE_VERSION = 1;

// Metadata header prepended to each persistent shard on disk.
struct StripeHeader {
    uint magic;
    ushort version_num;
    ushort data_shards;
    ushort parity_shards;
    ushort shard_index;
    ulong payload_size;
    uint checksum;
}

fn void serialize_stripe_header(StripeHeader h, char* out_buf) {
    core::write_u32_be(out_buf, h.magic);
    core::write_u16_be(out_buf + 4, h.version_num);
    core::write_u16_be(out_buf + 6, h.data_shards);
    core::write_u16_be(out_buf + 8, h.parity_shards);
    core::write_u16_be(out_buf + 10, h.shard_index);
    core::write_u64_be(out_buf + 12, h.payload_size);
    core::write_u32_be(out_buf + 20, h.checksum);
}

fn StripeHeader deserialize_stripe_header(char* in_buf) {
    return (StripeHeader){
        .magic = core::read_u32_be(in_buf),
        .version_num = core::read_u16_be(in_buf + 4),
        .data_shards = core::read_u16_be(in_buf + 6),
        .parity_shards = core::read_u16_be(in_buf + 8),
        .shard_index = core::read_u16_be(in_buf + 10),
        .payload_size = core::read_u64_be(in_buf + 12),
        .checksum = core::read_u32_be(in_buf + 20)
    };
}

// Splits an arbitrary payload into K padded data shards of shard_size bytes.
fn void stripe_split_payload(
    char* payload,
    usz payload_len,
    uint k,
    usz shard_size,
    char** out_data_shards
) {
    usz total_capacity = (usz)k * shard_size;
    usz bytes_copied = 0;

    for (uint i = 0; i < k; i++) {
        char* shard_buf = out_data_shards[i];
        for (usz j = 0; j < shard_size; j++) {
            if (bytes_copied < payload_len) {
                shard_buf[j] = payload[bytes_copied++];
            } else {
                shard_buf[j] = 0; // Zero padding for remainder of stripe
            }
        }
    }
}

// Reassembles the original payload from K data shards, truncating zero-padding.
fn void stripe_assemble_payload(
    char** data_shards,
    uint k,
    usz shard_size,
    usz original_len,
    char* out_payload
) {
    usz bytes_written = 0;

    for (uint i = 0; i < k; i++) {
        char* shard_buf = data_shards[i];
        for (usz j = 0; j < shard_size && bytes_written < original_len; j++) {
            out_payload[bytes_written++] = shard_buf[j];
        }
    }
}
