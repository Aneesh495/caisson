// Module: caisson::s3
// AWS S3 standard XML error responses and HTTP status code mappings.
//
// Part of the Caisson distributed object storage engine.

module caisson::s3;

import caisson::core;
import caisson::http;

struct S3ErrorDef {
    String code;
    String message;
    int http_status;
}

fn S3ErrorDef get_s3_error(String code) {
    if (code == "NoSuchBucket") {
        return (S3ErrorDef){ .code = "NoSuchBucket", .message = "The specified bucket does not exist", .http_status = 404 };
    }
    if (code == "NoSuchKey") {
        return (S3ErrorDef){ .code = "NoSuchKey", .message = "The specified key does not exist", .http_status = 404 };
    }
    if (code == "BucketAlreadyExists") {
        return (S3ErrorDef){ .code = "BucketAlreadyExists", .message = "The requested bucket name is not available", .http_status = 409 };
    }
    if (code == "BucketNotEmpty") {
        return (S3ErrorDef){ .code = "BucketNotEmpty", .message = "The bucket you tried to delete is not empty", .http_status = 409 };
    }
    if (code == "InvalidBucketName") {
        return (S3ErrorDef){ .code = "InvalidBucketName", .message = "The specified bucket is not valid", .http_status = 400 };
    }
    if (code == "SignatureDoesNotMatch") {
        return (S3ErrorDef){ .code = "SignatureDoesNotMatch", .message = "The request signature we calculated does not match the signature you provided", .http_status = 403 };
    }
    if (code == "AccessDenied") {
        return (S3ErrorDef){ .code = "AccessDenied", .message = "Access Denied", .http_status = 403 };
    }
    if (code == "InvalidPart") {
        return (S3ErrorDef){ .code = "InvalidPart", .message = "One or more of the specified parts could not be found or part checksum mismatch", .http_status = 400 };
    }
    if (code == "NoSuchUpload") {
        return (S3ErrorDef){ .code = "NoSuchUpload", .message = "The specified multipart upload does not exist", .http_status = 404 };
    }
    if (code == "InvalidRange") {
        return (S3ErrorDef){ .code = "InvalidRange", .message = "The requested range is not satisfiable", .http_status = 416 };
    }
    return (S3ErrorDef){ .code = "InternalError", .message = "We encountered an internal error. Please try again.", .http_status = 500 };
}

// Formats an S3 XML error payload into the provided HttpResponse.
fn void format_s3_error(http::HttpResponse* resp, String code, String resource, String request_id) {
    S3ErrorDef err = get_s3_error(code);
    resp.set_status(err.http_status, err.message);
    resp.add_header("Content-Type", "application/xml");

    core::Buffer b = core::buffer_init(512);
    b.append_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    b.append_string("<Error>\n");
    b.append_string("  <Code>");
    b.append_string(err.code);
    b.append_string("</Code>\n");

    b.append_string("  <Message>");
    b.append_string(err.message);
    b.append_string("</Message>\n");

    if (resource.len > 0) {
        b.append_string("  <Resource>");
        b.append_string(resource);
        b.append_string("</Resource>\n");
    }

    b.append_string("  <RequestId>");
    b.append_string(request_id.len > 0 ? request_id : "CAISSON0000000001");
    b.append_string("</RequestId>\n");

    b.append_string("</Error>\n");

    resp.set_body_bytes(b.data, b.len);
    b.free();
}
