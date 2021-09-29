// Module: caisson::storage
// In-memory Robin Hood hash table for sub-microsecond point lookups without disk seeks.
//
// Part of the Caisson distributed object storage engine.

module caisson::storage;

import std::core::mem;
import caisson::core;

struct KeyDirEntry {
    char[128] key_buf;
    usz key_len;
    uint file_id;
    ulong val_pos;
    ulong val_size;
    long timestamp;
    uint psl;
    bool occupied;
}

struct KeyDir {
    KeyDirEntry* entries;
    usz capacity;
    usz mask;
    usz count;
}

// 64-bit FNV-1a hash function for string keys.
fn ulong fnv1a_hash(char* data, usz len) {
    ulong hash = 0xcbf29ce484222325;
    for (usz i = 0; i < len; i++) {
        hash ^= (ulong)((char)data[i]);
        hash *= 0x100000001b3;
    }
    return hash;
}

fn KeyDir keydir_init(usz initial_capacity) {
    usz cap = 16;
    while (cap < initial_capacity) {
        cap <<= 1;
    }

    KeyDirEntry* entries = (KeyDirEntry*)mem::malloc((sz)(cap * KeyDirEntry::size));
    for (usz i = 0; i < cap; i++) {
        entries[i].occupied = false;
        entries[i].psl = 0;
        entries[i].key_len = 0;
    }

    return (KeyDir){
        .entries = entries,
        .capacity = cap,
        .mask = cap - 1,
        .count = 0
    };
}

fn void KeyDir.free(&this) {
    if (this.entries != null) {
        mem::free(this.entries);
        this.entries = null;
        this.capacity = 0;
        this.count = 0;
        this.mask = 0;
    }
}

fn void KeyDir.resize(&this) {
    usz old_cap = this.capacity;
    KeyDirEntry* old_entries = this.entries;

    usz new_cap = old_cap * 2;
    KeyDirEntry* new_entries = (KeyDirEntry*)mem::malloc((sz)(new_cap * KeyDirEntry::size));
    for (usz i = 0; i < new_cap; i++) {
        new_entries[i].occupied = false;
        new_entries[i].psl = 0;
        new_entries[i].key_len = 0;
    }

    this.entries = new_entries;
    this.capacity = new_cap;
    this.mask = new_cap - 1;
    this.count = 0;

    for (usz i = 0; i < old_cap; i++) {
        if (old_entries[i].occupied) {
            String k = (String)old_entries[i].key_buf[0:old_entries[i].key_len];
            this.put(k, old_entries[i].file_id, old_entries[i].val_pos,
                     old_entries[i].val_size, old_entries[i].timestamp);
        }
    }

    mem::free(old_entries);
}

fn void KeyDir.put(
    &this,
    String key,
    uint file_id,
    ulong val_pos,
    ulong val_size,
    long timestamp
) {
    // Resize when load factor exceeds 70%
    if (this.count * 10 >= this.capacity * 7) {
        this.resize();
    }

    // Check if key already exists, update in-place
    KeyDirEntry* existing = this.get(key);
    if (existing != null) {
        existing.file_id = file_id;
        existing.val_pos = val_pos;
        existing.val_size = val_size;
        existing.timestamp = timestamp;
        return;
    }

    KeyDirEntry entry;
    entry.key_len = key.len < 127 ? key.len : 127;
    mem::copy(&entry.key_buf[0], key.ptr, (sz)entry.key_len);
    entry.key_buf[entry.key_len] = '\0';
    entry.file_id = file_id;
    entry.val_pos = val_pos;
    entry.val_size = val_size;
    entry.timestamp = timestamp;
    entry.psl = 0;
    entry.occupied = true;

    ulong hash = fnv1a_hash(key.ptr, key.len);
    usz idx = (usz)(hash & this.mask);

    while (true) {
        if (!this.entries[idx].occupied) {
            this.entries[idx] = entry;
            this.count++;
            return;
        }

        // Robin Hood displacement: swap if new entry has traveled further
        if (entry.psl > this.entries[idx].psl) {
            KeyDirEntry tmp = this.entries[idx];
            this.entries[idx] = entry;
            entry = tmp;
        }

        entry.psl++;
        idx = (idx + 1) & this.mask;
    }
}

fn KeyDirEntry* KeyDir.get(&this, String key) {
    if (this.count == 0 || this.entries == null) return null;

    ulong hash = fnv1a_hash(key.ptr, key.len);
    usz idx = (usz)(hash & this.mask);
    uint psl = 0;

    while (true) {
        if (!this.entries[idx].occupied || psl > this.entries[idx].psl) {
            return null; // Key definitely does not exist
        }

        if (this.entries[idx].key_len == key.len) {
            String entry_key = (String)this.entries[idx].key_buf[0:key.len];
            if (entry_key == key) {
                return &this.entries[idx];
            }
        }

        psl++;
        idx = (idx + 1) & this.mask;
    }
}

fn bool KeyDir.delete(&this, String key) {
    if (this.count == 0 || this.entries == null) return false;

    ulong hash = fnv1a_hash(key.ptr, key.len);
    usz idx = (usz)(hash & this.mask);
    uint psl = 0;

    while (true) {
        if (!this.entries[idx].occupied || psl > this.entries[idx].psl) {
            return false;
        }

        if (this.entries[idx].key_len == key.len) {
            String entry_key = (String)this.entries[idx].key_buf[0:key.len];
            if (entry_key == key) {
                // Backward-shift deletion
                usz curr = idx;
                while (true) {
                    usz next = (curr + 1) & this.mask;
                    if (!this.entries[next].occupied || this.entries[next].psl == 0) {
                        this.entries[curr].occupied = false;
                        this.entries[curr].psl = 0;
                        break;
                    }
                    this.entries[curr] = this.entries[next];
                    this.entries[curr].psl--;
                    curr = next;
                }
                this.count--;
                return true;
            }
        }

        psl++;
        idx = (idx + 1) & this.mask;
    }
}
