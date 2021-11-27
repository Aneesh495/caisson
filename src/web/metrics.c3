// Module: caisson::web
// Prometheus and OpenMetrics telemetry exposition format generator.
//
// Part of the Caisson distributed object storage engine.

module caisson::web;

import caisson::core;
import caisson::http;
import caisson::s3;

// Appends a single metric line to the Prometheus output buffer.
fn void append_prometheus_metric(
    core::Buffer* b,
    String name,
    String help,
    String type_name,
    ulong value
) {
    b.append_string("# HELP ");
    b.append_string(name);
    b.append_string(" ");
    b.append_string(help);
    b.append_string("\n# TYPE ");
    b.append_string(name);
    b.append_string(" ");
    b.append_string(type_name);
    b.append_string("\n");
    b.append_string(name);
    b.append_string(" ");

    char[32] val_buf;
    usz v_len = http::int_to_ascii((long)value, &val_buf[0]);
    b.append_bytes(&val_buf[0], v_len);
    b.append_string("\n\n");
}

// Formats full Prometheus metrics exposition from S3 server context.
fn void format_prometheus_metrics(s3::S3Context* ctx, http::HttpResponse* resp) {
    resp.set_status(200, "OK");
    resp.add_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8");

    core::Buffer b = core::buffer_init(2048);

    append_prometheus_metric(
        &b,
        "caisson_storage_writes_total",
        "Total write operations to storage WAL",
        "counter",
        ctx != null ? ctx.storage.total_writes : 0
    );

    append_prometheus_metric(
        &b,
        "caisson_storage_reads_total",
        "Total read operations from storage",
        "counter",
        ctx != null ? ctx.storage.total_reads : 0
    );

    append_prometheus_metric(
        &b,
        "caisson_scrubber_stripes_scanned_total",
        "Number of erasure coding stripes scanned for bit rot",
        "counter",
        ctx != null ? ctx.scrubber.metrics.stripes_scanned : 0
    );

    append_prometheus_metric(
        &b,
        "caisson_scrubber_shards_repaired_total",
        "Number of corrupted shards auto-healed via Reed-Solomon",
        "counter",
        ctx != null ? ctx.scrubber.metrics.shards_repaired : 0
    );

    append_prometheus_metric(
        &b,
        "caisson_buckets_count",
        "Number of registered S3 buckets",
        "gauge",
        ctx != null ? (ulong)ctx.bucket_reg.count : 0
    );

    append_prometheus_metric(
        &b,
        "caisson_objects_count",
        "Number of active objects in catalog index",
        "gauge",
        ctx != null ? (ulong)ctx.obj_index.count : 0
    );

    resp.set_body_bytes(b.data, b.len);
    b.free();
}
