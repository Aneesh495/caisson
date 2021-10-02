// Module: caisson::storage
// Bitcask log-structured merge storage engine with append-only WAL and KeyDir indexing.
//
// Part of the Caisson distributed object storage engine.

module caisson::storage;

import libc;
import std::core::mem;
import caisson::core;
import caisson::hash;

extern fn int mkdir(char* path, int mode);

struct Bitcask {
    char[256] dir_path;
    usz dir_path_len;
    uint active_file_id;
    libc::CFile active_file;
    ulong active_offset;
    ulong max_file_size;
    KeyDir keydir;
    ulong total_writes;
    ulong total_reads;
}

// Builds file path: "<dir>/<file_id:06d>.<ext>"
fn void format_file_path(
    char* dir,
    usz dir_len,
    uint file_id,
    String ext,
    char* out_path
) {
    mem::copy(out_path, dir, (sz)dir_len);
    usz idx = dir_len;
    if (idx > 0 && out_path[idx - 1] != '/') {
        out_path[idx++] = '/';
    }

    // Format 6-digit zero-padded file ID
    uint divisor = 100000;
    uint temp_id = file_id;
    for (int i = 0; i < 6; i++) {
        uint digit = temp_id / divisor;
        out_path[idx++] = (char)('0' + digit);
        temp_id %= divisor;
        divisor /= 10;
    }

    out_path[idx++] = '.';
    for (usz i = 0; i < ext.len; i++) {
        out_path[idx++] = ext[i];
    }
    out_path[idx] = '\0';
}

fn Bitcask bitcask_open(String dir_path, ulong max_file_size) {
    Bitcask b;
    b.dir_path_len = dir_path.len < 255 ? dir_path.len : 255;
    mem::copy(&b.dir_path[0], dir_path.ptr, (sz)b.dir_path_len);
    b.dir_path[b.dir_path_len] = '\0';

    b.max_file_size = max_file_size > 0 ? max_file_size : (64 * 1024 * 1024);
    b.active_file_id = 0;
    b.active_offset = 0;
    b.keydir = keydir_init(1024);
    b.total_writes = 0;
    b.total_reads = 0;

    // Create storage directory if it does not exist
    mkdir(&b.dir_path[0], 0o755);

    // Open active data file 000000.data in append/read binary mode
    char[280] path_buf;
    format_file_path(&b.dir_path[0], b.dir_path_len, b.active_file_id, "data", &path_buf[0]);
    b.active_file = libc::fopen((ZString)&path_buf[0], "a+b");
    if (b.active_file != null) {
        libc::fseek(b.active_file, 0, 2); // SEEK_END
        long end_pos = libc::ftell(b.active_file);
        b.active_offset = end_pos >= 0 ? (ulong)end_pos : 0;
    }

    return b;
}

fn void Bitcask.close(&this) {
    if (this.active_file != null) {
        libc::fflush(this.active_file);
        libc::fclose(this.active_file);
        this.active_file = null;
    }
    this.keydir.free();
}

fn void Bitcask.rotate_file(&this) {
    if (this.active_file != null) {
        libc::fflush(this.active_file);
        libc::fclose(this.active_file);
    }

    this.active_file_id++;
    this.active_offset = 0;

    char[280] path_buf;
    format_file_path(&this.dir_path[0], this.dir_path_len, this.active_file_id, "data", &path_buf[0]);
    this.active_file = libc::fopen((ZString)&path_buf[0], "a+b");
}

// Appends a key-value record to the active Bitcask data log.
fn core::Result Bitcask.put(&this, String key, char* val_data, usz val_len) {
    if (this.active_file == null) {
        return core::result_err(core::StorageError.IO_ERROR, "Storage engine not open");
    }

    // Check if active file needs rotation
    usz record_total = RECORD_HEADER_SIZE + key.len + val_len;
    if (this.active_offset + record_total > this.max_file_size) {
        this.rotate_file();
    }

    long now = core::current_time_seconds();

    // Compute CRC32C over payload: Key || Value
    uint crc = 0;
    if (key.len > 0) {
        crc = hash::crc32c_calculate(key.ptr, key.len);
    }
    if (val_len > 0 && val_data != null) {
        crc = hash::crc32c_update(crc, val_data, val_len);
    }

    RecordHeader header = {
        .checksum = crc,
        .timestamp = now,
        .key_size = (uint)key.len,
        .val_size = (ulong)val_len,
        .is_deleted = 0
    };

    char[RECORD_HEADER_SIZE] hdr_buf;
    serialize_record_header(header, &hdr_buf[0]);

    // Write header
    usz w_hdr = libc::fwrite(&hdr_buf[0], 1, RECORD_HEADER_SIZE, this.active_file);
    if (w_hdr != RECORD_HEADER_SIZE) {
        return core::result_err(core::StorageError.IO_ERROR, "Failed to write record header");
    }

    // Write key
    if (key.len > 0) {
        usz w_key = libc::fwrite(key.ptr, 1, key.len, this.active_file);
        if (w_key != key.len) {
            return core::result_err(core::StorageError.IO_ERROR, "Failed to write record key");
        }
    }

    // Write value payload
    if (val_len > 0 && val_data != null) {
        usz w_val = libc::fwrite(val_data, 1, val_len, this.active_file);
        if (w_val != val_len) {
            return core::result_err(core::StorageError.IO_ERROR, "Failed to write record value");
        }
    }

    libc::fflush(this.active_file);

    // Update in-memory KeyDir
    ulong val_pos = this.active_offset + RECORD_HEADER_SIZE + key.len;
    this.keydir.put(key, this.active_file_id, val_pos, (ulong)val_len, now);

    this.active_offset += record_total;
    this.total_writes++;

    return core::result_ok();
}

// Retrieves a value by key directly from the appropriate data file.
fn core::Result Bitcask.get(&this, String key, core::Buffer* out_val) {
    KeyDirEntry* entry = this.keydir.get(key);
    if (entry == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Key does not exist in storage");
    }

    char[280] path_buf;
    format_file_path(&this.dir_path[0], this.dir_path_len, entry.file_id, "data", &path_buf[0]);

    libc::CFile fp = libc::fopen((ZString)&path_buf[0], "rb");
    if (fp == null) {
        return core::result_err(core::StorageError.IO_ERROR, "Failed to open data file for reading");
    }
    defer libc::fclose(fp);

    libc::fseek(fp, (long)entry.val_pos, 0); // SEEK_SET

    out_val.clear();
    out_val.ensure_capacity((usz)entry.val_size);

    if (entry.val_size > 0) {
        usz bytes_read = libc::fread(out_val.data, 1, (usz)entry.val_size, fp);
        if (bytes_read != (usz)entry.val_size) {
            return core::result_err(core::StorageError.IO_ERROR, "Failed to read complete value payload");
        }
        out_val.len = (usz)entry.val_size;
    }

    this.total_reads++;
    return core::result_ok();
}

// Appends a tombstone deletion record to the log and removes key from in-memory KeyDir.
fn core::Result Bitcask.delete(&this, String key) {
    if (this.active_file == null) {
        return core::result_err(core::StorageError.IO_ERROR, "Storage engine not open");
    }

    KeyDirEntry* entry = this.keydir.get(key);
    if (entry == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Key does not exist");
    }

    long now = core::current_time_seconds();
    RecordHeader header = {
        .checksum = 0,
        .timestamp = now,
        .key_size = (uint)key.len,
        .val_size = 0,
        .is_deleted = 1
    };

    char[RECORD_HEADER_SIZE] hdr_buf;
    serialize_record_header(header, &hdr_buf[0]);

    libc::fwrite(&hdr_buf[0], 1, RECORD_HEADER_SIZE, this.active_file);
    if (key.len > 0) {
        libc::fwrite(key.ptr, 1, key.len, this.active_file);
    }
    libc::fflush(this.active_file);

    this.active_offset += RECORD_HEADER_SIZE + key.len;
    this.keydir.delete(key);

    return core::result_ok();
}
