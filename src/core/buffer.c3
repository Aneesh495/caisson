// Module: caisson::core
// Dynamic byte buffer, memory slicing, hex and base64 transforms.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

import std::core::mem;

// Growable contiguous byte buffer suitable for network frames and chunk payloads.
struct Buffer {
    char* data;
    usz len;
    usz cap;
}

fn Buffer buffer_init(usz initial_capacity) {
    usz cap = initial_capacity > 16 ? initial_capacity : 16;
    char* ptr = (char*)mem::malloc((sz)cap);
    return (Buffer){ .data = ptr, .len = 0, .cap = cap };
}

fn Buffer buffer_from_string(String s) {
    Buffer b = buffer_init(s.len + 1);
    b.append_string(s);
    return b;
}

fn Buffer buffer_from_bytes(char* bytes, usz length) {
    Buffer b = buffer_init(length);
    b.append_bytes(bytes, length);
    return b;
}

fn void Buffer.free(&this) {
    if (this.data != null) {
        mem::free(this.data);
        this.data = null;
        this.len = 0;
        this.cap = 0;
    }
}

fn void Buffer.ensure_capacity(&this, usz additional) {
    usz required = this.len + additional;
    if (required <= this.cap) return;

    usz new_cap = this.cap * 2;
    if (new_cap < required) {
        new_cap = required + 64;
    }

    char* new_ptr = (char*)mem::malloc((sz)new_cap);
    if (this.len > 0 && this.data != null) {
        mem::copy(new_ptr, this.data, (sz)this.len);
    }
    if (this.data != null) {
        mem::free(this.data);
    }
    this.data = new_ptr;
    this.cap = new_cap;
}

fn void Buffer.append_byte(&this, char b) {
    this.ensure_capacity(1);
    this.data[this.len] = b;
    this.len++;
}

fn void Buffer.append_bytes(&this, char* bytes, usz count) {
    if (count == 0 || bytes == null) return;
    this.ensure_capacity(count);
    mem::copy(this.data + this.len, bytes, (sz)count);
    this.len += count;
}

fn void Buffer.append_string(&this, String s) {
    if (s.len == 0) return;
    this.append_bytes(s.ptr, s.len);
}

fn void Buffer.append_u16_le(&this, ushort val) {
    this.ensure_capacity(2);
    write_u16_le(this.data + this.len, val);
    this.len += 2;
}

fn void Buffer.append_u16_be(&this, ushort val) {
    this.ensure_capacity(2);
    write_u16_be(this.data + this.len, val);
    this.len += 2;
}

fn void Buffer.append_u32_le(&this, uint val) {
    this.ensure_capacity(4);
    write_u32_le(this.data + this.len, val);
    this.len += 4;
}

fn void Buffer.append_u32_be(&this, uint val) {
    this.ensure_capacity(4);
    write_u32_be(this.data + this.len, val);
    this.len += 4;
}

fn void Buffer.append_u64_le(&this, ulong val) {
    this.ensure_capacity(8);
    write_u64_le(this.data + this.len, val);
    this.len += 8;
}

fn void Buffer.append_u64_be(&this, ulong val) {
    this.ensure_capacity(8);
    write_u64_be(this.data + this.len, val);
    this.len += 8;
}

fn void Buffer.clear(&this) {
    this.len = 0;
}

fn void Buffer.truncate(&this, usz new_len) {
    if (new_len < this.len) {
        this.len = new_len;
    }
}

fn String Buffer.as_string(this) {
    if (this.len == 0 || this.data == null) return "";
    return (String)this.data[0:this.len];
}

fn bool Buffer.equals(&this, Buffer* other) {
    if (other == null) return false;
    if (this.len != other.len) return false;
    for (usz i = 0; i < this.len; i++) {
        if (this.data[i] != other.data[i]) return false;
    }
    return true;
}

fn bool Buffer.starts_with(&this, String prefix) {
    if (prefix.len > this.len) return false;
    for (usz i = 0; i < prefix.len; i++) {
        if (this.data[i] != prefix[i]) return false;
    }
    return true;
}

fn sz Buffer.index_of(&this, char target) {
    for (usz i = 0; i < this.len; i++) {
        if (this.data[i] == target) return (sz)i;
    }
    return -1;
}

fn sz Buffer.find_subsequence(&this, char* needle, usz needle_len) {
    if (needle_len == 0 || needle_len > this.len) return -1;
    usz max_start = this.len - needle_len;
    for (usz i = 0; i <= max_start; i++) {
        bool match = true;
        for (usz j = 0; j < needle_len; j++) {
            if (this.data[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) return (sz)i;
    }
    return -1;
}

// Hexadecimal encoding transforms.
fn String hex_encode(char* bytes, usz len, char* out_buf) {
    const char[16] HEX_DIGITS = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    };

    for (usz i = 0; i < len; i++) {
        char b = bytes[i];
        out_buf[i * 2] = HEX_DIGITS[(b >> 4) & 0x0F];
        out_buf[i * 2 + 1] = HEX_DIGITS[b & 0x0F];
    }
    out_buf[len * 2] = '\0';
    return (String)out_buf[0:len * 2];
}

fn usz hex_decode(String hex_str, char* out_bytes, usz max_out) {
    if (hex_str.len % 2 != 0) return 0;
    usz target_len = hex_str.len / 2;
    if (target_len > max_out) target_len = max_out;

    for (usz i = 0; i < target_len; i++) {
        char hi = hex_str[i * 2];
        char lo = hex_str[i * 2 + 1];

        int hi_val = 0;
        if (hi >= '0' && hi <= '9') {
            hi_val = hi - '0';
        } else if (hi >= 'a' && hi <= 'f') {
            hi_val = hi - 'a' + 10;
        } else if (hi >= 'A' && hi <= 'F') {
            hi_val = hi - 'A' + 10;
        } else {
            return 0;
        }

        int lo_val = 0;
        if (lo >= '0' && lo <= '9') {
            lo_val = lo - '0';
        } else if (lo >= 'a' && lo <= 'f') {
            lo_val = lo - 'a' + 10;
        } else if (lo >= 'A' && lo <= 'F') {
            lo_val = lo - 'A' + 10;
        } else {
            return 0;
        }

        out_bytes[i] = (char)((hi_val << 4) | lo_val);
    }
    return target_len;
}

// Base64 encoding and decoding for authorization headers and multipart signatures.
const char[64] BASE64_TABLE = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '+', '/'
};

fn usz base64_encode(char* src, usz src_len, char* dst, usz dst_max) {
    usz out_len = 4 * ((src_len + 2) / 3);
    if (out_len > dst_max) return 0;

    usz si = 0;
    usz di = 0;

    while (si < src_len) {
        uint b0 = (uint)((char)src[si++]);
        uint b1 = si < src_len ? (uint)((char)src[si++]) : 0;
        uint b2 = si < src_len ? (uint)((char)src[si++]) : 0;

        uint triple = (b0 << 16) | (b1 << 8) | b2;

        dst[di++] = BASE64_TABLE[(triple >> 18) & 0x3F];
        dst[di++] = BASE64_TABLE[(triple >> 12) & 0x3F];
        dst[di++] = (si > src_len + 1) ? '=' : BASE64_TABLE[(triple >> 6) & 0x3F];
        dst[di++] = (si > src_len) ? '=' : BASE64_TABLE[triple & 0x3F];
    }

    return di;
}
