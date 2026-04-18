const Writer = @This();
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const std = @import("../../std.zig");
const Io = std.Io;
const File = std.Io.File;
const assert = std.debug.assert;

io: Io,
file: File,
err: ?Error = null,
mode: Mode = .positional,
/// Tracks the true seek position in the file. To obtain the logical position,
/// use `logicalPos`.
pos: u64 = 0,
write_file_err: ?WriteFileError = null,
seek_err: ?SeekError = null,
interface: Io.Writer,

pub const Mode = File.Reader.Mode;

pub const Error = Io.Operation.FileWriteStreaming.Error || Io.Cancelable;

pub const WriteFileError = Error || error{
    /// Descriptor is not valid or locked, or an mmap(2)-like operation is not available for in_fd.
    Unimplemented,
    /// Can happen on FreeBSD when using copy_file_range.
    CorruptedData,
    EndOfStream,
    ReadFailed,
};

pub const SeekError = Io.File.SeekError;

pub fn init(file: File, io: Io, buffer: []u8) Writer {
    return .{
        .io = io,
        .file = file,
        .interface = initInterface(buffer),
        .mode = .positional,
    };
}

/// Positional is more threadsafe, since the global seek position is not
/// affected, but when such syscalls are not available, preemptively
/// initializing in streaming mode will skip a failed syscall.
pub fn initStreaming(file: File, io: Io, buffer: []u8) Writer {
    return .{
        .io = io,
        .file = file,
        .interface = initInterface(buffer),
        .mode = .streaming,
    };
}

/// Detects if `file` is terminal and sets the mode accordingly.
pub fn initDetect(file: File, io: Io, buffer: []u8) Io.Cancelable!Writer {
    return .{
        .io = io,
        .file = file,
        .interface = initInterface(buffer),
        .mode = try .detect(io, file, true, .positional),
    };
}

pub fn initInterface(buffer: []u8) Io.Writer {
    return .{
        .vtable = &.{
            .drain = drain,
            .sendFile = sendFile,
        },
        .buffer = buffer,
    };
}

pub fn moveToReader(w: *Writer) File.Reader {
    defer w.* = undefined;
    return .{
        .io = w.io,
        .file = w.file,
        .mode = w.mode,
        .pos = w.pos,
        .interface = File.Reader.initInterface(w.interface.buffer),
        .seek_err = w.seek_err,
    };
}

pub fn drain(io_w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const w: *Writer = @alignCast(@fieldParentPtr("interface", io_w));
    switch (w.mode) {
        .positional, .positional_simple => return drainPositional(w, data, splat),
        .streaming, .streaming_simple => return drainStreaming(w, data, splat),
        .failure => return error.WriteFailed,
    }
}

fn drainPositional(w: *Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const io = w.io;
    const header = w.interface.buffered();
    const n = io.vtable.fileWritePositional(io.userdata, w.file, header, data, splat, w.pos) catch |err| switch (err) {
        error.Unseekable => {
            w.mode = w.mode.toStreaming();
            const pos = w.pos;
            if (pos != 0) {
                w.pos = 0;
                w.seekTo(@intCast(pos)) catch {
                    w.mode = .failure;
                    return error.WriteFailed;
                };
            }
            return 0;
        },
        else => |e| {
            w.err = e;
            return error.WriteFailed;
        },
    };
    w.pos += n;
    return w.interface.consume(n);
}

fn drainStreaming(w: *Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const io = w.io;
    const header = w.interface.buffered();
    const n = w.file.writeStreaming(io, header, data, splat) catch |err| {
        w.err = err;
        return error.WriteFailed;
    };
    w.pos += n;
    return w.interface.consume(n);
}

pub fn sendFile(io_w: *Io.Writer, file_reader: *Io.File.Reader, limit: Io.Limit) Io.Writer.FileError!usize {
    const w: *Writer = @alignCast(@fieldParentPtr("interface", io_w));
    switch (w.mode) {
        .positional => return sendFilePositional(w, file_reader, limit),
        .positional_simple => return error.Unimplemented,
        .streaming => return sendFileStreaming(w, file_reader, limit),
        .streaming_simple => return error.Unimplemented,
        .failure => return error.WriteFailed,
    }
}

fn sendFilePositional(w: *Writer, file_reader: *Io.File.Reader, limit: Io.Limit) Io.Writer.FileError!usize {
    const io = w.io;
    const header = w.interface.buffered();
    const n = io.vtable.fileWriteFilePositional(io.userdata, w.file, header, file_reader, limit, w.pos) catch |err| switch (err) {
        error.Unseekable => {
            w.mode = w.mode.toStreaming();
            const pos = w.pos;
            if (pos != 0) {
                w.pos = 0;
                w.seekTo(@intCast(pos)) catch {
                    w.mode = .failure;
                    return error.WriteFailed;
                };
            }
            return 0;
        },
        error.Canceled => {
            w.err = error.Canceled;
            return error.WriteFailed;
        },
        error.EndOfStream => return error.EndOfStream,
        error.Unimplemented => return error.Unimplemented,
        error.ReadFailed => return error.ReadFailed,
        else => |e| {
            w.write_file_err = e;
            return error.WriteFailed;
        },
    };
    w.pos += n;
    return w.interface.consume(n);
}

fn sendFileStreaming(w: *Writer, file_reader: *Io.File.Reader, limit: Io.Limit) Io.Writer.FileError!usize {
    const io = w.io;
    const header = w.interface.buffered();
    const n = io.vtable.fileWriteFileStreaming(io.userdata, w.file, header, file_reader, limit) catch |err| switch (err) {
        error.Canceled => {
            w.err = error.Canceled;
            return error.WriteFailed;
        },
        error.EndOfStream => return error.EndOfStream,
        error.Unimplemented => return error.Unimplemented,
        error.ReadFailed => return error.ReadFailed,
        else => |e| {
            w.write_file_err = e;
            return error.WriteFailed;
        },
    };
    w.pos += n;
    return w.interface.consume(n);
}

pub fn seekTo(w: *Writer, offset: u64) (SeekError || Io.Writer.Error)!void {
    try w.interface.flush();
    try seekToUnbuffered(w, offset);
}

pub fn logicalPos(w: *const Writer) u64 {
    return w.pos + w.interface.end;
}

/// Asserts that no data is currently buffered.
pub fn seekToUnbuffered(w: *Writer, offset: u64) SeekError!void {
    assert(w.interface.buffered().len == 0);
    const io = w.io;
    switch (w.mode) {
        .positional, .positional_simple => {
            w.pos = offset;
        },
        .streaming, .streaming_simple => {
            if (w.seek_err) |err| return err;
            io.vtable.fileSeekTo(io.userdata, w.file, offset) catch |err| {
                w.seek_err = err;
                return err;
            };
            w.pos = offset;
        },
        .failure => return w.seek_err.?,
    }
}

pub const EndError = File.SetLengthError || Io.Writer.Error;

/// Flushes any buffered data and sets the end position of the file.
///
/// If not overwriting existing contents, then calling `interface.flush`
/// directly is sufficient.
///
/// Flush failure is handled by setting `err` so that it can be handled
/// along with other write failures.
pub fn end(w: *Writer) EndError!void {
    const io = w.io;
    try w.interface.flush();
    switch (w.mode) {
        .positional,
        .positional_simple,
        => w.file.setLength(io, w.pos) catch |err| switch (err) {
            error.NonResizable => return,
            else => |e| return e,
        },

        .streaming,
        .streaming_simple,
        .failure,
        => {},
    }
}

/// Convenience method for calling `Io.Writer.flush` and returning the
/// underlying error.
pub fn flush(w: *Writer) Error!void {
    w.interface.flush() catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}
