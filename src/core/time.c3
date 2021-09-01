// Module: caisson::core
// Time primitives, monotonic clocks, ISO 8601, and RFC 1123 HTTP date formatters.
//
// Part of the Caisson distributed object storage engine.

module caisson::core;

// POSIX time structures and functions.
struct TimeVal {
    long tv_sec;
    int tv_usec;
}

struct TimeSpec {
    long tv_sec;
    long tv_nsec;
}

struct Tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
    long tm_gmtoff;
    char* tm_zone;
}

extern fn int gettimeofday(TimeVal* tv, void* tz);
extern fn int clock_gettime(int clk_id, TimeSpec* tp);
extern fn Tm* gmtime_r(long* timer, Tm* result);

const int CLOCK_MONOTONIC_ID = 6; // Standard CLOCK_MONOTONIC on Darwin

// Returns current Unix timestamp in seconds.
fn long current_time_seconds() {
    TimeVal tv;
    gettimeofday(&tv, null);
    return tv.tv_sec;
}

// Returns current Unix timestamp in milliseconds.
fn ulong current_time_millis() {
    TimeVal tv;
    gettimeofday(&tv, null);
    return ((ulong)tv.tv_sec * 1000) + ((ulong)tv.tv_usec / 1000);
}

// Returns monotonic nanosecond timestamp for high-resolution latency measurements.
fn ulong monotonic_nanos() {
    TimeSpec ts;
    clock_gettime(CLOCK_MONOTONIC_ID, &ts);
    return ((ulong)ts.tv_sec * 1000000000) + (ulong)ts.tv_nsec;
}

// Formats Unix epoch seconds into RFC 1123 HTTP date header format.
// Example: "Sun, 06 Nov 1994 08:49:37 GMT"
fn void format_rfc1123_date(long timestamp_sec, char* out_buf) {
    const String[7] DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const String[12] MONTHS = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    };

    Tm tm_data;
    gmtime_r(&timestamp_sec, &tm_data);

    int wday = tm_data.tm_wday;
    if (wday < 0 || wday > 6) wday = 0;
    int mon = tm_data.tm_mon;
    if (mon < 0 || mon > 11) mon = 0;

    String day_str = DAYS[wday];
    out_buf[0] = day_str[0];
    out_buf[1] = day_str[1];
    out_buf[2] = day_str[2];
    out_buf[3] = ',';
    out_buf[4] = ' ';

    int mday = tm_data.tm_mday;
    out_buf[5] = (char)('0' + (mday / 10));
    out_buf[6] = (char)('0' + (mday % 10));
    out_buf[7] = ' ';

    String mon_str = MONTHS[mon];
    out_buf[8] = mon_str[0];
    out_buf[9] = mon_str[1];
    out_buf[10] = mon_str[2];
    out_buf[11] = ' ';

    int year = 1900 + tm_data.tm_year;
    out_buf[12] = (char)('0' + (year / 1000));
    out_buf[13] = (char)('0' + ((year / 100) % 10));
    out_buf[14] = (char)('0' + ((year / 10) % 10));
    out_buf[15] = (char)('0' + (year % 10));
    out_buf[16] = ' ';

    int hour = tm_data.tm_hour;
    out_buf[17] = (char)('0' + (hour / 10));
    out_buf[18] = (char)('0' + (hour % 10));
    out_buf[19] = ':';

    int min = tm_data.tm_min;
    out_buf[20] = (char)('0' + (min / 10));
    out_buf[21] = (char)('0' + (min % 10));
    out_buf[22] = ':';

    int sec = tm_data.tm_sec;
    out_buf[23] = (char)('0' + (sec / 10));
    out_buf[24] = (char)('0' + (sec % 10));

    out_buf[25] = ' ';
    out_buf[26] = 'G';
    out_buf[27] = 'M';
    out_buf[28] = 'T';
    out_buf[29] = '\0';
}

// Formats Unix epoch into ISO 8601 basic format for AWS SigV4 (e.g. "20261107T102358Z").
fn void format_iso8601_basic(long timestamp_sec, char* out_buf) {
    Tm tm_data;
    gmtime_r(&timestamp_sec, &tm_data);

    int year = 1900 + tm_data.tm_year;
    int mon = tm_data.tm_mon + 1;
    int mday = tm_data.tm_mday;
    int hour = tm_data.tm_hour;
    int min = tm_data.tm_min;
    int sec = tm_data.tm_sec;

    out_buf[0] = (char)('0' + (year / 1000));
    out_buf[1] = (char)('0' + ((year / 100) % 10));
    out_buf[2] = (char)('0' + ((year / 10) % 10));
    out_buf[3] = (char)('0' + (year % 10));

    out_buf[4] = (char)('0' + (mon / 10));
    out_buf[5] = (char)('0' + (mon % 10));

    out_buf[6] = (char)('0' + (mday / 10));
    out_buf[7] = (char)('0' + (mday % 10));

    out_buf[8] = 'T';

    out_buf[9] = (char)('0' + (hour / 10));
    out_buf[10] = (char)('0' + (hour % 10));

    out_buf[11] = (char)('0' + (min / 10));
    out_buf[12] = (char)('0' + (min % 10));

    out_buf[13] = (char)('0' + (sec / 10));
    out_buf[14] = (char)('0' + (sec % 10));

    out_buf[15] = 'Z';
    out_buf[16] = '\0';
}

// Formats Unix epoch into ISO 8601 extended format for S3 XML metadata.
// Example: "2026-11-07T10:23:58.000Z"
fn void format_iso8601_extended(long timestamp_sec, char* out_buf) {
    Tm tm_data;
    gmtime_r(&timestamp_sec, &tm_data);

    int year = 1900 + tm_data.tm_year;
    int mon = tm_data.tm_mon + 1;
    int mday = tm_data.tm_mday;
    int hour = tm_data.tm_hour;
    int min = tm_data.tm_min;
    int sec = tm_data.tm_sec;

    out_buf[0] = (char)('0' + (year / 1000));
    out_buf[1] = (char)('0' + ((year / 100) % 10));
    out_buf[2] = (char)('0' + ((year / 10) % 10));
    out_buf[3] = (char)('0' + (year % 10));
    out_buf[4] = '-';

    out_buf[5] = (char)('0' + (mon / 10));
    out_buf[6] = (char)('0' + (mon % 10));
    out_buf[7] = '-';

    out_buf[8] = (char)('0' + (mday / 10));
    out_buf[9] = (char)('0' + (mday % 10));
    out_buf[10] = 'T';

    out_buf[11] = (char)('0' + (hour / 10));
    out_buf[12] = (char)('0' + (hour % 10));
    out_buf[13] = ':';

    out_buf[14] = (char)('0' + (min / 10));
    out_buf[15] = (char)('0' + (min % 10));
    out_buf[16] = ':';

    out_buf[17] = (char)('0' + (sec / 10));
    out_buf[18] = (char)('0' + (sec % 10));
    out_buf[19] = '.';
    out_buf[20] = '0';
    out_buf[21] = '0';
    out_buf[22] = '0';
    out_buf[23] = 'Z';
    out_buf[24] = '\0';
}
