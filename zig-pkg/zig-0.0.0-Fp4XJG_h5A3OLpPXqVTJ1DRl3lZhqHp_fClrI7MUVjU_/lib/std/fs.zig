//! File System.

const std = @import("std.zig");

/// Deprecated, use `std.Io.Dir.path`.
pub const path = @import("fs/path.zig");
/// Deprecated, use `std.base64.url_safe_alphabet_chars`.
pub const base64_alphabet = std.base64.url_safe_alphabet_chars;
/// Deprecated, use `std.base64.url_safe.Encoder`.
pub const base64_encoder = std.base64.url_safe.Encoder;
/// Deprecated, use `std.base64.url_safe.Decoder`.
pub const base64_decoder = std.base64.url_safe.Decoder;
/// Deprecated, use `std.Io.Dir.max_path_bytes`.
pub const max_path_bytes = std.Io.Dir.max_path_bytes;
/// Deprecated, use `std.Io.Dir.max_name_bytes`.
pub const max_name_bytes = std.Io.Dir.max_name_bytes;

test {
    _ = path;
    _ = @import("fs/test.zig");
}
