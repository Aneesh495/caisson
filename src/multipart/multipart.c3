// Module: caisson::multipart
// Multipart upload pipeline, concurrent chunk staging, and composite ETag synthesis.
//
// Part of the Caisson distributed object storage engine.

module caisson::multipart;

import std::core::mem;
import caisson::core;
import caisson::hash;

struct ClientPart {
    uint part_number;
    String etag;
}

struct MultipartManager {
    MultipartSession* sessions;
    uint capacity;
    uint active_count;
    core::RngState rng;
}

fn MultipartManager multipart_manager_init(uint capacity) {
    uint cap = capacity > 0 ? capacity : 32;
    MultipartSession* ptr = (MultipartSession*)mem::malloc((sz)(cap * MultipartSession::size));
    for (uint i = 0; i < cap; i++) {
        ptr[i].occupied = false;
        ptr[i].part_count = 0;
    }

    MultipartManager mgr;
    mgr.sessions = ptr;
    mgr.capacity = cap;
    mgr.active_count = 0;
    mgr.rng.init(88776655);
    return mgr;
}

fn void MultipartManager.free(&this) {
    if (this.sessions != null) {
        mem::free(this.sessions);
        this.sessions = null;
        this.capacity = 0;
        this.active_count = 0;
    }
}

// Initiates a new multipart upload session, generating an RFC 4122 upload ID.
fn core::Result MultipartManager.initiate_upload(
    &this,
    String bucket,
    String key,
    char* out_upload_id
) {
    core::Uuid u = core::uuid_v4(&this.rng);
    core::uuid_to_string(u, out_upload_id);
    String uid_str = (String)out_upload_id[0:36];

    for (uint i = 0; i < this.capacity; i++) {
        if (!this.sessions[i].occupied) {
            this.sessions[i] = session_init(uid_str, bucket, key);
            this.active_count++;
            return core::result_ok();
        }
    }

    return core::result_err(core::StorageError.CAPACITY_EXCEEDED, "Concurrent multipart sessions limit exceeded");
}

fn MultipartSession* MultipartManager.find_session(&this, String upload_id) {
    for (uint i = 0; i < this.capacity; i++) {
        if (this.sessions[i].occupied && !this.sessions[i].completed && !this.sessions[i].aborted) {
            String uid = (String)this.sessions[i].upload_id[0:this.sessions[i].upload_id_len];
            if (uid == upload_id) {
                return &this.sessions[i];
            }
        }
    }
    return null;
}

// Stages a single uploaded part, computing its MD5 checksum and recording part metadata.
fn core::Result MultipartManager.upload_part(
    &this,
    String upload_id,
    uint part_number,
    char* part_data,
    usz part_size,
    char* out_etag
) {
    if (part_number < 1 || part_number > 10000) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "Part number must be between 1 and 10000");
    }

    MultipartSession* session = this.find_session(upload_id);
    if (session == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Multipart upload session not found");
    }

    // Compute MD5 ETag of part payload
    char[16] digest;
    hash::md5_hash(part_data, part_size, &digest[0]);
    String etag_str = core::hex_encode(&digest[0], 16, out_etag);

    // Update existing part or insert new part record
    for (uint i = 0; i < session.part_count; i++) {
        if (session.parts[i].occupied && session.parts[i].part_number == part_number) {
            session.parts[i].size = (ulong)part_size;
            mem::copy(&session.parts[i].etag[0], etag_str.ptr, 32);
            session.parts[i].etag[32] = '\0';
            session.parts[i].etag_len = 32;
            session.parts[i].uploaded_at = core::current_time_seconds();
            return core::result_ok();
        }
    }

    if (session.part_count < 100) {
        uint idx = session.part_count;
        session.parts[idx].part_number = part_number;
        session.parts[idx].size = (ulong)part_size;
        mem::copy(&session.parts[idx].etag[0], etag_str.ptr, 32);
        session.parts[idx].etag[32] = '\0';
        session.parts[idx].etag_len = 32;
        session.parts[idx].uploaded_at = core::current_time_seconds();
        session.parts[idx].occupied = true;
        session.part_count++;
        return core::result_ok();
    }

    return core::result_err(core::StorageError.CAPACITY_EXCEEDED, "Part count limit exceeded for session");
}

// Completes a multipart upload, verifying part numbers and ETags, and computing composite ETag.
fn core::Result MultipartManager.complete_upload(
    &this,
    String upload_id,
    ClientPart* client_parts,
    uint client_part_count,
    char* out_composite_etag
) {
    MultipartSession* session = this.find_session(upload_id);
    if (session == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Session not found");
    }

    if (client_part_count == 0) {
        return core::result_err(core::StorageError.INVALID_ARGUMENT, "No parts provided in completion request");
    }

    // Verify client parts are ordered and match session uploaded parts
    uint last_num = 0;
    hash::Md5Context composite_md5;
    hash::md5_init(&composite_md5);

    for (uint i = 0; i < client_part_count; i++) {
        uint pnum = client_parts[i].part_number;
        if (pnum <= last_num) {
            return core::result_err(core::StorageError.INVALID_ARGUMENT, "Part numbers must be in strictly ascending order");
        }
        last_num = pnum;

        // Verify part exists in session
        bool found = false;
        for (uint j = 0; j < session.part_count; j++) {
            if (session.parts[j].occupied && session.parts[j].part_number == pnum) {
                String session_etag = (String)session.parts[j].etag[0:session.parts[j].etag_len];
                if (session_etag == client_parts[i].etag) {
                    found = true;

                    // Convert hex ETag to raw bytes and feed into composite MD5
                    char[16] raw_md5;
                    core::hex_decode(session_etag, &raw_md5[0], 16);
                    hash::md5_update(&composite_md5, &raw_md5[0], 16);
                    break;
                }
            }
        }

        if (!found) {
            return core::result_err(core::StorageError.INVALID_ARGUMENT, "Mismatched part number or ETag");
        }
    }

    // Finalize composite MD5: "<hash>-<part_count>"
    char[16] final_digest;
    hash::md5_final(&composite_md5, &final_digest[0]);

    char[33] hex_buf;
    String hex_str = core::hex_encode(&final_digest[0], 16, &hex_buf[0]);

    mem::copy(out_composite_etag, hex_str.ptr, 32);
    out_composite_etag[32] = '-';

    // Format part count number
    uint count = client_part_count;
    char[10] count_str;
    int c_idx = 0;
    if (count == 0) {
        count_str[c_idx++] = '0';
    } else {
        char[10] tmp;
        int t_idx = 0;
        while (count > 0) {
            tmp[t_idx++] = (char)('0' + (count % 10));
            count /= 10;
        }
        while (t_idx > 0) {
            count_str[c_idx++] = tmp[--t_idx];
        }
    }

    for (int i = 0; i < c_idx; i++) {
        out_composite_etag[33 + i] = count_str[i];
    }
    out_composite_etag[33 + c_idx] = '\0';

    session.completed = true;
    return core::result_ok();
}

// Aborts an upload session and invalidates all uploaded part records.
fn core::Result MultipartManager.abort_upload(
    &this,
    String upload_id
) {
    MultipartSession* session = this.find_session(upload_id);
    if (session == null) {
        return core::result_err(core::StorageError.NOT_FOUND, "Session not found");
    }

    session.aborted = true;
    session.occupied = false;
    this.active_count--;
    return core::result_ok();
}
