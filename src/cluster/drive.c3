// Module: caisson::cluster
// Storage drive abstractions, device telemetry, and fault domain topologies.
//
// Part of the Caisson distributed object storage engine.

module caisson::cluster;

import std::core::mem;

enum DriveStatus : int {
    ONLINE,
    DEGRADED,
    OFFLINE
}

struct StorageDrive {
    uint drive_id;
    char[128] mount_path;
    usz mount_path_len;
    DriveStatus status;
    ulong total_capacity;
    ulong used_bytes;
    ulong read_errors;
    ulong write_errors;
    bool occupied;
}

fn StorageDrive drive_init(uint id, String mount_path, ulong capacity) {
    StorageDrive d;
    d.drive_id = id;
    d.mount_path_len = mount_path.len < 127 ? mount_path.len : 127;
    mem::copy(&d.mount_path[0], mount_path.ptr, (sz)d.mount_path_len);
    d.mount_path[d.mount_path_len] = '\0';
    d.status = DriveStatus.ONLINE;
    d.total_capacity = capacity;
    d.used_bytes = 0;
    d.read_errors = 0;
    d.write_errors = 0;
    d.occupied = true;
    return d;
}

fn bool StorageDrive.is_available(this) {
    return this.occupied && this.status != DriveStatus.OFFLINE;
}
