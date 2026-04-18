//! Memoizes key information about a file handle such as:
//! * The size from calling stat, or the error that occurred therein.
//! * The current seek position.
//! * The error that occurred when trying to seek.
//! * Whether reading should be done positionally or streaming.
//! * Whether reading should be done via fd-to-fd syscalls (e.g. `sendfile`)
//!   versus plain variants (e.g. `read`).
//!
//! Fulfills the `Io.Reader` interface.
const Reader = @This();

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
size: ?u64 = null,
size_err: ?SizeError = null,
seek_err: ?SeekError = null,
interface: Io.Reader,

pub const Error = Io.Operation.FileReadStreaming.UnendingError || Io.Cancelable;

pub const SizeError = File.StatError || error{
    /// Occurs if, for example, the file handle is a network socket and therefore does not have a size.
    Streaming,
};

pub const SeekError = File.SeekError || error{
    /// Seeking fell back to reading, and reached the end before the requested seek position.
    /// `pos` remains at the end of the file.
    EndOfStream,
    /// Seeking fell back to reading, which failed.
    ReadFailed,
};

pub const Mode = enum {
    streaming,
    positional,
    /// Avoid syscalls other than `read` and `readv`.
    streaming_simple,
    /// Avoid syscalls other than `pread` and `preadv`.
    positional_simple,
    /// Indicates reading cannot continue because of a seek failure.
    failure,

    pub fn toStreaming(m: @This()) @This() {
        return switch (m) {
            .positional, .streaming => .streaming,
            .positional_simple, .streaming_simple => .streaming_simple,
            .failure => .failure,
        };
    }

    pub fn toSimple(m: @This()) @This() {
        return switch (m) {
            .positional, .positional_simple => .positional_simple,
            .streaming, .streaming_simple => .streaming_simple,
            .failure => .failure,
        };
    }
};

pub fn initInterface(buffer: []u8) Io.Reader {
    return .{
        .vtable = &.{
            .stream = stream,
            .discard = discard,
            .readVec = readVec,
        },
        .buffer = buffer,
        .seek = 0,
        .end = 0,
    };
}

pub fn init(file: File, io: Io, buffer: []u8) Reader {
    return .{
        .io = io,
        .file = file,
        .interface = initInterface(buffer),
    };
}

pub fn initSize(file: File, io: Io, buffer: []u8, size: ?u64) Reader {
    return .{
        .io = io,
        .file = file,
        .interface = initInterface(buffer),
        .size = size,
    };
}

/// Positional is more threadsafe, since the global seek position is not
/// affected, but when such syscalls are not available, preemptively
/// initializing in streaming mode skips a failed syscall.
pub fn initStreaming(file: File, io: Io, buffer: []u8) Reader {
    return .{
        .io = io,
        .file = file,
        .interface = Reader.initInterface(buffer),
        .mode = .streaming,
        .seek_err = error.Unseekable,
        .size_err = error.Streaming,
    };
}

pub fn getSize(r: *Reader) SizeError!u64 {
    return r.size orelse {
        if (r.size_err) |err| return err;
        if (r.file.stat(r.io)) |st| {
            if (st.kind == .file) {
                r.size = st.size;
                return st.size;
            } else {
                r.mode = r.mode.toStreaming();
                r.size_err = error.Streaming;
                return error.Streaming;
            }
        } else |err| {
            r.size_err = err;
            return err;
        }
    };
}

pub fn seekBy(r: *Reader, offset: i64) SeekError!void {
    const io = r.io;
    switch (r.mode) {
        .positional, .positional_simple => {
            setLogicalPos(r, @intCast(@as(i64, @intCast(logicalPos(r))) + offset));
        },
        .streaming, .streaming_simple => {
            const seek_err = r.seek_err orelse e: {
                if (io.vtable.fileSeekBy(io.userdata, r.file, offset)) |_| {
                    setLogicalPos(r, @intCast(@as(i64, @intCast(logicalPos(r))) + offset));
                    return;
                } else |err| {
                    r.seek_err = err;
                    break :e err;
                }
            };
            var remaining = std.math.cast(u64, offset) orelse return seek_err;
            while (remaining > 0) {
                remaining -= discard(&r.interface, .limited64(remaining)) catch |err| {
                    r.seek_err = err;
                    return err;
                };
            }
            r.interface.tossBuffered();
        },
        .failure => return r.seek_err.?,
    }
}

/// Repositions logical read offset relative to the beginning of the file.
pub fn seekTo(r: *Reader, offset: u64) SeekError!void {
    const io = r.io;
    switch (r.mode) {
        .positional, .positional_simple => {
            setLogicalPos(r, offset);
        },
        .streaming, .streaming_simple => {
            const logical_pos = logicalPos(r);
            if (offset >= logical_pos) return seekBy(r, @intCast(offset - logical_pos));
            if (r.seek_err) |err| return err;
            io.vtable.fileSeekTo(io.userdata, r.file, offset) catch |err| {
                r.seek_err = err;
                return err;
            };
            setLogicalPos(r, offset);
        },
        .failure => return r.seek_err.?,
    }
}

pub fn logicalPos(r: *const Reader) u64 {
    return r.pos - r.interface.bufferedLen();
}

fn setLogicalPos(r: *Reader, offset: u64) void {
    const logical_pos = r.logicalPos();
    if (offset < logical_pos or offset >= r.pos) {
        r.interface.tossBuffered();
        r.pos = offset;
    } else r.interface.toss(@intCast(offset - logical_pos));
}

/// Number of slices to store on the stack, when trying to send as many byte
/// vectors through the underlying read calls as possible.
const max_buffers_len = 16;

fn stream(io_reader: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
    const r: *Reader = @alignCast(@fieldParentPtr("interface", io_reader));
    return streamMode(r, w, limit, r.mode);
}

pub fn streamMode(r: *Reader, w: *Io.Writer, limit: Io.Limit, mode: Mode) Io.Reader.StreamError!usize {
    switch (mode) {
        .positional, .streaming => return w.sendFile(r, limit) catch |write_err| switch (write_err) {
            error.Unimplemented => {
                r.mode = r.mode.toSimple();
                return 0;
            },
            else => |e| return e,
        },
        .positional_simple => {
            const dest = limit.slice(try w.writableSliceGreedy(1));
            var data: [1][]u8 = .{dest};
            const n = try readVecPositional(r, &data);
            w.advance(n);
            return n;
        },
        .streaming_simple => {
            const dest = limit.slice(try w.writableSliceGreedy(1));
            var data: [1][]u8 = .{dest};
            const n = try readVecStreaming(r, &data);
            w.advance(n);
            return n;
        },
        .failure => return error.ReadFailed,
    }
}

fn readVec(io_reader: *Io.Reader, data: [][]u8) Io.Reader.Error!usize {
    const r: *Reader = @alignCast(@fieldParentPtr("interface", io_reader));
    switch (r.mode) {
        .positional, .positional_simple => return readVecPositional(r, data),
        .streaming, .streaming_simple => return readVecStreaming(r, data),
        .failure => return error.ReadFailed,
    }
}

fn readVecPositional(r: *Reader, data: [][]u8) Io.Reader.Error!usize {
    const io = r.io;
    var iovecs_buffer: [max_buffers_len][]u8 = undefined;
    const dest_n, const data_size = try r.interface.writableVector(&iovecs_buffer, data);
    const dest = iovecs_buffer[0..dest_n];
    assert(dest[0].len > 0);
    const n = io.vtable.fileReadPositional(io.userdata, r.file, dest, r.pos) catch |err| switch (err) {
        error.Unseekable => {
            r.mode = r.mode.toStreaming();
            const pos = r.pos;
            if (pos != 0) {
                r.pos = 0;
                r.seekBy(@intCast(pos)) catch {
                    r.mode = .failure;
                    return error.ReadFailed;
                };
            }
            return 0;
        },
        else => |e| {
            r.err = e;
            return error.ReadFailed;
        },
    };
    if (n == 0) {
        r.size = r.pos;
        return error.EndOfStream;
    }
    r.pos += n;
    if (n > data_size) {
        r.interface.end += n - data_size;
        return data_size;
    }
    return n;
}

fn readVecStreaming(r: *Reader, data: [][]u8) Io.Reader.Error!usize {
    const io = r.io;
    var iovecs_buffer: [max_buffers_len][]u8 = undefined;
    const dest_n, const data_size = try r.interface.writableVector(&iovecs_buffer, data);
    const dest = iovecs_buffer[0..dest_n];
    assert(dest[0].len > 0);
    const n = r.file.readStreaming(io, dest) catch |err| switch (err) {
        error.EndOfStream => {
            r.size = r.pos;
            return error.EndOfStream;
        },
        else => |e| {
            r.err = e;
            return error.ReadFailed;
        },
    };
    r.pos += n;
    if (n > data_size) {
        r.interface.end += n - data_size;
        return data_size;
    }
    return n;
}

fn discard(io_reader: *Io.Reader, limit: Io.Limit) Io.Reader.Error!usize {
    const r: *Reader = @alignCast(@fieldParentPtr("interface", io_reader));
    const io = r.io;
    const file = r.file;
    switch (r.mode) {
        .positional, .positional_simple => {
            const size = r.getSize() catch {
                r.mode = r.mode.toStreaming();
                return 0;
            };
            const logical_pos = logicalPos(r);
            const bytes_remaining = size - logical_pos;
            if (bytes_remaining == 0) return error.EndOfStream;
            const delta = @min(@intFromEnum(limit), bytes_remaining);
            setLogicalPos(r, logical_pos + delta);
            return delta;
        },
        .streaming, .streaming_simple => {
            // Unfortunately we can't seek forward without knowing the
            // size because the seek syscalls provided to us will not
            // return the true end position if a seek would exceed the
            // end.
            fallback: {
                if (r.size_err == null and r.seek_err == null) break :fallback;

                const buffered_len = r.interface.bufferedLen();
                var remaining = @intFromEnum(limit);
                if (remaining <= buffered_len) {
                    r.interface.seek += remaining;
                    return remaining;
                }
                remaining -= buffered_len;
                r.interface.seek = 0;
                r.interface.end = 0;

                var trash_buffer: [128]u8 = undefined;
                var data: [1][]u8 = .{trash_buffer[0..@min(trash_buffer.len, remaining)]};
                var iovecs_buffer: [max_buffers_len][]u8 = undefined;
                const dest_n, const data_size = try r.interface.writableVector(&iovecs_buffer, &data);
                const dest = iovecs_buffer[0..dest_n];
                assert(dest[0].len > 0);
                const n = file.readStreaming(io, dest) catch |err| switch (err) {
                    error.EndOfStream => {
                        r.size = r.pos;
                        return error.EndOfStream;
                    },
                    else => |e| {
                        r.err = e;
                        return error.ReadFailed;
                    },
                };
                r.pos += n;
                if (n > data_size) {
                    r.interface.end += n - data_size;
                    remaining -= data_size;
                } else {
                    remaining -= n;
                }
                return @intFromEnum(limit) - remaining;
            }
            const size = r.getSize() catch return 0;
            const n = @min(size - r.pos, std.math.maxInt(i64), @intFromEnum(limit));
            io.vtable.fileSeekBy(io.userdata, file, n) catch |err| {
                r.seek_err = err;
                return 0;
            };
            r.pos += n;
            return n;
        },
        .failure => return error.ReadFailed,
    }
}

/// Returns whether the stream is at the logical end.
pub fn atEnd(r: *Reader) bool {
    // Even if stat fails, size is set when end is encountered.
    const size = r.size orelse return false;
    return size - logicalPos(r) == 0;
}
