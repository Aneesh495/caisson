// Module: caisson::storage
// Background compactor, dead record reclaimer, and hint file generator.
//
// Part of the Caisson distributed object storage engine.

module caisson::storage;

import libc;
import std::core::mem;
import caisson::core;

struct Compactor {
    ulong bytes_reclaimed;
    ulong records_compacted;
}

fn Compactor compactor_init() {
    return (Compactor){ .bytes_reclaimed = 0, .records_compacted = 0 };
}

// Scans an existing data file, filters obsolete entries, and generates hint index files.
fn core::Result Compactor.compact_file(
    &this,
    Bitcask* storage,
    uint file_id
) {
    if (storage == null || file_id >= storage.active_file_id) {
        return core::result_ok(); // Cannot compact the currently active log file
    }

    char[280] data_path;
    format_file_path(&storage.dir_path[0], storage.dir_path_len, file_id, "data", &data_path[0]);

    libc::CFile fp = libc::fopen((ZString)&data_path[0], "rb");
    if (fp == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Data file does not exist");
    }
    defer libc::fclose(fp);

    char[280] hint_path;
    format_file_path(&storage.dir_path[0], storage.dir_path_len, file_id, "hint", &hint_path[0]);

    libc::CFile hint_fp = libc::fopen((ZString)&hint_path[0], "wb");
    if (hint_fp == null) {
        return core::result_err(core::StorageError.IO_ERROR, "Failed to create hint file");
    }
    defer libc::fclose(hint_fp);

    char[RECORD_HEADER_SIZE] hdr_buf;
    ulong current_offset = 0;

    while (true) {
        usz n = libc::fread(&hdr_buf[0], 1, RECORD_HEADER_SIZE, fp);
        if (n != RECORD_HEADER_SIZE) break; // EOF reached

        RecordHeader hdr = deserialize_record_header(&hdr_buf[0]);

        char[128] key_buf;
        usz klen = hdr.key_size < 127 ? hdr.key_size : 127;
        usz kn = libc::fread(&key_buf[0], 1, (usz)hdr.key_size, fp);
        if (kn != (usz)hdr.key_size) break;

        String key = (String)key_buf[0:klen];

        // Seek past value payload in source data file
        libc::fseek(fp, (long)hdr.val_size, 1); // SEEK_CUR

        ulong val_pos = current_offset + RECORD_HEADER_SIZE + hdr.key_size;
        current_offset += RECORD_HEADER_SIZE + hdr.key_size + hdr.val_size;

        // Check if this record is still the current live entry in KeyDir
        KeyDirEntry* current_entry = storage.keydir.get(key);
        if (current_entry != null &&
            current_entry.file_id == file_id &&
            current_entry.val_pos == val_pos &&
            hdr.is_deleted == 0) {

            // Record is alive: write hint entry
            HintHeader hint_hdr = {
                .timestamp = hdr.timestamp,
                .key_size = hdr.key_size,
                .val_size = hdr.val_size,
                .val_pos = val_pos
            };

            char[HINT_HEADER_SIZE] hint_buf;
            serialize_hint_header(hint_hdr, &hint_buf[0]);
            libc::fwrite(&hint_buf[0], 1, HINT_HEADER_SIZE, hint_fp);
            libc::fwrite(key.ptr, 1, key.len, hint_fp);

            this.records_compacted++;
        } else {
            this.bytes_reclaimed += RECORD_HEADER_SIZE + hdr.key_size + hdr.val_size;
        }
    }

    libc::fflush(hint_fp);
    return core::result_ok();
}
