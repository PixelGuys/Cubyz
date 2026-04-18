const MultiReader = @This();

const std = @import("../../std.zig");
const Io = std.Io;
const File = Io.File;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

gpa: Allocator,
streams: *Streams,
batch: Io.Batch,

pub const Context = struct {
    mr: *MultiReader,
    fr: File.Reader,
    vec: [1][]u8,
    err: ?Error,
};

pub const Error = UnendingError || error{EndOfStream};
pub const UnendingError = Allocator.Error || File.Reader.Error || Io.ConcurrentError;

/// Trailing:
/// * `contexts: [len]Context`
/// * `storage: [len]Io.Operation.Storage`
pub const Streams = extern struct {
    len: u32,

    pub fn contexts(s: *Streams) []Context {
        const base: usize = @intFromPtr(s);
        const ptr: [*]Context = @ptrFromInt(std.mem.alignForward(usize, base + @sizeOf(Streams), @alignOf(Context)));
        return ptr[0..s.len];
    }

    pub fn storage(s: *Streams) []Io.Operation.Storage {
        const prev = contexts(s);
        const end = prev.ptr + prev.len;
        const ptr: [*]Io.Operation.Storage = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(end), @alignOf(Io.Operation.Storage)));
        return ptr[0..s.len];
    }
};

pub fn Buffer(comptime n: usize) type {
    return extern struct {
        len: u32,
        contexts: [n][@sizeOf(Context)]u8 align(@alignOf(Context)),
        storage: [n][@sizeOf(Io.Operation.Storage)]u8 align(@alignOf(Io.Operation.Storage)),

        pub fn toStreams(b: *@This()) *Streams {
            b.len = n;
            return @ptrCast(b);
        }
    };
}

/// See `Streams.Buffer` for convenience API to obtain the `streams` parameter.
pub fn init(mr: *MultiReader, gpa: Allocator, io: Io, streams: *Streams, files: []const File) void {
    const contexts = streams.contexts();
    for (contexts, files) |*context, file| context.* = .{
        .mr = mr,
        .fr = .{
            .io = io,
            .file = file,
            .mode = .streaming,
            .interface = .{
                .vtable = &.{
                    .stream = stream,
                    .discard = discard,
                    .readVec = readVec,
                    .rebase = rebase,
                },
                .buffer = &.{},
                .seek = 0,
                .end = 0,
            },
        },
        .vec = .{&.{}},
        .err = null,
    };
    mr.* = .{
        .gpa = gpa,
        .streams = streams,
        .batch = .init(streams.storage()),
    };
    for (contexts, 0..) |*context, i| {
        const r = &context.fr.interface;
        rebaseGrowing(mr, context, 1) catch |err| {
            context.err = err;
            continue;
        };
        context.vec[0] = r.buffer;
        mr.batch.addAt(@intCast(i), .{ .file_read_streaming = .{
            .file = context.fr.file,
            .data = &context.vec,
        } });
    }
}

pub fn deinit(mr: *MultiReader) void {
    const gpa = mr.gpa;
    const contexts = mr.streams.contexts();
    const io = contexts[0].fr.io;
    mr.batch.cancel(io);
    for (contexts) |*context| {
        gpa.free(context.fr.interface.buffer);
    }
}

pub fn fileReader(mr: *MultiReader, index: usize) *File.Reader {
    return &mr.streams.contexts()[index].fr;
}

pub fn reader(mr: *MultiReader, index: usize) *Io.Reader {
    return &mr.streams.contexts()[index].fr.interface;
}

/// Checks for errors in all streams, prioritizing `error.Canceled` if it
/// occurred anywhere, and ignoring `error.EndOfStream`.
pub fn checkAnyError(mr: *const MultiReader) UnendingError!void {
    const contexts = mr.streams.contexts();
    var other: UnendingError!void = {};
    for (contexts) |*context| {
        if (context.err) |err| switch (err) {
            error.Canceled => |e| return e,
            error.EndOfStream => continue,
            else => |e| other = e,
        };
    }
    return other;
}

pub fn toOwnedSlice(mr: *MultiReader, index: usize) Allocator.Error![]u8 {
    const gpa = mr.gpa;
    const r: *Io.Reader = reader(mr, index);
    if (r.seek == 0) {
        const new = try gpa.realloc(r.buffer, r.end);
        r.buffer = &.{};
        r.end = 0;
        return new;
    }
    const new = try gpa.dupe(u8, r.buffered());
    gpa.free(r.buffer);
    r.buffer = &.{};
    r.seek = 0;
    r.end = 0;
    return new;
}

fn stream(r: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
    _ = limit;
    _ = w;
    const fr: *File.Reader = @alignCast(@fieldParentPtr("interface", r));
    const context: *Context = @fieldParentPtr("fr", fr);
    try fillUntimed(context, 1);
    return 0;
}

fn discard(r: *Io.Reader, limit: Io.Limit) Io.Reader.Error!usize {
    _ = limit;
    const fr: *File.Reader = @alignCast(@fieldParentPtr("interface", r));
    const context: *Context = @fieldParentPtr("fr", fr);
    try fillUntimed(context, 1);
    return 0;
}

fn readVec(r: *Io.Reader, data: [][]u8) Io.Reader.Error!usize {
    _ = data;
    const fr: *File.Reader = @alignCast(@fieldParentPtr("interface", r));
    const context: *Context = @fieldParentPtr("fr", fr);
    try fillUntimed(context, 1);
    return 0;
}

fn rebase(r: *Io.Reader, capacity: usize) Io.Reader.RebaseError!void {
    const fr: *File.Reader = @alignCast(@fieldParentPtr("interface", r));
    const context: *Context = @fieldParentPtr("fr", fr);
    try fillUntimed(context, capacity);
}

fn fillUntimed(context: *Context, capacity: usize) Io.Reader.Error!void {
    fill(context.mr, capacity, .none) catch |err| switch (err) {
        error.Timeout => unreachable,
        error.Canceled, error.ConcurrencyUnavailable => |e| {
            context.err = e;
            return error.ReadFailed;
        },
        error.EndOfStream => |e| return e,
    };
    if (context.err) |err| switch (err) {
        error.EndOfStream => |e| return e,
        else => return error.ReadFailed,
    };
}

pub const FillError = Io.Batch.AwaitConcurrentError || error{
    /// `fill` was called when all streams already have failed or reached the
    /// end.
    EndOfStream,
};

/// Wait until at least one stream receives more data.
pub fn fill(mr: *MultiReader, unused_capacity: usize, timeout: Io.Timeout) FillError!void {
    const contexts = mr.streams.contexts();
    const io = contexts[0].fr.io;
    var any_completed = false;

    try mr.batch.awaitConcurrent(io, timeout);

    while (mr.batch.next()) |operation| {
        any_completed = true;
        const context = &contexts[operation.index];
        const n = operation.result.file_read_streaming catch |err| {
            context.err = err;
            continue;
        };
        const r = &context.fr.interface;
        r.end += n;
        if (r.buffer.len - r.end < unused_capacity) {
            rebaseGrowing(mr, context, r.bufferedLen() + unused_capacity) catch |err| {
                context.err = err;
                continue;
            };
            assert(r.seek == 0);
        }
        context.vec[0] = r.buffer[r.end..];
        mr.batch.addAt(operation.index, .{ .file_read_streaming = .{
            .file = context.fr.file,
            .data = &context.vec,
        } });
    }

    if (!any_completed) return error.EndOfStream;
}

/// Wait until all streams fail or reach the end.
pub fn fillRemaining(mr: *MultiReader, timeout: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
    while (fill(mr, 1, timeout)) |_| {} else |err| switch (err) {
        error.EndOfStream => return,
        else => |e| return e,
    }
}

fn rebaseGrowing(mr: *MultiReader, context: *Context, capacity: usize) Allocator.Error!void {
    const gpa = mr.gpa;
    const r = &context.fr.interface;
    if (r.buffer.len >= capacity) {
        const data = r.buffer[r.seek..r.end];
        @memmove(r.buffer[0..data.len], data);
        r.seek = 0;
        r.end = data.len;
    } else {
        const adjusted_capacity = std.ArrayList(u8).growCapacity(capacity);

        if (r.seek == 0) {
            if (gpa.remap(r.buffer, adjusted_capacity)) |new_memory| {
                r.buffer = new_memory;
                return;
            }
        }

        const data = r.buffer[r.seek..r.end];
        const new = try gpa.alloc(u8, adjusted_capacity);
        @memcpy(new[0..data.len], data);
        gpa.free(r.buffer);
        r.buffer = new;
        r.seek = 0;
        r.end = data.len;
    }
}
