const Atomic = @This();

const std = @import("../../std.zig");
const Io = std.Io;
const File = std.Io.File;
const Dir = std.Io.Dir;
const assert = std.debug.assert;

file: File,
file_basename_hex: u64,
file_open: bool,
file_exists: bool,

dir: Dir,
close_dir_on_deinit: bool,

dest_sub_path: []const u8,

pub const InitError = File.OpenError;

/// To release all resources, always call `deinit`, even after a successful
/// `finish`.
pub fn deinit(af: *Atomic, io: Io) void {
    if (af.file_open) {
        af.file.close(io);
        af.file_open = false;
    }
    if (af.file_exists) {
        const tmp_sub_path = std.fmt.hex(af.file_basename_hex);
        af.dir.deleteFile(io, &tmp_sub_path) catch {};
        af.file_exists = false;
    }
    if (af.close_dir_on_deinit) {
        af.dir.close(io);
        af.close_dir_on_deinit = false;
    }
    af.* = undefined;
}

pub const LinkError = File.HardLinkError || Dir.RenamePreserveError;

/// Atomically materializes the file into place, failing with
/// `error.PathAlreadyExists` if something already exists there.
///
/// If this operation could not be done with an unnamed temporary file, the
/// named temporary file will be deleted in a following operation, which may
/// independently fail. The result of that operation is stored in `delete_err`.
pub fn link(af: *Atomic, io: Io) LinkError!void {
    if (af.file_exists) {
        if (af.file_open) {
            af.file.close(io);
            af.file_open = false;
        }
        const tmp_sub_path = std.fmt.hex(af.file_basename_hex);
        try af.dir.renamePreserve(&tmp_sub_path, af.dir, af.dest_sub_path, io);
        af.file_exists = false;
    } else {
        assert(af.file_open);
        try af.file.hardLink(io, af.dir, af.dest_sub_path, .{});
        af.file.close(io);
        af.file_open = false;
    }
}

pub const ReplaceError = Dir.RenameError;

/// Atomically materializes the file into place, replacing any file that
/// already exists there.
///
/// Calling this function requires setting `CreateFileAtomicOptions.replace` to
/// `true`.
///
/// On Windows, this function introduces a period of time where some file
/// system operations on the destination file will result in
/// `error.AccessDenied`, including rename operations (such as the one used in
/// this function).
pub fn replace(af: *Atomic, io: Io) ReplaceError!void {
    assert(af.file_exists); // Wrong value for `CreateFileAtomicOptions.replace`.
    if (af.file_open) {
        af.file.close(io);
        af.file_open = false;
    }
    const tmp_sub_path = std.fmt.hex(af.file_basename_hex);
    try af.dir.rename(&tmp_sub_path, af.dir, af.dest_sub_path, io);
    af.file_exists = false;
}
