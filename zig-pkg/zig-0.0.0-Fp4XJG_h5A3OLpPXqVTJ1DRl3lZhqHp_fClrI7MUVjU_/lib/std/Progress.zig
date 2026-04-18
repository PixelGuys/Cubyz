//! This API is non-allocating, non-fallible, thread-safe, and lock-free.
const Progress = @This();

const builtin = @import("builtin");
const is_big_endian = builtin.cpu.arch.endian() == .big;
const is_windows = builtin.os.tag == .windows;

const std = @import("std");
const Io = std.Io;
const windows = std.os.windows;
const testing = std.testing;
const assert = std.debug.assert;
const posix = std.posix;
const Writer = Io.Writer;

/// Currently this API only supports this value being set to stderr, which
/// happens automatically inside `start`.
terminal: Io.File,

io: Io,

terminal_mode: TerminalMode,

update_worker: ?Io.Future(WorkerError!void),

/// Atomically set by SIGWINCH as well as the root done() function.
redraw_event: Io.Event,
need_clear: bool,
status: Status,

refresh_rate_ns: u64,
initial_delay_ns: u64,

rows: u16,
cols: u16,

/// Accessed only by the update thread.
draw_buffer: []u8,

/// This is in a separate array from `node_storage` but with the same length so
/// that it can be iterated over efficiently without trashing too much of the
/// CPU cache.
node_parents: [node_storage_buffer_len]Node.Parent,
node_storage: [node_storage_buffer_len]Node.Storage,
node_freelist_next: [node_storage_buffer_len]Node.OptionalIndex,
node_freelist: Freelist,
/// This is the number of elements in node arrays which have been used so far. Nodes before this
/// index are either active, or on the freelist. The remaining nodes are implicitly free. This
/// value may at times temporarily exceed the node count.
node_end_index: u32,

ipc_next: Ipc.SlotAtomic,
ipc: [ipc_storage_buffer_len]Ipc,
ipc_files: [ipc_storage_buffer_len]Io.File,

start_failure: StartFailure,

pub const Status = enum {
    /// Indicates the application is progressing towards completion of a task.
    /// Unless the application is interactive, this is the only status the
    /// program will ever have!
    working,
    /// The application has completed an operation, and is now waiting for user
    /// input rather than calling exit(0).
    success,
    /// The application encountered an error, and is now waiting for user input
    /// rather than calling exit(1).
    failure,
    /// The application encountered at least one error, but is still working on
    /// more tasks.
    failure_working,
};

const Freelist = packed struct(u32) {
    head: Node.OptionalIndex,
    /// Whenever `node_freelist` is added to, this generation is incremented
    /// to avoid ABA bugs when acquiring nodes. Wrapping arithmetic is used.
    generation: u24,
};

pub const Ipc = packed struct(u32) {
    /// mutex protecting `file` use, only locked by `serializeIpc`
    locked: bool,
    /// when unlocked: whether `file` is defined
    /// when locked: whether `file` does not need to be closed
    valid: bool,
    unused: @Int(.unsigned, 32 - 2 - @bitSizeOf(Generation)) = 0,
    generation: Generation,

    pub const Slot = std.math.IntFittingRange(0, ipc_storage_buffer_len - 1);
    pub const Generation = @Int(.unsigned, 32 - @bitSizeOf(Slot));

    const SlotAtomic = @Int(.unsigned, std.math.ceilPowerOfTwoAssert(usize, @min(@bitSizeOf(Slot), 8)));

    pub const Index = packed struct(u32) {
        slot: Slot,
        generation: Generation,
    };

    const Data = struct {
        state: State,
        bytes_read: u16,
        main_index: u8,
        start_index: u8,
        nodes_len: u8,

        const State = enum { unused, pending, ready };

        /// No operations have been started on this file.
        const unused: Data = .{
            .state = .unused,
            .bytes_read = 0,
            .main_index = 0,
            .start_index = 0,
            .nodes_len = 0,
        };

        fn findLastPacket(data: *const Data, buffer: *const [max_packet_len]u8) struct { u16, u16 } {
            assert(data.state == .ready);
            var packet_start: u16 = 0;
            var packet_end: u16 = 0;
            const bytes_read = data.bytes_read;
            while (bytes_read - packet_end >= 1) {
                const nodes_len: u16 = buffer[packet_end];
                const packet_len = 1 + nodes_len * (@sizeOf(Node.Storage) + @sizeOf(Node.Parent));
                if (packet_end + packet_len > bytes_read) break;
                packet_start = packet_end;
                packet_end += packet_len;
            }
            return .{ packet_start, packet_end };
        }

        fn rebase(
            data: *Data,
            buffer: *[max_packet_len]u8,
            vec: *[1][]u8,
            batch: *std.Io.Batch,
            slot: Slot,
            packet_end: u16,
        ) void {
            assert(data.state == .ready);
            const remaining = buffer[packet_end..data.bytes_read];
            @memmove(buffer[0..remaining.len], remaining);
            vec.* = .{buffer[remaining.len..]};
            batch.addAt(slot, .{ .file_read_streaming = .{
                .file = global_progress.ipc_files[slot],
                .data = vec,
            } });
            data.state = .pending;
            data.bytes_read = @intCast(remaining.len);
        }
    };
};

pub const TerminalMode = union(enum) {
    off,
    ansi_escape_codes,
    /// This is not the same as being run on windows because other terminals
    /// exist like MSYS/git-bash.
    windows_api: if (is_windows) WindowsApi else noreturn,

    pub const WindowsApi = struct {
        /// The output code page of the console.
        code_page: windows.UINT,
    };
};

pub const Options = struct {
    /// User-provided buffer with static lifetime.
    ///
    /// Used to store the entire write buffer sent to the terminal. Progress output will be truncated if it
    /// cannot fit into this buffer which will look bad but not cause any malfunctions.
    ///
    /// Must be at least 200 bytes.
    draw_buffer: []u8 = &default_draw_buffer,
    /// How many nanoseconds between writing updates to the terminal.
    refresh_rate_ns: Io.Duration = .fromMilliseconds(80),
    /// How many nanoseconds to keep the output hidden
    initial_delay_ns: Io.Duration = .fromMilliseconds(200),
    /// If provided, causes the progress item to have a denominator.
    /// 0 means unknown.
    estimated_total_items: usize = 0,
    root_name: []const u8 = "",
    disable_printing: bool = false,
};

/// Represents one unit of progress. Each node can have children nodes, or
/// one can use integers with `update`.
pub const Node = struct {
    index: OptionalIndex,

    pub const none: Node = .{ .index = .none };

    pub const max_name_len = 120;

    const Storage = extern struct {
        /// Little endian.
        completed_count: u32,
        /// 0 means unknown.
        /// Little endian.
        estimated_total_count: u32,
        name: [max_name_len]u8 align(@alignOf(usize)),

        /// Not thread-safe.
        fn getIpcIndex(s: Storage) ?Ipc.Index {
            return if (s.estimated_total_count == std.math.maxInt(u32)) @bitCast(s.completed_count) else null;
        }

        /// Thread-safe.
        fn setIpcIndex(s: *Storage, ipc_index: Ipc.Index) void {
            // `estimated_total_count` max int indicates the special state that
            // causes `completed_count` to be treated as a file descriptor, so
            // the order here matters.
            @atomicStore(u32, &s.completed_count, @bitCast(ipc_index), .monotonic);
            @atomicStore(u32, &s.estimated_total_count, std.math.maxInt(u32), .release); // synchronizes with acquire in `serialize`
        }

        /// Not thread-safe.
        fn byteSwap(s: *Storage) void {
            s.completed_count = @byteSwap(s.completed_count);
            s.estimated_total_count = @byteSwap(s.estimated_total_count);
        }

        fn copyRoot(dest: *Node.Storage, src: *align(1) const Node.Storage) void {
            dest.* = .{
                .completed_count = src.completed_count,
                .estimated_total_count = src.estimated_total_count,
                .name = if (src.name[0] == 0) dest.name else src.name,
            };
        }

        comptime {
            assert((@sizeOf(Storage) % 4) == 0);
        }
    };

    const Parent = enum(u8) {
        /// Unallocated storage.
        unused = std.math.maxInt(u8) - 1,
        /// Indicates root node.
        none = std.math.maxInt(u8),
        /// Index into `node_storage`.
        _,

        fn unwrap(i: @This()) ?Index {
            return switch (i) {
                .unused, .none => return null,
                else => @enumFromInt(@intFromEnum(i)),
            };
        }
    };

    pub const OptionalIndex = enum(u8) {
        none = std.math.maxInt(u8),
        /// Index into `node_storage`.
        _,

        pub fn unwrap(i: @This()) ?Index {
            if (i == .none) return null;
            return @enumFromInt(@intFromEnum(i));
        }

        fn toParent(i: @This()) Parent {
            assert(@intFromEnum(i) != @intFromEnum(Parent.unused));
            return @enumFromInt(@intFromEnum(i));
        }
    };

    /// Index into `node_storage`.
    pub const Index = enum(u8) {
        _,

        fn toParent(i: @This()) Parent {
            assert(@intFromEnum(i) != @intFromEnum(Parent.unused));
            assert(@intFromEnum(i) != @intFromEnum(Parent.none));
            return @enumFromInt(@intFromEnum(i));
        }

        pub fn toOptional(i: @This()) OptionalIndex {
            return @enumFromInt(@intFromEnum(i));
        }
    };

    /// Create a new child progress node. Thread-safe.
    ///
    /// Passing 0 for `estimated_total_items` means unknown.
    pub fn start(node: Node, name: []const u8, estimated_total_items: usize) Node {
        if (noop_impl) {
            assert(node.index == .none);
            return Node.none;
        }
        const node_index = node.index.unwrap() orelse return Node.none;
        const parent = node_index.toParent();

        const freelist = &global_progress.node_freelist;
        var old_freelist = @atomicLoad(Freelist, freelist, .acquire); // acquire to ensure we have the correct "next" entry
        while (old_freelist.head.unwrap()) |free_index| {
            const next_ptr = freelistNextByIndex(free_index);
            const new_freelist: Freelist = .{
                .head = @atomicLoad(Node.OptionalIndex, next_ptr, .monotonic),
                // We don't need to increment the generation when removing nodes from the free list,
                // only when adding them. (This choice is arbitrary; the opposite would also work.)
                .generation = old_freelist.generation,
            };
            old_freelist = @cmpxchgWeak(
                Freelist,
                freelist,
                old_freelist,
                new_freelist,
                .acquire, // not theoretically necessary, but not allowed to be weaker than the failure order
                .acquire, // ensure we have the correct `node_freelist_next` entry on the next iteration
            ) orelse {
                // We won the allocation race.
                return init(free_index, parent, name, estimated_total_items);
            };
        }

        const free_index = @atomicRmw(u32, &global_progress.node_end_index, .Add, 1, .monotonic);
        if (free_index >= node_storage_buffer_len) {
            // Ran out of node storage memory. Progress for this node will not be tracked.
            _ = @atomicRmw(u32, &global_progress.node_end_index, .Sub, 1, .monotonic);
            return Node.none;
        }

        return init(@enumFromInt(free_index), parent, name, estimated_total_items);
    }

    pub fn startFmt(node: Node, estimated_total_items: usize, comptime format: []const u8, args: anytype) Node {
        var buffer: [max_name_len]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, format, args) catch &buffer;
        return Node.start(node, name, estimated_total_items);
    }

    /// This is the same as calling `start` and then `end` on the returned `Node`. Thread-safe.
    pub fn completeOne(n: Node) void {
        const index = n.index.unwrap() orelse return;
        const storage = storageByIndex(index);
        _ = @atomicRmw(u32, &storage.completed_count, .Add, 1, .monotonic);
    }

    /// Thread-safe. Bytes after '0' in `new_name` are ignored.
    pub fn setName(n: Node, new_name: []const u8) void {
        const index = n.index.unwrap() orelse return;
        const storage = storageByIndex(index);

        const name_len = @min(max_name_len, std.mem.findScalar(u8, new_name, 0) orelse new_name.len);

        copyAtomicStore(storage.name[0..name_len], new_name[0..name_len]);
        if (name_len < storage.name.len)
            @atomicStore(u8, &storage.name[name_len], 0, .monotonic);
    }

    /// Gets the name of this `Node`.
    /// A pointer to this array can later be passed to `setName` to restore the name.
    pub fn getName(n: Node) [max_name_len]u8 {
        var dest: [max_name_len]u8 align(@alignOf(usize)) = undefined;
        if (n.index.unwrap()) |index| {
            copyAtomicLoad(&dest, &storageByIndex(index).name);
        }
        return dest;
    }

    /// Thread-safe.
    pub fn setCompletedItems(n: Node, completed_items: usize) void {
        const index = n.index.unwrap() orelse return;
        const storage = storageByIndex(index);
        @atomicStore(u32, &storage.completed_count, std.math.lossyCast(u32, completed_items), .monotonic);
    }

    /// Thread-safe. 0 means unknown.
    pub fn setEstimatedTotalItems(n: Node, count: usize) void {
        const index = n.index.unwrap() orelse return;
        const storage = storageByIndex(index);
        // Avoid u32 max int which is used to indicate a special state.
        const saturated_total_count = @min(std.math.maxInt(u32) - 1, count);
        @atomicStore(u32, &storage.estimated_total_count, saturated_total_count, .monotonic);
    }

    /// Thread-safe.
    pub fn increaseEstimatedTotalItems(n: Node, count: usize) void {
        const index = n.index.unwrap() orelse return;
        const storage = storageByIndex(index);
        // Avoid u32 max int which is used to indicate a special state.
        const saturated_total_count = @min(std.math.maxInt(u32) - 1, count);
        _ = @atomicRmw(u32, &storage.estimated_total_count, .Add, saturated_total_count, .monotonic);
    }

    /// Finish a started `Node`. Thread-safe.
    pub fn end(n: Node) void {
        if (noop_impl) {
            assert(n.index == .none);
            return;
        }
        const index = n.index.unwrap() orelse return;
        const io = global_progress.io;
        const parent_ptr = parentByIndex(index);
        if (@atomicLoad(Node.Parent, parent_ptr, .monotonic).unwrap()) |parent_index| {
            _ = @atomicRmw(u32, &storageByIndex(parent_index).completed_count, .Add, 1, .monotonic);
            @atomicStore(Node.Parent, parent_ptr, .unused, .monotonic);

            if (storageByIndex(index).getIpcIndex()) |ipc_index| {
                const file = global_progress.ipc_files[ipc_index.slot];
                const ipc = @atomicRmw(
                    Ipc,
                    &global_progress.ipc[ipc_index.slot],
                    .And,
                    .{ .locked = true, .valid = false, .generation = std.math.maxInt(Ipc.Generation) },
                    .release,
                );
                assert(ipc.valid and ipc.generation == ipc_index.generation);
                if (!ipc.locked) file.close(io);
            }

            const freelist = &global_progress.node_freelist;
            var old_freelist = @atomicLoad(Freelist, freelist, .monotonic);
            while (true) {
                @atomicStore(Node.OptionalIndex, freelistNextByIndex(index), old_freelist.head, .monotonic);
                old_freelist = @cmpxchgWeak(
                    Freelist,
                    freelist,
                    old_freelist,
                    .{ .head = index.toOptional(), .generation = old_freelist.generation +% 1 },
                    .release, // ensure a matching `start` sees the freelist link written above
                    .monotonic, // our write above is irrelevant if we need to retry
                ) orelse {
                    // We won the race.
                    return;
                };
            }
        } else {
            if (global_progress.update_worker) |*worker| worker.cancel(io) catch {};
            for (&global_progress.ipc, &global_progress.ipc_files) |ipc, ipc_file| {
                assert(!ipc.locked or !ipc.valid); // missing call to end()
                if (ipc.locked or ipc.valid) ipc_file.close(io);
            }
        }
    }

    /// Used by `std.process.Child`. Thread-safe.
    pub fn setIpcFile(node: Node, expected_io_userdata: ?*anyopaque, file: Io.File) void {
        const index = node.index.unwrap() orelse return;
        const io = global_progress.io;
        assert(io.userdata == expected_io_userdata);
        for (0..ipc_storage_buffer_len) |_| {
            const slot: Ipc.Slot = @truncate(
                @atomicRmw(Ipc.SlotAtomic, &global_progress.ipc_next, .Add, 1, .monotonic),
            );
            if (slot >= ipc_storage_buffer_len) continue;
            const ipc_ptr = &global_progress.ipc[slot];
            const ipc = @atomicLoad(Ipc, ipc_ptr, .monotonic);
            if (ipc.locked or ipc.valid) continue;
            const generation = ipc.generation +% 1;
            if (@cmpxchgWeak(
                Ipc,
                ipc_ptr,
                ipc,
                .{ .locked = false, .valid = true, .generation = generation },
                .acquire,
                .monotonic,
            )) |_| continue;
            global_progress.ipc_files[slot] = file;
            storageByIndex(index).setIpcIndex(.{ .slot = slot, .generation = generation });
            break;
        } else file.close(io);
    }

    pub fn setIpcIndex(node: Node, ipc_index: Ipc.Index) void {
        storageByIndex(node.index.unwrap() orelse return).setIpcIndex(ipc_index);
    }

    /// Not thread-safe.
    pub fn takeIpcIndex(node: Node) ?Ipc.Index {
        const storage = storageByIndex(node.index.unwrap() orelse return null);
        assert(storage.estimated_total_count == std.math.maxInt(u32));
        @atomicStore(u32, &storage.estimated_total_count, 0, .monotonic);
        return @bitCast(storage.completed_count);
    }

    fn storageByIndex(index: Node.Index) *Node.Storage {
        return &global_progress.node_storage[@intFromEnum(index)];
    }

    fn parentByIndex(index: Node.Index) *Node.Parent {
        return &global_progress.node_parents[@intFromEnum(index)];
    }

    fn freelistNextByIndex(index: Node.Index) *Node.OptionalIndex {
        return &global_progress.node_freelist_next[@intFromEnum(index)];
    }

    fn init(free_index: Index, parent: Parent, name: []const u8, estimated_total_items: usize) Node {
        assert(parent == .none or @intFromEnum(parent) < node_storage_buffer_len);

        const storage = storageByIndex(free_index);
        @atomicStore(u32, &storage.completed_count, 0, .monotonic);
        // Avoid u32 max int which is used to indicate a special state.
        const saturated_total_count = @min(std.math.maxInt(u32) - 1, estimated_total_items);
        @atomicStore(u32, &storage.estimated_total_count, saturated_total_count, .monotonic);
        const name_len = @min(max_name_len, name.len);
        copyAtomicStore(storage.name[0..name_len], name[0..name_len]);
        if (name_len < storage.name.len)
            @atomicStore(u8, &storage.name[name_len], 0, .monotonic);

        const parent_ptr = parentByIndex(free_index);
        if (std.debug.runtime_safety) {
            assert(@atomicLoad(Node.Parent, parent_ptr, .monotonic) == .unused);
        }
        @atomicStore(Node.Parent, parent_ptr, parent, .monotonic);

        return .{ .index = free_index.toOptional() };
    }
};

var global_progress: Progress = .{
    .io = undefined,
    .terminal = undefined,
    .terminal_mode = .off,
    .update_worker = null,
    .redraw_event = .unset,
    .refresh_rate_ns = undefined,
    .initial_delay_ns = undefined,
    .rows = 0,
    .cols = 0,
    .draw_buffer = undefined,
    .need_clear = false,
    .status = .working,

    .node_parents = undefined,
    .node_storage = undefined,
    .node_freelist_next = undefined,
    .node_freelist = .{ .head = .none, .generation = 0 },
    .node_end_index = 0,

    .ipc_next = 0,
    .ipc = undefined,
    .ipc_files = undefined,

    .start_failure = .unstarted,
};

pub const StartFailure = union(enum) {
    unstarted,
    spawn_ipc_worker: error{ConcurrencyUnavailable},
    spawn_update_worker: error{ConcurrencyUnavailable},
    parent_ipc: error{ UnsupportedOperation, UnrecognizedFormat },
};

/// One less than a power of two ensures `max_packet_len` is already a power of two.
const node_storage_buffer_len = ipc_storage_buffer_len - 1;

/// Power of two to avoid wasted `ipc_next` increments.
const ipc_storage_buffer_len = 128;

pub const max_packet_len = std.math.ceilPowerOfTwoAssert(
    usize,
    1 + node_storage_buffer_len * (@sizeOf(Node.Storage) + @sizeOf(Node.OptionalIndex)),
);

var default_draw_buffer: [4096]u8 = undefined;

var debug_start_trace = std.debug.Trace.init;

pub const have_ipc = switch (builtin.os.tag) {
    .wasi, .freestanding => false,
    else => true,
};

const noop_impl = builtin.single_threaded or switch (builtin.os.tag) {
    .wasi, .freestanding => true,
    else => false,
} or switch (builtin.zig_backend) {
    else => false,
};

pub const ParentFileError = error{
    UnsupportedOperation,
    EnvironmentVariableMissing,
    UnrecognizedFormat,
};

/// Initializes a global Progress instance.
///
/// Asserts there is only one global Progress instance.
///
/// Call `Node.end` when done.
///
/// If an error occurs, `start_failure` will be populated.
pub fn start(io: Io, options: Options) Node {
    // Ensure there is only 1 global Progress object.
    if (global_progress.node_end_index != 0) {
        debug_start_trace.dump();
        unreachable;
    }
    debug_start_trace.add("first initialized here");

    @memset(&global_progress.node_parents, .unused);
    @memset(&global_progress.ipc, .{ .locked = false, .valid = false, .generation = 0 });
    const root_node = Node.init(@enumFromInt(0), .none, options.root_name, options.estimated_total_items);
    global_progress.node_end_index = 1;

    assert(options.draw_buffer.len >= 200);
    global_progress.draw_buffer = options.draw_buffer;
    global_progress.refresh_rate_ns = @intCast(options.refresh_rate_ns.toNanoseconds());
    global_progress.initial_delay_ns = @intCast(options.initial_delay_ns.toNanoseconds());

    if (noop_impl) return .none;

    global_progress.io = io;

    if (io.vtable.progressParentFile(io.userdata)) |ipc_file| {
        global_progress.update_worker = io.concurrent(ipcThreadRun, .{ io, ipc_file }) catch |err| {
            global_progress.start_failure = .{ .spawn_ipc_worker = err };
            return .none;
        };
    } else |env_err| switch (env_err) {
        error.EnvironmentVariableMissing => {
            if (options.disable_printing) return .none;
            const stderr: Io.File = .stderr();
            global_progress.terminal = stderr;
            if (stderr.enableAnsiEscapeCodes(io)) |_| {
                global_progress.terminal_mode = .ansi_escape_codes;
            } else |_| if (is_windows) {
                var get_console_cp = windows.CONSOLE.USER_IO.GET_CP(.Output);
                // Normally, we would pass `null` to `operate` here as the kernel32
                // function does not accept a handle, however, if we pass one anyway,
                // then we will get an error if the handle is not associated with
                // this process's console, effectively combining an `isTty` check
                // into the same syscall.
                switch (get_console_cp.operate(io, stderr) catch |err| switch (err) {
                    error.Canceled => {
                        io.recancel();
                        return .none;
                    },
                }) {
                    .SUCCESS => global_progress.terminal_mode = .{ .windows_api = .{
                        .code_page = get_console_cp.Data.CodePage,
                    } },
                    .INVALID_HANDLE => {},
                    else => {},
                }
            }
            if (future: switch (global_progress.terminal_mode) {
                .off => return .none,
                .ansi_escape_codes => {
                    if (have_sigwinch) {
                        const act: posix.Sigaction = .{
                            .handler = .{ .sigaction = handleSigWinch },
                            .mask = posix.sigemptyset(),
                            .flags = (posix.SA.SIGINFO | posix.SA.RESTART),
                        };
                        posix.sigaction(.WINCH, &act, null);
                    }
                    break :future io.concurrent(updateTask, .{io});
                },
                .windows_api => io.concurrent(windowsApiUpdateTask, .{io}),
            }) |future| {
                global_progress.update_worker = future;
            } else |err| {
                global_progress.start_failure = .{ .spawn_update_worker = err };
                return .none;
            }
        },
        else => |e| {
            global_progress.start_failure = .{ .parent_ipc = e };
            return .none;
        },
    }

    return root_node;
}

pub fn setStatus(new_status: Status) void {
    if (noop_impl) return;
    @atomicStore(Status, &global_progress.status, new_status, .monotonic);
}

/// Returns whether a resize is needed to learn the terminal size.
fn wait(io: Io, timeout_ns: u64) Io.Cancelable!bool {
    const timeout: Io.Timeout = .{ .duration = .{
        .clock = .awake,
        .raw = .fromNanoseconds(timeout_ns),
    } };
    const resize_flag = if (global_progress.redraw_event.waitTimeout(io, timeout)) |_| true else |err| switch (err) {
        error.Timeout => false,
        error.Canceled => |e| return e,
    };
    global_progress.redraw_event.reset();
    return resize_flag or (global_progress.cols == 0);
}

const WorkerError = error{WindowTooSmall} || Io.ConcurrentError || Io.Cancelable ||
    Io.File.Writer.Error || Io.Operation.FileReadStreaming.Error;

fn updateTask(io: Io) WorkerError!void {
    // Store this data in the thread so that it does not need to be part of the
    // linker data of the main executable.
    var serialized_buffer: Serialized.Buffer = undefined;
    serialized_buffer.init();
    defer serialized_buffer.batch.cancel(io);

    // In this function we bypass the wrapper code inside `Io.lockStderr` /
    // `Io.tryLockStderr` in order to avoid clearing the terminal twice.
    // We still want to go through the `Io` instance however in case it uses a
    // task-switching mutex.

    try maybeUpdateSize(io, try wait(io, global_progress.initial_delay_ns));
    errdefer {
        const cancel_protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(cancel_protection);
        const stderr = io.vtable.lockStderr(io.userdata, null) catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
        defer io.unlockStderr();
        clearWrittenWithEscapeCodes(stderr.file_writer) catch {};
    }
    while (true) {
        const buffer, _ = try computeRedraw(io, &serialized_buffer);
        if (try io.vtable.tryLockStderr(io.userdata, null)) |locked_stderr| {
            defer io.unlockStderr();
            global_progress.need_clear = true;
            locked_stderr.file_writer.interface.writeAll(buffer) catch |err| switch (err) {
                error.WriteFailed => return locked_stderr.file_writer.err.?,
            };
        }

        try maybeUpdateSize(io, try wait(io, global_progress.refresh_rate_ns));
    }
}

const WindowsApiError = Io.Cancelable || Io.UnexpectedError;

fn windowsApiWriteMarker(io: Io) WindowsApiError!void {
    // Write the marker that we will use to find the beginning of the progress when clearing.
    // Note: This doesn't have to use WriteConsoleW, but doing so avoids dealing with the code page.
    const terminal = global_progress.terminal;
    var write_console = windows.CONSOLE.USER_IO.WRITE(.WideCharacter);
    const buffer = [1]windows.WCHAR{windows_api_start_marker};
    switch ((try io.operate(.{ .device_io_control = .{
        .file = terminal,
        .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
        .in = @ptrCast(&write_console.request(null, 1, .{
            .{ .Size = @sizeOf(@TypeOf(buffer)), .Pointer = &buffer },
        }, 0, .{})),
    } })).device_io_control.u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn windowsApiUpdateTask(io: Io) WorkerError!void {
    // Store this data in the thread so that it does not need to be part of the
    // linker data of the main executable.
    var serialized_buffer: Serialized.Buffer = undefined;
    serialized_buffer.init();
    defer serialized_buffer.batch.cancel(io);

    // In this function we bypass the wrapper code inside `Io.lockStderr` /
    // `Io.tryLockStderr` in order to avoid clearing the terminal twice.
    // We still want to go through the `Io` instance however in case it uses a
    // task-switching mutex.

    try maybeUpdateSize(io, try wait(io, global_progress.initial_delay_ns));
    errdefer {
        const cancel_protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(cancel_protection);
        _ = io.vtable.lockStderr(io.userdata, null) catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
        defer io.unlockStderr();
        clearWrittenWindowsApi(io) catch {};
    }
    while (true) {
        const buffer, const nl_n = try computeRedraw(io, &serialized_buffer);
        if (io.vtable.tryLockStderr(io.userdata, null) catch return) |locked_stderr| {
            defer io.unlockStderr();
            try clearWrittenWindowsApi(io);
            try windowsApiWriteMarker(io);
            global_progress.need_clear = true;
            locked_stderr.file_writer.interface.writeAll(buffer) catch |err| switch (err) {
                error.WriteFailed => return locked_stderr.file_writer.err.?,
            };
            windowsApiMoveToMarker(io, nl_n) catch return;
        }

        try maybeUpdateSize(io, try wait(io, global_progress.refresh_rate_ns));
    }
}

fn ipcThreadRun(io: Io, file: Io.File) WorkerError!void {
    // Store this data in the thread so that it does not need to be part of the
    // linker data of the main executable.
    var serialized_buffer: Serialized.Buffer = undefined;
    serialized_buffer.init();
    defer serialized_buffer.batch.cancel(io);
    var fw = file.writerStreaming(io, &.{});

    _ = try io.sleep(.fromNanoseconds(global_progress.initial_delay_ns), .awake);
    while (true) {
        writeIpc(&fw.interface, try serialize(io, &serialized_buffer)) catch |err| switch (err) {
            error.WriteFailed => return fw.err.?,
        };

        _ = try io.sleep(.fromNanoseconds(global_progress.refresh_rate_ns), .awake);
    }
}

const start_sync = "\x1b[?2026h";
const up_one_line = "\x1bM";
const clear = "\x1b[J";
const save = "\x1b7";
const restore = "\x1b8";
const finish_sync = "\x1b[?2026l";

const progress_remove = "\x1b]9;4;0\x1b\\";
const @"progress_normal {d}" = "\x1b]9;4;1;{d}\x1b\\";
const @"progress_error {d}" = "\x1b]9;4;2;{d}\x1b\\";
const progress_pulsing = "\x1b]9;4;3\x1b\\";
const progress_pulsing_error = "\x1b]9;4;2\x1b\\";
const progress_normal_100 = "\x1b]9;4;1;100\x1b\\";
const progress_error_100 = "\x1b]9;4;2;100\x1b\\";

const TreeSymbol = enum {
    /// ├─
    tee,
    /// │
    line,
    /// └─
    langle,

    const Encoding = enum {
        ansi_escapes,
        code_page_437,
        utf8,
        ascii,
    };

    /// The escape sequence representation as a string literal
    fn escapeSeq(symbol: TreeSymbol) *const [9:0]u8 {
        return switch (symbol) {
            .tee => "\x1B\x28\x30\x74\x71\x1B\x28\x42 ",
            .line => "\x1B\x28\x30\x78\x1B\x28\x42  ",
            .langle => "\x1B\x28\x30\x6d\x71\x1B\x28\x42 ",
        };
    }

    fn bytes(symbol: TreeSymbol, encoding: Encoding) []const u8 {
        return switch (encoding) {
            .ansi_escapes => escapeSeq(symbol),
            .code_page_437 => switch (symbol) {
                .tee => "\xC3\xC4 ",
                .line => "\xB3  ",
                .langle => "\xC0\xC4 ",
            },
            .utf8 => switch (symbol) {
                .tee => "├─ ",
                .line => "│  ",
                .langle => "└─ ",
            },
            .ascii => switch (symbol) {
                .tee => "|- ",
                .line => "|  ",
                .langle => "+- ",
            },
        };
    }

    fn maxByteLen(symbol: TreeSymbol) usize {
        var max: usize = 0;
        inline for (@typeInfo(Encoding).@"enum".fields) |field| {
            const len = symbol.bytes(@field(Encoding, field.name)).len;
            max = @max(max, len);
        }
        return max;
    }
};

fn appendTreeSymbol(symbol: TreeSymbol, buf: []u8, start_i: usize) usize {
    switch (global_progress.terminal_mode) {
        .off => unreachable,
        .ansi_escape_codes => {
            const bytes = symbol.escapeSeq();
            buf[start_i..][0..bytes.len].* = bytes.*;
            return start_i + bytes.len;
        },
        .windows_api => |windows_api| {
            const bytes = switch (windows_api.code_page) {
                // Code page 437 is the default code page and contains the box drawing symbols
                437 => symbol.bytes(.code_page_437),
                // UTF-8
                65001 => symbol.bytes(.utf8),
                // Fall back to ASCII approximation
                else => symbol.bytes(.ascii),
            };
            @memcpy(buf[start_i..][0..bytes.len], bytes);
            return start_i + bytes.len;
        },
    }
}

pub fn clearWrittenWithEscapeCodes(file_writer: *Io.File.Writer) Io.Writer.Error!void {
    if (noop_impl or !global_progress.need_clear) return;
    try file_writer.interface.writeAll(clear ++ progress_remove);
    global_progress.need_clear = false;
}

/// U+25BA or ►
const windows_api_start_marker = 0x25BA;

fn clearWrittenWindowsApi(io: Io) WindowsApiError!void {
    // This uses a 'marker' strategy. The idea is:
    // - Always write a marker (in this case U+25BA or ►) at the beginning of the progress
    // - Get the current cursor position (at the end of the progress)
    // - Subtract the number of lines written to get the expected start of the progress
    // - Check to see if the first character at the start of the progress is the marker
    // - If it's not the marker, keep checking the line before until we find it
    // - Clear the screen from that position down, and set the cursor position to the start
    //
    // This strategy works even if there is line wrapping, and can handle the window
    // being resized/scrolled arbitrarily.
    //
    // Notes:
    // - Ideally, the marker would be a zero-width character, but the Windows console
    //   doesn't seem to support rendering zero-width characters (they show up as a space)
    // - This same marker idea could technically be done with an attribute instead
    //   (https://learn.microsoft.com/en-us/windows/console/console-screen-buffers#character-attributes)
    //   but it must be a valid attribute and it actually needs to apply to the first
    //   character in order to be readable via ReadConsoleOutputAttribute. It doesn't seem
    //   like any of the available attributes are invisible/benign.
    if (!global_progress.need_clear) return;
    const terminal = global_progress.terminal;
    const screen_area = @as(windows.DWORD, global_progress.cols) * global_progress.rows;

    var get_console_info = windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
    switch (try get_console_info.operate(io, terminal)) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
    var fill_spaces = windows.CONSOLE.USER_IO.FILL(
        .{ .WideCharacter = ' ' },
        screen_area,
        get_console_info.Data.dwCursorPosition,
    );
    switch (try fill_spaces.operate(io, terminal)) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn windowsApiMoveToMarker(io: Io, nl_n: usize) WindowsApiError!void {
    const terminal = global_progress.terminal;
    var get_console_info = windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
    switch (try get_console_info.operate(io, terminal)) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
    const cursor_pos = get_console_info.Data.dwCursorPosition;
    const expected_y = cursor_pos.Y - @as(i16, @intCast(nl_n));
    var start_pos: windows.COORD = .{ .X = 0, .Y = expected_y };
    while (start_pos.Y >= 0) : (start_pos.Y -= 1) {
        var read_output_char = windows.CONSOLE.USER_IO.READ_OUTPUT_CHARACTER(start_pos, .WideCharacter);
        var buffer: [1]windows.WCHAR = undefined;
        switch ((try io.operate(.{ .device_io_control = .{
            .file = .{
                .handle = windows.peb().ProcessParameters.ConsoleHandle,
                .flags = .{ .nonblocking = false },
            },
            .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
            .in = @ptrCast(&read_output_char.request(terminal, 0, .{}, 1, .{
                .{ .Size = @sizeOf(@TypeOf(buffer)), .Pointer = &buffer },
            })),
        } })).device_io_control.u.Status) {
            .SUCCESS => {},
            .CANCELLED => unreachable,
            else => |status| return windows.unexpectedStatus(status),
        }
        if (read_output_char.Data.nLength >= 1 and buffer[0] == windows_api_start_marker) break;
    } else {
        // If we couldn't find the marker, then just assume that no lines wrapped
        start_pos = .{ .X = 0, .Y = expected_y };
    }
    var set_cursor_position = windows.CONSOLE.USER_IO.SET_CURSOR_POSITION(start_pos);
    switch (try set_cursor_position.operate(io, terminal)) {
        .SUCCESS => {},
        else => |status| return windows.unexpectedStatus(status),
    }
}

const Children = struct {
    child: Node.OptionalIndex,
    sibling: Node.OptionalIndex,
};

const Serialized = struct {
    parents: []Node.Parent,
    storage: []Node.Storage,

    const Buffer = struct {
        parents: [node_storage_buffer_len]Node.Parent,
        storage: [node_storage_buffer_len]Node.Storage,

        ipc_start: u8,
        ipc_end: u8,
        ipc_data: [ipc_storage_buffer_len]Ipc.Data,
        ipc_buffers: [ipc_storage_buffer_len][max_packet_len]u8,
        ipc_vecs: [ipc_storage_buffer_len][1][]u8,
        batch_storage: [ipc_storage_buffer_len]Io.Operation.Storage,
        batch: Io.Batch,

        fn init(buffer: *Buffer) void {
            buffer.ipc_start = 0;
            buffer.ipc_end = 0;
            @memset(&buffer.ipc_data, .unused);
            buffer.batch = .init(&buffer.batch_storage);
        }
    };
};

fn serialize(io: Io, serialized_buffer: *Serialized.Buffer) !Serialized {
    var prev_parents: [node_storage_buffer_len]Node.Parent = undefined;
    var prev_storage: [node_storage_buffer_len]Node.Storage = undefined;
    {
        const ipc_start = serialized_buffer.ipc_start;
        const ipc_end = serialized_buffer.ipc_end;
        @memcpy(prev_parents[ipc_start..ipc_end], serialized_buffer.parents[ipc_start..ipc_end]);
        @memcpy(prev_storage[ipc_start..ipc_end], serialized_buffer.storage[ipc_start..ipc_end]);
    }

    // Iterate all of the nodes and construct a serializable copy of the state that can be examined
    // without atomics. The `@min` call is here because `node_end_index` might briefly exceed the
    // node count sometimes.
    const end_index = @min(
        @atomicLoad(u32, &global_progress.node_end_index, .monotonic),
        node_storage_buffer_len,
    );
    var map: [node_storage_buffer_len]Node.OptionalIndex = undefined;
    var serialized_len: u8 = 0;
    var maybe_ipc_start: ?u8 = null;
    for (
        global_progress.node_parents[0..end_index],
        global_progress.node_storage[0..end_index],
        map[0..end_index],
    ) |*parent_ptr, *storage_ptr, *map_entry| {
        const parent = @atomicLoad(Node.Parent, parent_ptr, .monotonic);
        if (parent == .unused) {
            // We might read "mixed" node data in this loop, due to weird atomic things
            // or just a node actually being freed while this loop runs. That could cause
            // there to be a parent reference to a nonexistent node. Without this assignment,
            // this would lead to the map entry containing stale data. By assigning none, the
            // child node with the bad parent pointer will be harmlessly omitted from the tree.
            //
            // Note that there's no concern of potentially creating "looping" data if we read
            // "mixed" node data like this, because if a node is (directly or indirectly) its own
            // parent, it will just not be printed at all. The general idea here is that performance
            // is more important than 100% correct output every frame, given that this API is likely
            // to be used in hot paths!
            map_entry.* = .none;
            continue;
        }
        const dest_storage = &serialized_buffer.storage[serialized_len];
        copyAtomicLoad(&dest_storage.name, &storage_ptr.name);
        dest_storage.estimated_total_count = @atomicLoad(u32, &storage_ptr.estimated_total_count, .acquire); // sychronizes with release in `setIpcIndex`
        dest_storage.completed_count = @atomicLoad(u32, &storage_ptr.completed_count, .monotonic);

        serialized_buffer.parents[serialized_len] = parent;
        map_entry.* = @enumFromInt(serialized_len);
        if (maybe_ipc_start == null and dest_storage.getIpcIndex() != null) maybe_ipc_start = serialized_len;
        serialized_len += 1;
    }

    // Remap parents to point inside serialized arrays.
    for (serialized_buffer.parents[0..serialized_len]) |*parent| {
        parent.* = switch (parent.*) {
            .unused => unreachable,
            .none => .none,
            _ => |p| map[@intFromEnum(p)].toParent(),
        };
    }

    // Fill pipe buffers.
    const batch = &serialized_buffer.batch;
    batch.awaitConcurrent(io, .{
        .duration = .{ .raw = .zero, .clock = .awake },
    }) catch |err| switch (err) {
        error.Timeout => {},
        else => |e| return e,
    };
    var ready_len: u8 = 0;
    while (batch.next()) |operation| switch (operation.index) {
        0...ipc_storage_buffer_len - 1 => {
            const ipc_data = &serialized_buffer.ipc_data[operation.index];
            ipc_data.bytes_read += @intCast(
                operation.result.file_read_streaming catch |err| switch (err) {
                    error.EndOfStream => {
                        const file = global_progress.ipc_files[operation.index];
                        const ipc = @atomicRmw(
                            Ipc,
                            &global_progress.ipc[operation.index],
                            .And,
                            .{
                                .locked = false,
                                .valid = true,
                                .generation = std.math.maxInt(Ipc.Generation),
                            },
                            .release,
                        );
                        assert(ipc.locked);
                        if (!ipc.valid) file.close(io);
                        ipc_data.* = .unused;
                        continue;
                    },
                    else => |e| return e,
                },
            );
            assert(ipc_data.state == .pending);
            ipc_data.state = .ready;
            ready_len += 1;
        },
        else => unreachable,
    };

    // Find nodes which correspond to child processes.
    const ipc_start = maybe_ipc_start orelse serialized_len;
    serialized_buffer.ipc_start = ipc_start;
    for (
        serialized_buffer.parents[ipc_start..serialized_len],
        serialized_buffer.storage[ipc_start..serialized_len],
        ipc_start..,
    ) |main_parent, *main_storage, main_index| {
        if (main_parent == .unused) continue;
        const ipc_index = main_storage.getIpcIndex() orelse continue;
        const ipc = &global_progress.ipc[ipc_index.slot];
        const ipc_data = &serialized_buffer.ipc_data[ipc_index.slot];
        state: switch (ipc_data.state) {
            .unused => {
                if (@cmpxchgWeak(
                    Ipc,
                    ipc,
                    .{ .locked = false, .valid = true, .generation = ipc_index.generation },
                    .{ .locked = true, .valid = true, .generation = ipc_index.generation },
                    .acquire,
                    .monotonic,
                )) |_| continue;

                const ipc_vec = &serialized_buffer.ipc_vecs[ipc_index.slot];
                ipc_vec.* = .{&serialized_buffer.ipc_buffers[ipc_index.slot]};
                batch.addAt(ipc_index.slot, .{ .file_read_streaming = .{
                    .file = global_progress.ipc_files[ipc_index.slot],
                    .data = ipc_vec,
                } });

                ipc_data.* = .{
                    .state = .pending,
                    .bytes_read = 0,
                    .main_index = @intCast(main_index),
                    .start_index = serialized_len,
                    .nodes_len = 0,
                };
                main_storage.completed_count = 0;
                main_storage.estimated_total_count = 0;
            },
            .pending => {
                const start_index = ipc_data.start_index;
                const nodes_len = @min(ipc_data.nodes_len, node_storage_buffer_len - serialized_len);

                main_storage.copyRoot(&prev_storage[ipc_data.main_index]);
                @memcpy(
                    serialized_buffer.storage[serialized_len..][0..nodes_len],
                    prev_storage[start_index..][0..nodes_len],
                );
                for (
                    serialized_buffer.parents[serialized_len..][0..nodes_len],
                    prev_parents[serialized_len..][0..nodes_len],
                ) |*parent, prev_parent| parent.* = switch (prev_parent) {
                    .none, .unused => .none,
                    _ => if (@intFromEnum(prev_parent) == ipc_data.main_index)
                        @enumFromInt(main_index)
                    else if (@intFromEnum(prev_parent) >= start_index and
                        @intFromEnum(prev_parent) < start_index + nodes_len)
                        @enumFromInt(@intFromEnum(prev_parent) - start_index + serialized_len)
                    else
                        .none,
                };

                ipc_data.main_index = @intCast(main_index);
                ipc_data.start_index = serialized_len;
                ipc_data.nodes_len = nodes_len;
                serialized_len += nodes_len;
            },
            .ready => {
                const ipc_buffer = &serialized_buffer.ipc_buffers[ipc_index.slot];
                const packet_start, const packet_end = ipc_data.findLastPacket(ipc_buffer);
                const packet_is_empty = packet_end - packet_start <= 1;
                if (!packet_is_empty) {
                    const storage, const parents, const nodes_len = packet_contents: {
                        var packet_index: usize = packet_start;
                        const nodes_len: u16 = ipc_buffer[packet_index];
                        packet_index += 1;
                        const storage_bytes =
                            ipc_buffer[packet_index..][0 .. nodes_len * @sizeOf(Node.Storage)];
                        packet_index += storage_bytes.len;
                        const parents_bytes =
                            ipc_buffer[packet_index..][0 .. nodes_len * @sizeOf(Node.Parent)];
                        packet_index += parents_bytes.len;
                        assert(packet_index == packet_end);
                        const storage: []align(1) const Node.Storage = @ptrCast(storage_bytes);
                        const parents: []align(1) const Node.Parent = @ptrCast(parents_bytes);
                        const children_nodes_len =
                            @min(nodes_len - 1, node_storage_buffer_len - serialized_len);
                        break :packet_contents .{ storage, parents, children_nodes_len };
                    };

                    // Mount the root here.
                    main_storage.copyRoot(&storage[0]);
                    if (is_big_endian) main_storage.byteSwap();

                    // Copy the rest of the tree to the end.
                    const serialized_storage =
                        serialized_buffer.storage[serialized_len..][0..nodes_len];
                    @memcpy(serialized_storage, storage[1..][0..nodes_len]);
                    if (is_big_endian) for (serialized_storage) |*s| s.byteSwap();

                    // Patch up parent pointers taking into account how the subtree is mounted.
                    for (
                        serialized_buffer.parents[serialized_len..][0..nodes_len],
                        parents[1..][0..nodes_len],
                    ) |*parent, prev_parent| parent.* = switch (prev_parent) {
                        // Fix bad data so the rest of the code does not see `unused`.
                        .none, .unused => .none,
                        // Root node is being mounted here.
                        @as(Node.Parent, @enumFromInt(0)) => @enumFromInt(main_index),
                        // Other nodes mounted at the end.
                        // Don't trust child data; if the data is outside the expected range,
                        // ignore the data. This also handles the case when data was truncated.
                        _ => if (@intFromEnum(prev_parent) <= nodes_len)
                            @enumFromInt(@intFromEnum(prev_parent) - 1 + serialized_len)
                        else
                            .none,
                    };

                    ipc_data.main_index = @intCast(main_index);
                    ipc_data.start_index = serialized_len;
                    ipc_data.nodes_len = nodes_len;
                    serialized_len += nodes_len;
                }
                const ipc_vec = &serialized_buffer.ipc_vecs[ipc_index.slot];
                ipc_data.rebase(ipc_buffer, ipc_vec, batch, ipc_index.slot, packet_end);
                ready_len -= 1;
                if (packet_is_empty) continue :state .pending;
            },
        }
    }
    serialized_buffer.ipc_end = serialized_len;

    // Ignore data from unused pipes. This ensures that if a child process exists we will
    // eventually see `EndOfStream` and close the pipe.
    if (ready_len > 0) for (
        &serialized_buffer.ipc_data,
        &serialized_buffer.ipc_buffers,
        &serialized_buffer.ipc_vecs,
        0..,
    ) |*ipc_data, *ipc_buffer, *ipc_vec, ipc_slot| switch (ipc_data.state) {
        .unused, .pending => {},
        .ready => {
            _, const packet_end = ipc_data.findLastPacket(ipc_buffer);
            ipc_data.rebase(ipc_buffer, ipc_vec, batch, @intCast(ipc_slot), packet_end);
            ready_len -= 1;
        },
    };
    assert(ready_len == 0);

    return .{
        .parents = serialized_buffer.parents[0..serialized_len],
        .storage = serialized_buffer.storage[0..serialized_len],
    };
}

fn computeRedraw(io: Io, serialized_buffer: *Serialized.Buffer) !struct { []u8, usize } {
    if (global_progress.rows == 0 or global_progress.cols == 0) return error.WindowTooSmall;

    const serialized = try serialize(io, serialized_buffer);

    // Now we can analyze our copy of the graph without atomics, reconstructing
    // children lists which do not exist in the canonical data. These are
    // needed for tree traversal below.

    var children_buffer: [node_storage_buffer_len]Children = undefined;
    const children = children_buffer[0..serialized.parents.len];

    @memset(children, .{ .child = .none, .sibling = .none });

    for (serialized.parents, 0..) |parent, child_index_usize| {
        const child_index: Node.Index = @enumFromInt(child_index_usize);
        assert(parent != .unused);
        const parent_index = parent.unwrap() orelse continue;
        const children_node = &children[@intFromEnum(parent_index)];
        if (children_node.child.unwrap()) |existing_child_index| {
            const existing_child = &children[@intFromEnum(existing_child_index)];
            children[@intFromEnum(child_index)].sibling = existing_child.sibling;
            existing_child.sibling = child_index.toOptional();
        } else {
            children_node.child = child_index.toOptional();
        }
    }

    // The strategy is, with every redraw:
    // erase to end of screen, write, move cursor to beginning of line, move cursor up N lines
    // This keeps the cursor at the beginning so that unlocked stderr writes
    // don't get eaten by the clear.

    var i: usize = 0;
    const buf = global_progress.draw_buffer;

    if (global_progress.terminal_mode == .ansi_escape_codes) {
        buf[i..][0..start_sync.len].* = start_sync.*;
        i += start_sync.len;
    }

    switch (global_progress.terminal_mode) {
        .off => unreachable,
        .ansi_escape_codes => {
            buf[i..][0..clear.len].* = clear.*;
            i += clear.len;
        },
        .windows_api => {},
    }

    const root_node_index: Node.Index = @enumFromInt(0);
    i, const nl_n = computeNode(buf, i, 0, serialized, children, root_node_index);

    if (global_progress.terminal_mode == .ansi_escape_codes) {
        {
            // Set progress state https://conemu.github.io/en/AnsiEscapeCodes.html#ConEmu_specific_OSC
            const root_storage = &serialized.storage[0];
            const storage = if (root_storage.name[0] != 0 or children[0].child == .none) root_storage else &serialized.storage[@intFromEnum(children[0].child)];
            const estimated_total = storage.estimated_total_count;
            const completed_items = storage.completed_count;
            const status = @atomicLoad(Status, &global_progress.status, .monotonic);
            switch (status) {
                .working => {
                    if (estimated_total == 0) {
                        buf[i..][0..progress_pulsing.len].* = progress_pulsing.*;
                        i += progress_pulsing.len;
                    } else {
                        const percent = completed_items * 100 / estimated_total;
                        if (std.fmt.bufPrint(buf[i..], @"progress_normal {d}", .{percent})) |b| {
                            i += b.len;
                        } else |_| {}
                    }
                },
                .success => {
                    buf[i..][0..progress_remove.len].* = progress_remove.*;
                    i += progress_remove.len;
                },
                .failure => {
                    buf[i..][0..progress_error_100.len].* = progress_error_100.*;
                    i += progress_error_100.len;
                },
                .failure_working => {
                    if (estimated_total == 0) {
                        buf[i..][0..progress_pulsing_error.len].* = progress_pulsing_error.*;
                        i += progress_pulsing_error.len;
                    } else {
                        const percent = completed_items * 100 / estimated_total;
                        if (std.fmt.bufPrint(buf[i..], @"progress_error {d}", .{percent})) |b| {
                            i += b.len;
                        } else |_| {}
                    }
                },
            }
        }

        if (nl_n > 0) {
            buf[i] = '\r';
            i += 1;
            for (0..nl_n) |_| {
                buf[i..][0..up_one_line.len].* = up_one_line.*;
                i += up_one_line.len;
            }
        }

        buf[i..][0..finish_sync.len].* = finish_sync.*;
        i += finish_sync.len;
    }

    return .{ buf[0..i], nl_n };
}

fn computePrefix(
    buf: []u8,
    start_i: usize,
    nl_n: usize,
    serialized: Serialized,
    children: []const Children,
    node_index: Node.Index,
) usize {
    var i = start_i;
    const parent_index = serialized.parents[@intFromEnum(node_index)].unwrap() orelse return i;
    if (serialized.parents[@intFromEnum(parent_index)] == .none) return i;
    if (@intFromEnum(serialized.parents[@intFromEnum(parent_index)]) == 0 and
        serialized.storage[0].name[0] == 0)
    {
        return i;
    }
    i = computePrefix(buf, i, nl_n, serialized, children, parent_index);
    if (children[@intFromEnum(parent_index)].sibling == .none) {
        const prefix = "   ";
        const upper_bound_len = prefix.len + lineUpperBoundLen(nl_n);
        if (i + upper_bound_len > buf.len) return buf.len;
        buf[i..][0..prefix.len].* = prefix.*;
        i += prefix.len;
    } else {
        const upper_bound_len = TreeSymbol.line.maxByteLen() + lineUpperBoundLen(nl_n);
        if (i + upper_bound_len > buf.len) return buf.len;
        i = appendTreeSymbol(.line, buf, i);
    }
    return i;
}

fn lineUpperBoundLen(nl_n: usize) usize {
    // \r\n on Windows, \n otherwise.
    const nl_len = if (is_windows) 2 else 1;
    return @max(TreeSymbol.tee.maxByteLen(), TreeSymbol.langle.maxByteLen()) +
        "[4294967296/4294967296] ".len + Node.max_name_len + nl_len +
        (1 + (nl_n + 1) * up_one_line.len) +
        finish_sync.len;
}

fn computeNode(
    buf: []u8,
    start_i: usize,
    start_nl_n: usize,
    serialized: Serialized,
    children: []const Children,
    node_index: Node.Index,
) struct { usize, usize } {
    var i = start_i;
    var nl_n = start_nl_n;

    i = computePrefix(buf, i, nl_n, serialized, children, node_index);

    if (i + lineUpperBoundLen(nl_n) > buf.len)
        return .{ start_i, start_nl_n };

    const storage = &serialized.storage[@intFromEnum(node_index)];
    const estimated_total = storage.estimated_total_count;
    const completed_items = storage.completed_count;
    const name = if (std.mem.findScalar(u8, &storage.name, 0)) |end| storage.name[0..end] else &storage.name;
    const parent = serialized.parents[@intFromEnum(node_index)];

    if (parent != .none) p: {
        if (@intFromEnum(parent) == 0 and serialized.storage[0].name[0] == 0) {
            break :p;
        }
        if (children[@intFromEnum(node_index)].sibling == .none) {
            i = appendTreeSymbol(.langle, buf, i);
        } else {
            i = appendTreeSymbol(.tee, buf, i);
        }
    }

    const is_empty_root = @intFromEnum(node_index) == 0 and serialized.storage[0].name[0] == 0;
    if (!is_empty_root) {
        if (name.len != 0 or estimated_total > 0) {
            if (estimated_total > 0) {
                if (std.fmt.bufPrint(buf[i..], "[{d}/{d}] ", .{ completed_items, estimated_total })) |b| {
                    i += b.len;
                } else |_| {}
            } else if (completed_items != 0) {
                if (std.fmt.bufPrint(buf[i..], "[{d}] ", .{completed_items})) |b| {
                    i += b.len;
                } else |_| {}
            }
            if (name.len != 0) {
                if (std.fmt.bufPrint(buf[i..], "{s}", .{name})) |b| {
                    i += b.len;
                } else |_| {}
            }
        }

        i = @min(global_progress.cols + start_i, i);
        if (is_windows) {
            // \r\n on Windows is necessary for the old console with the
            // ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN
            // console modes set to behave properly.
            buf[i] = '\r';
            i += 1;
        }
        buf[i] = '\n';
        i += 1;
        nl_n += 1;
    }

    if (global_progress.withinRowLimit(nl_n)) {
        if (children[@intFromEnum(node_index)].child.unwrap()) |child| {
            i, nl_n = computeNode(buf, i, nl_n, serialized, children, child);
        }
    }

    if (global_progress.withinRowLimit(nl_n)) {
        if (children[@intFromEnum(node_index)].sibling.unwrap()) |sibling| {
            i, nl_n = computeNode(buf, i, nl_n, serialized, children, sibling);
        }
    }

    return .{ i, nl_n };
}

fn withinRowLimit(p: *Progress, nl_n: usize) bool {
    // The +2 here is so that the PS1 is not scrolled off the top of the terminal.
    // one because we keep the cursor on the next line
    // one more to account for the PS1
    return nl_n + 2 < p.rows;
}

fn writeIpc(writer: *Io.Writer, serialized: Serialized) Io.Writer.Error!void {
    // Byteswap if necessary to ensure little endian over the pipe. This is
    // needed because the parent or child process might be running in qemu.
    if (is_big_endian) for (serialized.storage) |*s| s.byteSwap();

    assert(serialized.parents.len == serialized.storage.len);
    const serialized_len: u8 = @intCast(serialized.parents.len);
    const header = std.mem.asBytes(&serialized_len);
    const storage = std.mem.sliceAsBytes(serialized.storage);
    const parents = std.mem.sliceAsBytes(serialized.parents);

    var vec = [3][]const u8{ header, storage, parents };
    try writer.writeVecAll(&vec);
}

fn maybeUpdateSize(io: Io, resize_flag: bool) !void {
    if (!resize_flag) return;

    const file = global_progress.terminal;

    if (is_windows) {
        var get_console_info = windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
        switch (try get_console_info.operate(io, file)) {
            .SUCCESS => {
                global_progress.rows = @intCast(get_console_info.Data.dwWindowSize.Y);
                global_progress.cols = @intCast(get_console_info.Data.dwWindowSize.X);
            },
            else => {
                std.log.debug("failed to determine terminal size; using conservative guess 80x25", .{});
                global_progress.rows = 25;
                global_progress.cols = 80;
            },
        }
    } else {
        var winsize: posix.winsize = .{
            .row = 0,
            .col = 0,
            .xpixel = 0,
            .ypixel = 0,
        };

        const err = (try io.operate(.{ .device_io_control = .{
            .file = file,
            .code = posix.T.IOCGWINSZ,
            .arg = &winsize,
        } })).device_io_control;

        if (err >= 0) {
            global_progress.rows = winsize.row;
            global_progress.cols = winsize.col;
        } else {
            std.log.debug("failed to determine terminal size; using conservative guess 80x25", .{});
            global_progress.rows = 25;
            global_progress.cols = 80;
        }
    }
}

fn handleSigWinch(sig: posix.SIG, info: *const posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.c) void {
    _ = info;
    _ = ctx_ptr;
    assert(sig == .WINCH);
    global_progress.redraw_event.set(global_progress.io);
}

const have_sigwinch = switch (builtin.os.tag) {
    .linux,
    .plan9,
    .illumos,
    .netbsd,
    .openbsd,
    .haiku,
    .driverkit,
    .ios,
    .maccatalyst,
    .macos,
    .tvos,
    .visionos,
    .watchos,
    .dragonfly,
    .freebsd,
    .serenity,
    => true,

    else => false,
};

fn copyAtomicStore(dest: []align(@alignOf(usize)) u8, src: []const u8) void {
    assert(dest.len == src.len);
    const chunked_len = dest.len / @sizeOf(usize);
    const dest_chunked: []usize = @as([*]usize, @ptrCast(dest))[0..chunked_len];
    const src_chunked: []align(1) const usize = @as([*]align(1) const usize, @ptrCast(src))[0..chunked_len];
    for (dest_chunked, src_chunked) |*d, s| {
        @atomicStore(usize, d, s, .monotonic);
    }
    const remainder_start = chunked_len * @sizeOf(usize);
    for (dest[remainder_start..], src[remainder_start..]) |*d, s| {
        @atomicStore(u8, d, s, .monotonic);
    }
}

fn copyAtomicLoad(
    dest: *align(@alignOf(usize)) [Node.max_name_len]u8,
    src: *align(@alignOf(usize)) const [Node.max_name_len]u8,
) void {
    const chunked_len = @divExact(dest.len, @sizeOf(usize));
    const dest_chunked: *[chunked_len]usize = @ptrCast(dest);
    const src_chunked: *const [chunked_len]usize = @ptrCast(src);
    for (dest_chunked, src_chunked) |*d, *s| {
        d.* = @atomicLoad(usize, s, .monotonic);
    }
}
