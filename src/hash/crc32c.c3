// Module: caisson::hash
// Castagnoli CRC32C (polynomial 0x82F63B78) implementation for end-to-end data integrity.
//
// Part of the Caisson distributed object storage engine.

module caisson::hash;

struct Crc32cTable {
    uint[256] table;
    bool initialized;
}

Crc32cTable global_crc32c;

// Generates Castagnoli CRC32C lookup table using reversed polynomial 0x82F63B78.
fn void crc32c_init() {
    if (global_crc32c.initialized) return;

    const uint POLY = 0x82F63B78;
    for (uint i = 0; i < 256; i++) {
        uint crc = i;
        for (uint j = 0; j < 8; j++) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ POLY;
            } else {
                crc >>= 1;
            }
        }
        global_crc32c.table[i] = crc;
    }
    global_crc32c.initialized = true;
}

// Computes Castagnoli CRC32C across a contiguous byte buffer.
fn uint crc32c_calculate(char* data, usz length) {
    if (!global_crc32c.initialized) crc32c_init();

    uint crc = 0xFFFFFFFF;
    for (usz i = 0; i < length; i++) {
        char b = data[i];
        uint table_idx = (crc ^ (uint)((char)b)) & 0xFF;
        crc = (crc >> 8) ^ global_crc32c.table[table_idx];
    }
    return crc ^ 0xFFFFFFFF;
}

// Incrementally updates an in-flight CRC32C with additional bytes.
fn uint crc32c_update(uint previous_crc, char* data, usz length) {
    if (!global_crc32c.initialized) crc32c_init();

    uint crc = previous_crc ^ 0xFFFFFFFF;
    for (usz i = 0; i < length; i++) {
        char b = data[i];
        uint table_idx = (crc ^ (uint)((char)b)) & 0xFF;
        crc = (crc >> 8) ^ global_crc32c.table[table_idx];
    }
    return crc ^ 0xFFFFFFFF;
}
