// Module: caisson::s3
// Unified S3 server context holding storage, index, auth, ring, and multipart sub-engines.
//
// Part of the Caisson distributed object storage engine.

module caisson::s3;

import caisson::core;
import caisson::auth;
import caisson::storage;
import caisson::index;
import caisson::multipart;
import caisson::cluster;

struct S3Context {
    String data_dir;
    ushort port;
    index::BucketRegistry bucket_reg;
    index::ObjectIndex obj_index;
    storage::Bitcask storage;
    multipart::MultipartManager mp_manager;
    auth::CredentialStore auth_store;
    cluster::HashRing ring;
    cluster::Scrubber scrubber;
    bool require_auth;
}

fn S3Context context_init(String data_dir, ushort port, bool require_auth) {
    S3Context ctx = (S3Context){
        .data_dir = data_dir,
        .port = port,
        .bucket_reg = index::bucket_registry_init(),
        .obj_index = index::object_index_init(1024),
        .storage = storage::bitcask_open(data_dir, 64 * 1024 * 1024),
        .mp_manager = multipart::multipart_manager_init(32),
        .auth_store = auth::credential_store_init(),
        .ring = cluster::ring_init(32),
        .scrubber = cluster::scrubber_init(),
        .require_auth = require_auth
    };

    // Add default admin credentials
    ctx.auth_store.add("minioadmin", "minioadmin", "us-east-1", "s3");
    ctx.auth_store.add("caisson", "caissonsecretkey", "us-east-1", "s3");

    return ctx;
}

fn void S3Context.free(&this) {
    this.obj_index.free();
    this.storage.close();
    this.mp_manager.free();
}
