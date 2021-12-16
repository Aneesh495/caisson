// Module: caisson::cli
// Forensic inspection tool for Bitcask append-only WAL data and hint logs.
//
// Part of the Caisson distributed object storage engine.

module caisson::cli;

import libc;
import std::io;
import std::core::mem;
import caisson::core;
import caisson::hash;
import caisson::storage;

fn int run_inspect_command(String path) {
    if (path.len == 0) {
        io::printn("[ERROR] Missing file path for inspect command. Usage: caisson inspect <path/to/*.data>");
        return 1;
    }

    char[512] cpath;
    mem::copy(&cpath[0], path.ptr, (sz)path.len);
    cpath[path.len] = '\0';

    libc::CFile fp = libc::fopen((ZString)&cpath[0], "rb");
    if (fp == null) {
        io::printfn("[ERROR] Could not open file '%s' for inspection", path);
        return 1;
    }
    defer libc::fclose(fp);

    io::printn("");
    io::printn("================================================================================");
    io::printfn("               CAISSON BITCASK WAL INSPECTOR: %s", path);
    io::printn("================================================================================");
    io::printn("");

    ulong offset = 0;
    uint total_records = 0;
    uint active_records = 0;
    uint tombstone_records = 0;
    uint corrupt_records = 0;

    char[storage::RECORD_HEADER_SIZE] hdr_buf;

    while (true) {
        usz r_hdr = libc::fread(&hdr_buf[0], 1, storage::RECORD_HEADER_SIZE, fp);
        if (r_hdr == 0) break; // EOF reached cleanly

        if (r_hdr != storage::RECORD_HEADER_SIZE) {
            io::printfn("[CORRUPT] Truncated header at offset 0x%08X", offset);
            corrupt_records++;
            break;
        }

        storage::RecordHeader hdr = storage::deserialize_record_header(&hdr_buf[0]);

        // Allocate and read key
        char* key_buf = (char*)mem::malloc((sz)(hdr.key_size + 1));
        usz r_key = libc::fread(key_buf, 1, (usz)hdr.key_size, fp);
        key_buf[hdr.key_size] = '\0';
        String key_str = (String)key_buf[0 : hdr.key_size];

        // Seek or read value to verify CRC
        bool crc_ok = true;
        uint computed_crc = hash::crc32c_calculate(&hdr_buf[4], storage::RECORD_HEADER_SIZE - 4);
        computed_crc = hash::crc32c_update(computed_crc, key_buf, (usz)hdr.key_size);

        if (hdr.val_size > 0) {
            char* val_buf = (char*)mem::malloc((sz)hdr.val_size);
            usz r_val = libc::fread(val_buf, 1, (usz)hdr.val_size, fp);
            if (r_val == (usz)hdr.val_size) {
                computed_crc = hash::crc32c_update(computed_crc, val_buf, (usz)hdr.val_size);
            } else {
                crc_ok = false;
            }
            mem::free(val_buf);
        }

        if (computed_crc != hdr.checksum) {
            crc_ok = false;
            corrupt_records++;
        }

        if (hdr.is_deleted != 0) {
            tombstone_records++;
        } else {
            active_records++;
        }
        total_records++;

        char[32] ts_str;
        core::format_iso8601_basic(hdr.timestamp, &ts_str[0]);

        io::printfn("[0x%08X] CRC=%s (0x%08X) TS=%s KEY=%s VAL_SZ=%d DEL=%d",
                    offset,
                    crc_ok ? "OK " : "ERR",
                    hdr.checksum,
                    (String)ts_str[0:16],
                    key_str,
                    hdr.val_size,
                    (int)hdr.is_deleted);

        mem::free(key_buf);
        offset += storage::RECORD_HEADER_SIZE + (ulong)hdr.key_size + hdr.val_size;
    }

    io::printn("");
    io::printn("--------------------------------------------------------------------------------");
    io::printfn("SUMMARY: Total=%d | Active=%d | Tombstones=%d | Corrupt=%d",
                total_records, active_records, tombstone_records, corrupt_records);
    io::printn("================================================================================");
    io::printn("");

    return corrupt_records > 0 ? 1 : 0;
}
