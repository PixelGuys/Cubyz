const addressFromPosix = Io.Threaded.addressFromPosix;
const addressToPosix = Io.Threaded.addressToPosix;
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const Argv0 = Io.Threaded.Argv0;
const assert = std.debug.assert;
const builtin = @import("builtin");
const ChdirError = Io.Threaded.ChdirError;
const clockToPosix = Io.Threaded.clockToPosix;
const Csprng = Io.Threaded.Csprng;
const default_PATH = Io.Threaded.default_PATH;
const Dir = Io.Dir;
const Environ = Io.Threaded.Environ;
const errnoBug = Io.Threaded.errnoBug;
const Evented = @This();
const fallbackSeed = Io.Threaded.fallbackSeed;
const fd_t = linux.fd_t;
const File = Io.File;
const Io = std.Io;
const IoUring = linux.IoUring;
const iovec = std.posix.iovec;
const iovec_const = std.posix.iovec_const;
const linux = std.os.linux;
const linux_statx_request = Io.Threaded.linux_statx_request;
const LOCK = std.posix.LOCK;
const log = std.log.scoped(.@"io-uring");
const max_iovecs_len = Io.Threaded.max_iovecs_len;
const nanosecondsFromPosix = Io.Threaded.nanosecondsFromPosix;
const net = Io.net;
const PATH_MAX = linux.PATH_MAX;
const pathToPosix = Io.Threaded.pathToPosix;
const pid_t = linux.pid_t;
const PosixAddress = Io.Threaded.PosixAddress;
const posixAddressFamily = Io.Threaded.posixAddressFamily;
const posixSocketModeProtocol = Io.Threaded.posixSocketModeProtocol;
const process = std.process;
const recoverableOsBugDetected = Io.Threaded.recoverableOsBugDetected;
const setTimestampToPosix = Io.Threaded.setTimestampToPosix;
const splat_buffer_size = Io.Threaded.splat_buffer_size;
const statFromLinux = Io.Threaded.statFromLinux;
const statxKind = Io.Threaded.statxKind;
const std = @import("../std.zig");
const timestampFromPosix = Io.Threaded.timestampFromPosix;
const unexpectedErrno = std.posix.unexpectedErrno;
const winsize = std.posix.winsize;

const tracy = if (@hasDecl(@import("root"), "tracy")) @import("root").tracy else struct {
    const enable = false;
    inline fn fiberEnter(fiber: [*:0]const u8) void {
        _ = fiber;
    }
    inline fn fiberLeave() void {}
};

/// Empirically saw >128KB being used by the self-hosted backend to panic.
/// Empirically saw glibc complain about 256KB.
const idle_stack_size = 512 * 1024;

const max_idle_search = 1;
const max_steal_ready_search = 2;
const max_steal_free_search = 4;

backing_allocator_needs_mutex: bool,
backing_allocator_mutex: Io.Mutex,
/// Does not need to be thread-safe if not used elsewhere.
backing_allocator: Allocator,
main_fiber_buffer: [
    std.mem.alignForward(usize, @sizeOf(Fiber), @alignOf(Completion)) + @sizeOf(Completion)
]u8 align(@max(@alignOf(Fiber), @alignOf(Completion))),
log2_ring_entries: u4,
threads: Thread.List,
sync_limit: ?Io.Semaphore,

stderr_writer_initialized: bool = false,
stderr_mutex: Io.Mutex,
stderr_writer: File.Writer = .{
    .io = undefined,
    .interface = Io.File.Writer.initInterface(&.{}),
    .file = .stderr(),
    .mode = .streaming,
},
stderr_mode: Io.Terminal.Mode = .no_color,

environ_mutex: Io.Mutex,
environ_initialized: bool,
environ: Environ,

null_fd: CachedFd,
random_fd: CachedFd,

csprng_mutex: Io.Mutex,
csprng: Csprng,

const Thread = struct {
    required_align: void align(4),
    thread: std.Thread,
    idle_context: Io.fiber.Context,
    current_context: *Io.fiber.Context,
    ready_queue: ?*Fiber,
    free_queue: ?*Fiber,
    io_uring: IoUring,
    idle_search_index: u32,
    steal_ready_search_index: u32,
    steal_free_search_index: u32,
    name_arena: if (tracy.enable) std.heap.ArenaAllocator.State else struct {},
    csprng: Csprng,

    threadlocal var self: ?*Thread = null;

    noinline fn current() *Thread {
        return self.?;
    }

    fn deinit(thread: *Thread, gpa: Allocator) void {
        var next_fiber = thread.free_queue;
        while (next_fiber) |free_fiber| {
            next_fiber = free_fiber.status.free_next;
            gpa.free(free_fiber.allocatedSlice());
        }
        thread.io_uring.deinit();
    }

    fn currentFiber(thread: *Thread) *Fiber {
        assert(thread.current_context != &thread.idle_context);
        return @fieldParentPtr("context", thread.current_context);
    }

    fn enqueue(thread: *Thread) *linux.io_uring_sqe {
        while (true) return thread.io_uring.get_sqe() catch {
            thread.submit();
            continue;
        };
    }

    fn submit(thread: *Thread) void {
        _ = thread.io_uring.submit() catch |err| switch (err) {
            error.SignalInterrupt => {},
            else => |e| @panic(@errorName(e)),
        };
    }

    const List = struct {
        allocated: []Thread,
        reserved: u32,
        active: u32,
    };
};

const Fiber = struct {
    required_align: void align(4),
    context: Io.fiber.Context,
    link: union {
        awaiter: ?*Fiber,
        group: struct { prev: ?*Fiber, next: ?*Fiber },
    },
    status: union(enum) {
        queue_next: ?*Fiber,
        awaiting_group: Group,
        free_next: ?*Fiber,
    },
    cancel_status: CancelStatus,
    cancel_protection: CancelProtection,
    name: if (tracy.enable) [*:0]const u8 else void,

    var next_name: u64 = 0;

    const CancelStatus = packed struct(u32) {
        requested: bool,
        awaiting: Awaiting,

        const unrequested: CancelStatus = .{ .requested = false, .awaiting = .nothing };

        const Awaiting = enum(u31) {
            nothing = std.math.maxInt(u31),
            group = std.math.maxInt(u31) - 1,
            /// An io_uring fd.
            _,

            fn subWrap(lhs: Awaiting, rhs: Awaiting) Awaiting {
                return @enumFromInt(@intFromEnum(lhs) -% @intFromEnum(rhs));
            }

            fn fromIoUringFd(fd: fd_t) Awaiting {
                const awaiting: Awaiting = @enumFromInt(fd);
                switch (awaiting) {
                    .nothing, .group => unreachable,
                    _ => return awaiting,
                }
            }

            fn toIoUringFd(awaiting: Awaiting) fd_t {
                switch (awaiting) {
                    .nothing, .group => unreachable,
                    _ => return @intFromEnum(awaiting),
                }
            }
        };

        fn changeAwaiting(
            cancel_status: *CancelStatus,
            old_awaiting: Awaiting,
            new_awaiting: Awaiting,
        ) bool {
            const old_cancel_status = @atomicRmw(CancelStatus, cancel_status, .Add, .{
                .requested = false,
                .awaiting = new_awaiting.subWrap(old_awaiting),
            }, .monotonic);
            assert(old_cancel_status.awaiting == old_awaiting);
            return old_cancel_status.requested;
        }
    };

    const CancelProtection = packed struct {
        user: Io.CancelProtection,
        acknowledged: bool,

        const unblocked: CancelProtection = .{ .user = .unblocked, .acknowledged = false };

        fn check(cancel_protection: CancelProtection) Io.CancelProtection {
            return @enumFromInt(@intFromBool(cancel_protection != unblocked));
        }

        fn acknowledge(cancel_protection: *CancelProtection) void {
            assert(!cancel_protection.acknowledged);
            cancel_protection.acknowledged = true;
        }

        fn recancel(cancel_protection: *CancelProtection) void {
            assert(cancel_protection.acknowledged);
            cancel_protection.acknowledged = false;
        }

        test check {
            try std.testing.expectEqual(Io.CancelProtection.unblocked, check(.unblocked));
            try std.testing.expectEqual(Io.CancelProtection.blocked, check(.{
                .user = .unblocked,
                .acknowledged = true,
            }));
            try std.testing.expectEqual(Io.CancelProtection.blocked, check(.{
                .user = .blocked,
                .acknowledged = false,
            }));
            try std.testing.expectEqual(Io.CancelProtection.blocked, check(.{
                .user = .blocked,
                .acknowledged = true,
            }));
        }
    };

    const finished: ?*Fiber = @ptrFromInt(@alignOf(Fiber));

    const max_result_align: Alignment = .@"16";
    const max_result_size = max_result_align.forward(512);
    /// This includes any stack realignments that need to happen, and also the
    /// initial frame return address slot and argument frame, depending on target.
    const min_stack_size = 60 * 1024 * 1024;
    const max_context_align: Alignment = .@"16";
    const max_context_size = max_context_align.forward(1024);
    const max_closure_size: usize = @sizeOf(AsyncClosure);
    const max_closure_align: Alignment = .of(AsyncClosure);
    const allocation_size = std.mem.alignForward(
        usize,
        max_closure_align.max(max_context_align).forward(
            max_result_align.forward(@sizeOf(Fiber)) + max_result_size + min_stack_size,
        ) + max_closure_size + max_context_size,
        std.heap.page_size_max,
    );
    comptime {
        assert(max_result_align.compare(.gte, .of(Completion)));
        assert(max_result_size >= @sizeOf(Completion));
    }

    fn create(ev: *Evented) error{OutOfMemory}!*Fiber {
        const thread: *Thread = .current();
        if (@atomicRmw(?*Fiber, &thread.free_queue, .Xchg, finished, .acquire)) |free_fiber| {
            assert(free_fiber != finished);
            @atomicStore(?*Fiber, &thread.free_queue, free_fiber.status.free_next, .release);
            return free_fiber;
        }
        const active_threads = @atomicLoad(u32, &ev.threads.active, .acquire);
        for (0..@min(max_steal_free_search, active_threads)) |_| {
            defer thread.steal_free_search_index += 1;
            if (thread.steal_free_search_index == active_threads) thread.steal_free_search_index = 0;
            const steal_free_search_thread =
                &ev.threads.allocated[0..active_threads][thread.steal_free_search_index];
            if (steal_free_search_thread == thread) continue;
            const free_fiber =
                @atomicLoad(?*Fiber, &steal_free_search_thread.free_queue, .monotonic) orelse continue;
            if (free_fiber == finished) continue;
            if (@cmpxchgWeak(
                ?*Fiber,
                &steal_free_search_thread.free_queue,
                free_fiber,
                null,
                .acquire,
                .monotonic,
            )) |_| continue;
            @atomicStore(?*Fiber, &thread.free_queue, free_fiber.status.free_next, .release);
            return free_fiber;
        }
        @atomicStore(?*Fiber, &thread.free_queue, null, .monotonic);
        return @ptrCast(try ev.allocator().alignedAlloc(u8, .of(Fiber), allocation_size));
    }

    fn destroy(fiber: *Fiber) void {
        const thread: *Thread = .current();
        assert(fiber.status.queue_next == null);
        fiber.status = .{ .free_next = @atomicLoad(?*Fiber, &thread.free_queue, .acquire) };
        while (true) fiber.status.free_next = @cmpxchgWeak(
            ?*Fiber,
            &thread.free_queue,
            fiber.status.free_next,
            fiber,
            .acq_rel,
            .acquire,
        ) orelse break;
    }

    fn allocatedSlice(f: *Fiber) []align(@alignOf(Fiber)) u8 {
        return @as([*]align(@alignOf(Fiber)) u8, @ptrCast(f))[0..allocation_size];
    }

    fn allocatedEnd(f: *Fiber) [*]u8 {
        const allocated_slice = f.allocatedSlice();
        return allocated_slice[allocated_slice.len..].ptr;
    }

    fn resultPointer(f: *Fiber, comptime Result: type) *Result {
        return @ptrCast(@alignCast(f.resultBytes(.of(Result))));
    }

    fn resultBytes(f: *Fiber, alignment: Alignment) [*]u8 {
        return @ptrFromInt(alignment.forward(@intFromPtr(f) + @sizeOf(Fiber)));
    }

    const Queue = struct { head: *Fiber, tail: *Fiber };

    /// Like a `*Fiber`, but 2 bits smaller than a pointer (because the LSBs are always 0 due to
    /// alignment) so that those two bits can be used in a `packed struct`.
    const PackedPtr = enum(@Int(.unsigned, @bitSizeOf(usize) - 2)) {
        null = 0,
        all_ones = std.math.maxInt(@Int(.unsigned, @bitSizeOf(usize) - 2)),
        _,

        const Split = packed struct(usize) { low: u2, high: PackedPtr };
        fn pack(ptr: ?*Fiber) PackedPtr {
            const split: Split = @bitCast(@intFromPtr(ptr));
            assert(split.low == 0);
            return split.high;
        }
        fn unpack(ptr: PackedPtr) ?*Fiber {
            const split: Split = .{ .low = 0, .high = ptr };
            return @ptrFromInt(@as(usize, @bitCast(split)));
        }
    };

    fn requestCancel(fiber: *Fiber, ev: *Evented) void {
        const cancel_status = @atomicRmw(
            Fiber.CancelStatus,
            &fiber.cancel_status,
            .Or,
            .{ .requested = true, .awaiting = @enumFromInt(0) },
            .acquire,
        );
        assert(!cancel_status.requested);
        switch (cancel_status.awaiting) {
            .nothing => {},
            .group => {
                // The awaiter received a cancelation request while awaiting a group,
                // so propagate the cancelation to the group.
                if (fiber.status.awaiting_group.cancel(ev, null)) {
                    fiber.status = .{ .queue_next = null };
                    _ = ev.schedule(.current(), .{ .head = fiber, .tail = fiber });
                }
            },
            _ => |awaiting| {
                const awaiting_io_uring_fd = awaiting.toIoUringFd();
                const thread: *Thread = .current();
                thread.enqueue().* = if (thread.io_uring.fd == awaiting_io_uring_fd) .{
                    .opcode = .ASYNC_CANCEL,
                    .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
                    .ioprio = 0,
                    .fd = 0,
                    .off = 0,
                    .addr = @intFromPtr(fiber),
                    .len = 0,
                    .rw_flags = 0,
                    .user_data = @intFromEnum(Completion.Userdata.wakeup),
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                } else .{
                    .opcode = .MSG_RING,
                    .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
                    .ioprio = 0,
                    .fd = awaiting_io_uring_fd,
                    .off = @intFromPtr(fiber) | 0b01,
                    .addr = @intFromEnum(linux.IORING_MSG_RING_COMMAND.DATA),
                    .len = 0,
                    .rw_flags = 0,
                    .user_data = @intFromEnum(Completion.Userdata.cleanup),
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                };
            },
        }
    }
};

const CancelRegion = struct {
    fiber: *Fiber,
    status: Fiber.CancelStatus,
    fn init() CancelRegion {
        const fiber = Thread.current().currentFiber();
        return .{
            .fiber = fiber,
            .status = .{
                .requested = fiber.cancel_protection.check() == .unblocked,
                .awaiting = .nothing,
            },
        };
    }
    fn initBlocked() CancelRegion {
        return .{
            .fiber = Thread.current().currentFiber(),
            .status = .{ .requested = false, .awaiting = .nothing },
        };
    }
    fn deinit(cancel_region: *CancelRegion) void {
        if (cancel_region.status.requested) {
            @branchHint(.likely);
            _ = cancel_region.fiber.cancel_status.changeAwaiting(
                cancel_region.status.awaiting,
                .nothing,
            );
        }
        cancel_region.* = undefined;
    }
    fn await(cancel_region: *CancelRegion, awaiting: Fiber.CancelStatus.Awaiting) Io.Cancelable!void {
        if (!cancel_region.status.requested) {
            @branchHint(.unlikely);
            return;
        }
        const status: Fiber.CancelStatus = .{ .requested = true, .awaiting = awaiting };
        if (cancel_region.fiber.cancel_status.changeAwaiting(
            cancel_region.status.awaiting,
            status.awaiting,
        )) {
            @branchHint(.unlikely);
            cancel_region.fiber.cancel_protection.acknowledge();
            cancel_region.status = .unrequested;
            return error.Canceled;
        }
        cancel_region.status = status;
    }
    fn awaitIoUring(cancel_region: *CancelRegion) Io.Cancelable!*Thread {
        const thread: *Thread = .current();
        try cancel_region.await(.fromIoUringFd(thread.io_uring.fd));
        return thread;
    }
    fn completion(cancel_region: *const CancelRegion) Completion {
        return cancel_region.fiber.resultPointer(Completion).*;
    }
    fn errno(cancel_region: *const CancelRegion) linux.E {
        return cancel_region.completion().errno();
    }

    const Sync = struct {
        cancel_region: CancelRegion,
        fn init(ev: *Evented) Io.Cancelable!Sync {
            if (ev.sync_limit) |*sync_limit| try sync_limit.wait(ev.io());
            return .{ .cancel_region = .init() };
        }
        fn initBlocked(ev: *Evented) Sync {
            if (ev.sync_limit) |*sync_limit| sync_limit.waitUncancelable(ev.io());
            return .{ .cancel_region = .initBlocked() };
        }
        fn deinit(sync: *Sync, ev: *Evented) void {
            sync.cancel_region.deinit();
            if (ev.sync_limit) |*sync_limit| sync_limit.post(ev.io());
        }

        const Maybe = union(enum) {
            cancel_region: CancelRegion,
            sync: Sync,

            fn deinit(maybe: *Maybe, ev: *Evented) void {
                switch (maybe.*) {
                    .cancel_region => |*cancel_region| cancel_region.deinit(),
                    .sync => |*sync| sync.deinit(ev),
                }
            }

            fn enterSync(maybe: *Maybe, ev: *Evented) Io.Cancelable!*Sync {
                switch (maybe.*) {
                    .cancel_region => |cancel_region| {
                        if (ev.sync_limit) |*sync_limit| try sync_limit.wait(ev.io());
                        maybe.* = .{ .sync = .{ .cancel_region = cancel_region } };
                    },
                    .sync => {},
                }
                return &maybe.sync;
            }

            fn leaveSync(maybe: *Maybe, ev: *Evented) void {
                switch (maybe.*) {
                    .cancel_region => {},
                    .sync => |sync| {
                        if (ev.sync_limit) |*sync_limit| sync_limit.post(ev.io());
                        maybe.* = .{ .cancel_region = sync.cancel_region };
                    },
                }
            }

            fn cancelRegion(maybe: *Maybe) *CancelRegion {
                return switch (maybe.*) {
                    .cancel_region => |*cancel_region| cancel_region,
                    .sync => |*sync| &sync.cancel_region,
                };
            }
        };
    };
};

const CachedFd = struct {
    once: Once,

    const Once = enum(fd_t) {
        uninitialized = -1,
        initializing = -2,
        /// fd
        _,

        fn fromFd(fd: fd_t) Once {
            return @enumFromInt(@as(u31, @intCast(fd)));
        }

        fn toFd(once: Once) fd_t {
            return @as(u31, @intCast(@intFromEnum(once)));
        }
    };

    const init: CachedFd = .{ .once = .uninitialized };

    fn close(cached_fd: *CachedFd) void {
        switch (cached_fd.once) {
            .uninitialized => {},
            .initializing => unreachable,
            _ => |fd| {
                assert(@intFromEnum(fd) >= 0);
                _ = linux.close(@intFromEnum(fd));
                cached_fd.* = .init;
            },
        }
    }

    fn open(
        cached_fd: *CachedFd,
        ev: *Evented,
        cancel_region: *CancelRegion,
        path: [*:0]const u8,
        flags: linux.O,
    ) File.OpenError!fd_t {
        var once = @atomicLoad(Once, &cached_fd.once, .monotonic);
        while (true) {
            switch (once) {
                .uninitialized => {},
                .initializing => try futexWait(
                    ev,
                    @ptrCast(&cached_fd.once),
                    @bitCast(@intFromEnum(once)),
                    .none,
                ),
                _ => |fd| {
                    @branchHint(.likely);
                    return fd.toFd();
                },
            }
            once = @cmpxchgWeak(
                Once,
                &cached_fd.once,
                .uninitialized,
                .initializing,
                .monotonic,
                .monotonic,
            ) orelse {
                errdefer {
                    @atomicStore(Once, &cached_fd.once, .uninitialized, .monotonic);
                    futexWake(ev, @ptrCast(&cached_fd.once), 1);
                }
                const fd = ev.openat(cancel_region, linux.AT.FDCWD, path, flags, 0) catch |err| switch (err) {
                    error.OperationUnsupported => return error.Unexpected, // TMPFILE unset.
                    else => |e| return e,
                };
                @atomicStore(Once, &cached_fd.once, .fromFd(fd), .monotonic);
                futexWake(ev, @ptrCast(&cached_fd.once), std.math.maxInt(u32));
                return fd;
            };
        }
    }
};

pub fn allocator(ev: *Evented) std.mem.Allocator {
    return if (ev.backing_allocator_needs_mutex) .{
        .ptr = ev,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    } else ev.backing_allocator;
}

fn alloc(userdata: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    ev.backing_allocator_mutex.lockUncancelable(ev_io);
    defer ev.backing_allocator_mutex.unlock(ev_io);
    return ev.backing_allocator.rawAlloc(len, alignment, ret_addr);
}

fn resize(
    userdata: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    ev.backing_allocator_mutex.lockUncancelable(ev_io);
    defer ev.backing_allocator_mutex.unlock(ev_io);
    return ev.backing_allocator.rawResize(memory, alignment, new_len, ret_addr);
}

fn remap(
    userdata: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    ev.backing_allocator_mutex.lockUncancelable(ev_io);
    defer ev.backing_allocator_mutex.unlock(ev_io);
    return ev.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
}

fn free(userdata: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    ev.backing_allocator_mutex.lockUncancelable(ev_io);
    defer ev.backing_allocator_mutex.unlock(ev_io);
    return ev.backing_allocator.rawFree(memory, alignment, ret_addr);
}

pub fn io(ev: *Evented) Io {
    return .{
        .userdata = ev,
        .vtable = &.{
            .crashHandler = crashHandler,

            .async = async,
            .concurrent = concurrent,
            .await = await,
            .cancel = cancel,

            .groupAsync = groupAsync,
            .groupConcurrent = groupConcurrent,
            .groupAwait = groupAwait,
            .groupCancel = groupCancel,

            .recancel = recancel,
            .swapCancelProtection = swapCancelProtection,
            .checkCancel = checkCancel,

            .futexWait = futexWait,
            .futexWaitUncancelable = futexWaitUncancelable,
            .futexWake = futexWake,

            .operate = operate,
            .batchAwaitAsync = batchAwaitAsync,
            .batchAwaitConcurrent = batchAwaitConcurrent,
            .batchCancel = batchCancel,

            .dirCreateDir = dirCreateDir,
            .dirCreateDirPath = dirCreateDirPath,
            .dirCreateDirPathOpen = dirCreateDirPathOpen,
            .dirOpenDir = dirOpenDir,
            .dirStat = dirStat,
            .dirStatFile = dirStatFile,
            .dirAccess = dirAccess,
            .dirCreateFile = dirCreateFile,
            .dirCreateFileAtomic = dirCreateFileAtomic,
            .dirOpenFile = dirOpenFile,
            .dirClose = dirClose,
            .dirRead = dirRead,
            .dirRealPath = dirRealPath,
            .dirRealPathFile = dirRealPathFile,
            .dirDeleteFile = dirDeleteFile,
            .dirDeleteDir = dirDeleteDir,
            .dirRename = dirRename,
            .dirRenamePreserve = dirRenamePreserve,
            .dirSymLink = dirSymLink,
            .dirReadLink = dirReadLink,
            .dirSetOwner = dirSetOwner,
            .dirSetFileOwner = dirSetFileOwner,
            .dirSetPermissions = dirSetPermissions,
            .dirSetFilePermissions = dirSetFilePermissions,
            .dirSetTimestamps = dirSetTimestamps,
            .dirHardLink = dirHardLink,

            .fileStat = fileStat,
            .fileLength = fileLength,
            .fileClose = fileClose,
            .fileWritePositional = fileWritePositional,
            .fileWriteFileStreaming = fileWriteFileStreaming,
            .fileWriteFilePositional = fileWriteFilePositional,
            .fileReadPositional = fileReadPositional,
            .fileSeekBy = fileSeekBy,
            .fileSeekTo = fileSeekTo,
            .fileSync = fileSync,
            .fileIsTty = fileIsTty,
            .fileEnableAnsiEscapeCodes = fileEnableAnsiEscapeCodes,
            .fileSupportsAnsiEscapeCodes = fileIsTty,
            .fileSetLength = fileSetLength,
            .fileSetOwner = fileSetOwner,
            .fileSetPermissions = fileSetPermissions,
            .fileSetTimestamps = fileSetTimestamps,
            .fileLock = fileLock,
            .fileTryLock = fileTryLock,
            .fileUnlock = fileUnlock,
            .fileDowngradeLock = fileDowngradeLock,
            .fileRealPath = fileRealPath,
            .fileHardLink = fileHardLink,

            .fileMemoryMapCreate = fileMemoryMapCreate,
            .fileMemoryMapDestroy = fileMemoryMapDestroy,
            .fileMemoryMapSetLength = fileMemoryMapSetLength,
            .fileMemoryMapRead = fileMemoryMapRead,
            .fileMemoryMapWrite = fileMemoryMapWrite,

            .processExecutableOpen = processExecutableOpen,
            .processExecutablePath = processExecutablePath,
            .lockStderr = lockStderr,
            .tryLockStderr = tryLockStderr,
            .unlockStderr = unlockStderr,
            .processCurrentPath = processCurrentPath,
            .processSetCurrentDir = processSetCurrentDir,
            .processSetCurrentPath = processSetCurrentPath,
            .processReplace = processReplace,
            .processReplacePath = processReplacePath,
            .processSpawn = processSpawn,
            .processSpawnPath = processSpawnPath,
            .childWait = childWait,
            .childKill = childKill,

            .progressParentFile = progressParentFile,

            .now = now,
            .clockResolution = clockResolution,
            .sleep = sleep,

            .random = random,
            .randomSecure = randomSecure,

            .netListenIp = netListenIpUnavailable,
            .netAccept = netAcceptUnavailable,
            .netBindIp = netBindIp,
            .netConnectIp = netConnectIpUnavailable,
            .netListenUnix = netListenUnixUnavailable,
            .netConnectUnix = netConnectUnixUnavailable,
            .netSocketCreatePair = netSocketCreatePairUnavailable,
            .netSend = netSendUnavailable,
            .netRead = netReadUnavailable,
            .netWrite = netWriteUnavailable,
            .netWriteFile = netWriteFileUnavailable,
            .netClose = netClose,
            .netShutdown = netShutdown,
            .netInterfaceNameResolve = netInterfaceNameResolveUnavailable,
            .netInterfaceName = netInterfaceNameUnavailable,
            .netLookup = netLookupUnavailable,
        },
    };
}

pub const InitOptions = struct {
    backing_allocator_needs_mutex: bool = true,

    /// Maximum thread pool size (excluding the main thread).
    /// Defaults to one less than the number of logical CPU cores.
    thread_limit: ?usize = null,
    /// Maximum number of threads that may perform synchronous syscalls.
    sync_limit: Io.Limit = .unlimited,

    log2_ring_entries: u4 = 3,

    /// Affects the following operations:
    /// * `processExecutablePath` on OpenBSD and Haiku.
    argv0: Argv0 = .empty,
    /// Affects the following operations:
    /// * `fileIsTty`
    /// * `processSpawn`, `processSpawnPath`, `processReplace`, `processReplacePath`
    environ: process.Environ = .empty,
};

pub fn init(ev: *Evented, backing_allocator: Allocator, options: InitOptions) !void {
    const threads_size = @sizeOf(Thread) * if (options.thread_limit) |thread_limit|
        1 + thread_limit
    else
        @max(std.Thread.getCpuCount() catch 1, 1);
    const idle_stack_end_offset =
        std.mem.alignForward(usize, threads_size + idle_stack_size, std.heap.pageSize());
    const allocated_slice = try backing_allocator.alignedAlloc(u8, .of(Thread), idle_stack_end_offset);
    errdefer backing_allocator.free(allocated_slice);
    ev.* = .{
        .backing_allocator_needs_mutex = options.backing_allocator_needs_mutex,
        .backing_allocator_mutex = .init,
        .backing_allocator = backing_allocator,
        .main_fiber_buffer = undefined,
        .log2_ring_entries = options.log2_ring_entries,
        .threads = .{
            .allocated = @ptrCast(allocated_slice[0..threads_size]),
            .reserved = 1,
            .active = 1,
        },
        .sync_limit = if (options.sync_limit.toInt()) |sync_limit| .{ .permits = sync_limit } else null,

        .stderr_writer_initialized = false,
        .stderr_mutex = .init,
        .stderr_writer = .{
            .io = ev.io(),
            .interface = Io.File.Writer.initInterface(&.{}),
            .file = .stderr(),
            .mode = .streaming,
        },
        .stderr_mode = .no_color,

        .environ_mutex = .init,
        .environ_initialized = options.environ.block.isEmpty(),
        .environ = .{ .process_environ = options.environ },

        .null_fd = .init,
        .random_fd = .init,

        .csprng_mutex = .init,
        .csprng = .uninitialized,
    };
    const main_fiber: *Fiber = @ptrCast(&ev.main_fiber_buffer);
    main_fiber.* = .{
        .required_align = {},
        .context = undefined,
        .link = .{ .awaiter = null },
        .status = .{ .queue_next = null },
        .cancel_status = .unrequested,
        .cancel_protection = .unblocked,
        .name = if (tracy.enable) "main task",
    };
    const main_thread = &ev.threads.allocated[0];
    Thread.self = main_thread;
    main_thread.* = .{
        .required_align = {},
        .thread = undefined,
        .idle_context = switch (builtin.cpu.arch) {
            .aarch64 => .{
                .sp = @intFromPtr(allocated_slice[idle_stack_end_offset..].ptr),
                .fp = @intFromPtr(ev),
                .pc = @intFromPtr(&mainIdleEntry),
            },
            .riscv64 => .{
                .sp = @intFromPtr(allocated_slice[idle_stack_end_offset..].ptr),
                .fp = @intFromPtr(ev),
                .pc = @intFromPtr(&mainIdleEntry),
            },
            .x86_64 => .{
                .rsp = @intFromPtr(allocated_slice[idle_stack_end_offset..].ptr),
                .rbp = @intFromPtr(ev),
                .rip = @intFromPtr(&mainIdleEntry),
            },
            else => @compileError("unimplemented architecture"),
        },
        .current_context = &main_fiber.context,
        .ready_queue = null,
        .free_queue = null,
        .io_uring = try .init(
            @as(u16, 1) << ev.log2_ring_entries,
            linux.IORING_SETUP_COOP_TASKRUN | linux.IORING_SETUP_SINGLE_ISSUER,
        ),
        .idle_search_index = 1,
        .steal_ready_search_index = 1,
        .steal_free_search_index = 1,
        .name_arena = .{},
        .csprng = .uninitialized,
    };
    errdefer main_thread.io_uring.deinit();
    if (tracy.enable) tracy.fiberEnter(main_fiber.name);
}

pub fn deinit(ev: *Evented) void {
    const main_fiber: *Fiber = @ptrCast(&ev.main_fiber_buffer);
    assert(Thread.current().currentFiber() == main_fiber);
    const active_threads = @atomicLoad(u32, &ev.threads.active, .acquire);
    for (ev.threads.allocated[0..active_threads]) |*thread| {
        const ready_fiber = @atomicLoad(?*Fiber, &thread.ready_queue, .monotonic);
        assert(ready_fiber == null or ready_fiber == Fiber.finished); // pending async
    }
    ev.yield(null, .exit);
    ev.null_fd.close();
    ev.random_fd.close();
    const allocated_ptr: [*]align(@alignOf(Thread)) u8 = @ptrCast(@alignCast(ev.threads.allocated.ptr));
    const idle_stack_end_offset = std.mem.alignForward(
        usize,
        ev.threads.allocated.len * @sizeOf(Thread) + idle_stack_size,
        std.heap.page_size_max,
    );
    for (ev.threads.allocated[1..active_threads]) |*thread| thread.thread.join();
    for (ev.threads.allocated[0..active_threads]) |*thread| thread.deinit(ev.backing_allocator);
    assert(active_threads == ev.threads.active); // spawned threads while there was no pending async?
    ev.backing_allocator.free(allocated_ptr[0..idle_stack_end_offset]);
    ev.* = undefined;
}

fn findReadyFiber(ev: *Evented, thread: *Thread) ?*Fiber {
    if (@atomicRmw(?*Fiber, &thread.ready_queue, .Xchg, Fiber.finished, .acquire)) |ready_fiber| {
        assert(ready_fiber != Fiber.finished);
        @atomicStore(?*Fiber, &thread.ready_queue, ready_fiber.status.queue_next, .release);
        ready_fiber.status.queue_next = null;
        return ready_fiber;
    }
    const active_threads = @atomicLoad(u32, &ev.threads.active, .acquire);
    for (0..@min(max_steal_ready_search, active_threads)) |_| {
        defer thread.steal_ready_search_index += 1;
        if (thread.steal_ready_search_index == active_threads) thread.steal_ready_search_index = 0;
        const steal_ready_search_thread =
            &ev.threads.allocated[0..active_threads][thread.steal_ready_search_index];
        if (steal_ready_search_thread == thread) continue;
        const ready_fiber =
            @atomicLoad(?*Fiber, &steal_ready_search_thread.ready_queue, .monotonic) orelse continue;
        if (ready_fiber == Fiber.finished) continue;
        if (@cmpxchgWeak(
            ?*Fiber,
            &steal_ready_search_thread.ready_queue,
            ready_fiber,
            null,
            .acquire,
            .monotonic,
        )) |_| continue;
        @atomicStore(?*Fiber, &thread.ready_queue, ready_fiber.status.queue_next, .release);
        ready_fiber.status.queue_next = null;
        return ready_fiber;
    }
    // couldn't find anything to do, so we are now open for business
    @atomicStore(?*Fiber, &thread.ready_queue, null, .monotonic);
    return null;
}

fn yield(ev: *Evented, maybe_ready_fiber: ?*Fiber, pending_task: SwitchMessage.PendingTask) void {
    const thread: *Thread = .current();
    const ready_context = if (maybe_ready_fiber orelse ev.findReadyFiber(thread)) |ready_fiber|
        &ready_fiber.context
    else
        &thread.idle_context;
    const message: SwitchMessage = .{
        .contexts = .{
            .old = thread.current_context,
            .new = ready_context,
        },
        .pending_task = pending_task,
    };
    contextSwitch(&message).handle(ev);
}

fn schedule(ev: *Evented, thread: *Thread, ready_queue: Fiber.Queue) bool {
    // shared fields of previous `Thread` must be initialized before later ones are marked as active
    const new_thread_index = @atomicLoad(u32, &ev.threads.active, .acquire);
    for (0..@min(max_idle_search, new_thread_index)) |_| {
        defer thread.idle_search_index += 1;
        if (thread.idle_search_index == new_thread_index) thread.idle_search_index = 0;
        const idle_search_thread = &ev.threads.allocated[0..new_thread_index][thread.idle_search_index];
        if (idle_search_thread == thread) continue;
        if (@cmpxchgWeak(
            ?*Fiber,
            &idle_search_thread.ready_queue,
            null,
            ready_queue.head,
            .release,
            .monotonic,
        )) |_| continue;
        thread.enqueue().* = .{
            .opcode = .MSG_RING,
            .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
            .ioprio = 0,
            .fd = idle_search_thread.io_uring.fd,
            .off = @intFromEnum(Completion.Userdata.wakeup),
            .addr = @intFromEnum(linux.IORING_MSG_RING_COMMAND.DATA),
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromEnum(Completion.Userdata.wakeup),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        return true;
    }
    spawn_thread: {
        // previous failed reservations must have completed before retrying
        if (new_thread_index == ev.threads.allocated.len or @cmpxchgWeak(
            u32,
            &ev.threads.reserved,
            new_thread_index,
            new_thread_index + 1,
            .acquire,
            .monotonic,
        ) != null) break :spawn_thread;
        const new_thread = &ev.threads.allocated[new_thread_index];
        const next_thread_index = new_thread_index + 1;
        var params = std.mem.zeroInit(linux.io_uring_params, .{
            .flags = linux.IORING_SETUP_ATTACH_WQ |
                linux.IORING_SETUP_R_DISABLED |
                linux.IORING_SETUP_COOP_TASKRUN |
                linux.IORING_SETUP_SINGLE_ISSUER,
            .wq_fd = @as(u32, @intCast(ev.threads.allocated[0].io_uring.fd)),
        });
        new_thread.* = .{
            .required_align = {},
            .thread = undefined,
            .idle_context = undefined,
            .current_context = &new_thread.idle_context,
            .ready_queue = ready_queue.head,
            .free_queue = null,
            .io_uring = IoUring.init_params(@as(u16, 1) << ev.log2_ring_entries, &params) catch |err| {
                @atomicStore(u32, &ev.threads.reserved, new_thread_index, .release);
                // no more access to `thread` after giving up reservation
                log.warn("unable to create worker thread due to io_uring init failure: {s}", .{
                    @errorName(err),
                });
                break :spawn_thread;
            },
            .idle_search_index = 0,
            .steal_ready_search_index = 0,
            .steal_free_search_index = 0,
            .name_arena = .{},
            .csprng = .uninitialized,
        };
        new_thread.thread = std.Thread.spawn(.{
            .stack_size = idle_stack_size,
            .allocator = ev.allocator(),
        }, threadEntry, .{ ev, new_thread_index }) catch |err| {
            new_thread.io_uring.deinit();
            @atomicStore(u32, &ev.threads.reserved, new_thread_index, .release);
            // no more access to `thread` after giving up reservation
            log.warn("unable to create worker thread due spawn failure: {s}", .{@errorName(err)});
            break :spawn_thread;
        };
        // shared fields of `Thread` must be initialized before being marked active
        @atomicStore(u32, &ev.threads.active, next_thread_index, .release);
        return false;
    }
    // nobody wanted it, so just queue it on ourselves
    while (true) ready_queue.tail.status.queue_next = @cmpxchgWeak(
        ?*Fiber,
        &thread.ready_queue,
        ready_queue.tail.status.queue_next,
        ready_queue.head,
        .acq_rel,
        .acquire,
    ) orelse break;
    return false;
}

fn threadEntry(ev: *Evented, index: u32) void {
    const thread: *Thread = &ev.threads.allocated[index];
    Thread.self = thread;
    switch (linux.errno(linux.io_uring_register(thread.io_uring.fd, .REGISTER_ENABLE_RINGS, null, 0))) {
        .SUCCESS => ev.idle(thread),
        else => |err| @panic(@tagName(err)),
    }
}

const Completion = struct {
    result: i32,
    flags: u32,

    const Userdata = enum(usize) {
        unused,
        wakeup,
        futex_wake,
        close,
        cleanup,
        exit,
        /// If bit 0 is 1, a pointer to the `context` field of `Io.Batch.Storage.Pending`.
        /// If bits 0 and 1 are 0, a `*Fiber`.
        _,
    };

    fn errno(completion: Completion) linux.E {
        return linux.errno(@bitCast(@as(isize, completion.result)));
    }
};

fn mainIdleEntry() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .aarch64 => asm volatile (
            \\ mov x0, fp
            \\ mov fp, #0
            \\ b %[mainIdle]
            :
            : [mainIdle] "X" (&mainIdle),
        ),
        .riscv64 => asm volatile (
            \\ mv a0, fp
            \\ mv fp, zero
            \\ tail %[mainIdle]@plt
            :
            : [mainIdle] "X" (&mainIdle),
        ),
        .x86_64 => asm volatile (
            \\ movq %%rbp, %%rdi
            \\ xor %%ebp, %%ebp
            \\ jmp %[mainIdle:P]
            :
            : [mainIdle] "X" (&mainIdle),
        ),
        else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
    }
}

fn mainIdle(
    ev: *Evented,
    message: *const SwitchMessage,
) callconv(.withStackAlign(.c, @max(@alignOf(Thread), @alignOf(Io.fiber.Context)))) noreturn {
    message.handle(ev);
    ev.idle(&ev.threads.allocated[0]);
    ev.yield(@ptrCast(&ev.main_fiber_buffer), .nothing);
    unreachable; // switched to dead fiber
}

fn idle(ev: *Evented, thread: *Thread) void {
    var maybe_ready_fiber: ?*Fiber = null;
    while (true) {
        while (maybe_ready_fiber orelse ev.findReadyFiber(thread)) |ready_fiber| {
            ev.yield(ready_fiber, .nothing);
            maybe_ready_fiber = null;
        }
        _ = thread.io_uring.submit_and_wait(1) catch |err| switch (err) {
            error.SignalInterrupt => {},
            else => |e| @panic(@errorName(e)),
        };
        var maybe_ready_queue: ?Fiber.Queue = null;
        while (true) {
            var cqes_buffer: [1 << 8]linux.io_uring_cqe = undefined;
            const cqes = cqes_buffer[0 .. thread.io_uring.copy_cqes(&cqes_buffer, 0) catch |err| switch (err) {
                error.SignalInterrupt => 0,
                else => |e| @panic(@errorName(e)),
            }];
            if (cqes.len == 0) break;
            for (cqes) |cqe| if (cqe.flags & linux.IORING_CQE_F_SKIP == 0) switch (@as(
                Completion.Userdata,
                @enumFromInt(cqe.user_data),
            )) {
                .unused => unreachable, // bad submission queued?
                .wakeup => {},
                .futex_wake => switch (Completion.errno(.{ .result = cqe.res, .flags = cqe.flags })) {
                    .SUCCESS => recoverableOsBugDetected(), // success is skipped
                    .INVAL => {}, // invalid futex_wait() on ptr done elsewhere
                    .INTR, .CANCELED => recoverableOsBugDetected(), // `Completion.Userdata.futex_wake` is not cancelable
                    .FAULT => {}, // pointer became invalid while doing the wake
                    else => recoverableOsBugDetected(), // deadlock due to operating system bug
                },
                .close => switch (Completion.errno(.{ .result = cqe.res, .flags = cqe.flags })) {
                    .BADF => recoverableOsBugDetected(), // Always a race condition.
                    .INTR => {}, // This is still a success. See https://github.com/ziglang/zig/issues/2425
                    else => {},
                },
                .cleanup => @panic("failed to notify other threads that we are exiting"),
                .exit => {
                    assert(maybe_ready_fiber == null and maybe_ready_queue == null); // pending async
                    return;
                },
                _ => if (@as(?*Fiber, ready_fiber: switch (@as(u2, @truncate(cqe.user_data))) {
                    0b00 => {
                        const ready_fiber: *Fiber = @ptrFromInt(cqe.user_data & ~@as(usize, 0b11));
                        ready_fiber.resultPointer(Completion).* = .{
                            .result = cqe.res,
                            .flags = cqe.flags,
                        };
                        break :ready_fiber ready_fiber;
                    },
                    0b01 => {
                        thread.enqueue().* = .{
                            .opcode = .ASYNC_CANCEL,
                            .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
                            .ioprio = 0,
                            .fd = 0,
                            .off = 0,
                            .addr = cqe.user_data & ~@as(usize, 0b11),
                            .len = 0,
                            .rw_flags = 0,
                            .user_data = @intFromEnum(Completion.Userdata.wakeup),
                            .buf_index = 0,
                            .personality = 0,
                            .splice_fd_in = 0,
                            .addr3 = 0,
                            .resv = 0,
                        };
                        break :ready_fiber null;
                    },
                    0b10 => {
                        const batch_userdata: *Io.Operation.Storage.Pending.Userdata =
                            @ptrFromInt(cqe.user_data & ~@as(usize, 0b11));
                        const batch: *Io.Batch = @ptrFromInt(batch_userdata[0]);
                        var next: usize = 0b00;
                        batch_userdata[0..3].* = .{ next, @as(u32, @bitCast(cqe.res)), cqe.flags };
                        while (true) {
                            next = @cmpxchgWeak(
                                usize,
                                @as(*usize, @ptrCast(&batch.userdata)),
                                next,
                                cqe.user_data,
                                .release,
                                .acquire,
                            ) orelse break;
                            batch_userdata[0] = next;
                        }
                        break :ready_fiber switch (@as(u2, @truncate(next))) {
                            0b00, 0b01 => @ptrFromInt(next & ~@as(usize, 0b11)),
                            0b10, 0b11 => null,
                        };
                    },
                    0b11 => switch (Completion.errno(.{ .result = cqe.res, .flags = cqe.flags })) {
                        .SUCCESS => unreachable, // no event count specified
                        .TIME => {
                            const context: *usize = @ptrFromInt(cqe.user_data & ~@as(usize, 0b11));
                            const fiber = @atomicRmw(usize, context, .Add, 0b01, .acquire);
                            break :ready_fiber switch (@as(u2, @truncate(fiber))) {
                                else => unreachable, // timeout completed multiple times
                                0b00 => @ptrFromInt(fiber & ~@as(usize, 0b11)),
                                0b10 => null,
                            };
                        },
                        .CANCELED => null, // user data may have been invalidated
                        else => |err| unexpectedErrno(err) catch null,
                    },
                })) |ready_fiber| {
                    assert(ready_fiber.status.queue_next == null);
                    if (maybe_ready_fiber == null) {
                        maybe_ready_fiber = ready_fiber;
                    } else if (maybe_ready_queue) |*ready_queue| {
                        ready_queue.tail.status.queue_next = ready_fiber;
                        ready_queue.tail = ready_fiber;
                    } else maybe_ready_queue = .{ .head = ready_fiber, .tail = ready_fiber };
                },
            };
        }
        if (maybe_ready_queue) |ready_queue| _ = ev.schedule(thread, ready_queue);
    }
}

const SwitchMessage = struct {
    contexts: Io.fiber.Switch,
    pending_task: PendingTask,

    const PendingTask = union(enum) {
        nothing,
        reschedule,
        await: *Fiber,
        group_await: Group,
        group_cancel: Group,
        batch_await: *Io.Batch,
        destroy,
        exit,
    };

    fn handle(message: *const SwitchMessage, ev: *Evented) void {
        const thread: *Thread = .current();
        thread.current_context = message.contexts.new;
        if (tracy.enable) {
            if (message.contexts.new != &thread.idle_context) {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.new));
                tracy.fiberEnter(fiber.name);
            } else tracy.fiberLeave();
        }
        switch (message.pending_task) {
            .nothing => {},
            .reschedule => if (message.contexts.old != &thread.idle_context) {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                assert(fiber.status.queue_next == null);
                _ = ev.schedule(thread, .{ .head = fiber, .tail = fiber });
            },
            .await => |awaiting| {
                const awaiter: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                assert(awaiter.status.queue_next == null);
                if (@atomicRmw(?*Fiber, &awaiting.link.awaiter, .Xchg, awaiter, .acq_rel) ==
                    Fiber.finished) _ = ev.schedule(thread, .{ .head = awaiter, .tail = awaiter });
            },
            .group_await => |group| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (group.await(ev, fiber))
                    _ = ev.schedule(thread, .{ .head = fiber, .tail = fiber });
            },
            .group_cancel => |group| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (group.cancel(ev, fiber))
                    _ = ev.schedule(thread, .{ .head = fiber, .tail = fiber });
            },
            .batch_await => |batch| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (@cmpxchgStrong(
                    ?*anyopaque,
                    &batch.userdata,
                    null,
                    fiber,
                    .release,
                    .monotonic,
                )) |head| {
                    assert(@as(u2, @truncate(@intFromPtr(head))) != 0b00);
                    _ = ev.schedule(thread, .{ .head = fiber, .tail = fiber });
                }
            },
            .destroy => {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                fiber.destroy();
            },
            .exit => for (
                ev.threads.allocated[0..@atomicLoad(u32, &ev.threads.active, .acquire)],
            ) |*each_thread| {
                thread.enqueue().* = .{
                    .opcode = .MSG_RING,
                    .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
                    .ioprio = 0,
                    .fd = each_thread.io_uring.fd,
                    .off = @intFromEnum(Completion.Userdata.exit),
                    .addr = @intFromEnum(linux.IORING_MSG_RING_COMMAND.DATA),
                    .len = 0,
                    .rw_flags = 0,
                    .user_data = @intFromEnum(Completion.Userdata.cleanup),
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                };
            },
        }
    }
};

inline fn contextSwitch(message: *const SwitchMessage) *const SwitchMessage {
    return @fieldParentPtr("contexts", Io.fiber.contextSwitch(&message.contexts));
}

fn crashHandler(userdata: ?*anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const thread = Thread.self orelse std.process.abort();
    if (thread.current_context == &thread.idle_context) std.process.abort();
    const fiber = thread.currentFiber();
    @atomicStore(
        Fiber.CancelStatus,
        &fiber.cancel_status,
        .{ .requested = true, .awaiting = .nothing },
        .monotonic,
    );
    fiber.cancel_protection = .{ .user = .blocked, .acknowledged = true };
}

const AsyncClosure = struct {
    evented: *Evented,
    fiber: *Fiber,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
    result_align: Alignment,

    fn fromFiber(fiber: *Fiber) *AsyncClosure {
        return @ptrFromInt(Fiber.max_context_align.max(.of(AsyncClosure)).backward(
            @intFromPtr(fiber.allocatedEnd()) - Fiber.max_context_size,
        ) - @sizeOf(AsyncClosure));
    }

    fn contextPointer(closure: *AsyncClosure) [*]align(Fiber.max_context_align.toByteUnits()) u8 {
        return @alignCast(@as([*]u8, @ptrCast(closure)) + @sizeOf(AsyncClosure));
    }

    fn entry() callconv(.naked) void {
        switch (builtin.cpu.arch) {
            .aarch64 => asm volatile (
                \\ mov x0, sp
                \\ b %[call]
                :
                : [call] "X" (&call),
            ),
            .riscv64 => asm volatile (
                \\ mv a0, sp
                \\ tail %[call]@plt
                :
                : [call] "X" (&call),
            ),
            .x86_64 => asm volatile (
                \\ leaq 8(%%rsp), %%rdi
                \\ jmp %[call:P]
                :
                : [call] "X" (&call),
            ),
            else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
        }
    }

    fn call(
        closure: *AsyncClosure,
        message: *const SwitchMessage,
    ) callconv(.withStackAlign(.c, @alignOf(AsyncClosure))) noreturn {
        const ev = closure.evented;
        const fiber = closure.fiber;
        message.handle(ev);
        closure.start(closure.contextPointer(), fiber.resultBytes(closure.result_align));
        ev.yield(@atomicRmw(?*Fiber, &fiber.link.awaiter, .Xchg, Fiber.finished, .acq_rel), .nothing);
        unreachable; // switched to dead fiber
    }
};

fn async(
    userdata: ?*anyopaque,
    result: []u8,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*std.Io.AnyFuture {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return concurrent(ev, result.len, result_alignment, context, context_alignment, start) catch {
        start(context.ptr, result.ptr);
        return null;
    };
}

fn concurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) Io.ConcurrentError!*std.Io.AnyFuture {
    assert(result_alignment.compare(.lte, Fiber.max_result_align)); // TODO
    assert(context_alignment.compare(.lte, Fiber.max_context_align)); // TODO
    assert(result_len <= Fiber.max_result_size); // TODO
    assert(context.len <= Fiber.max_context_size); // TODO

    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const fiber = Fiber.create(ev) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };

    const closure: *AsyncClosure = .fromFiber(fiber);
    fiber.* = .{
        .required_align = {},
        .context = switch (builtin.cpu.arch) {
            .aarch64 => .{
                .sp = @intFromPtr(closure),
                .fp = 0,
                .pc = @intFromPtr(&AsyncClosure.entry),
            },
            .riscv64 => .{
                .sp = @intFromPtr(closure),
                .fp = 0,
                .pc = @intFromPtr(&AsyncClosure.entry),
            },
            .x86_64 => .{
                .rsp = @intFromPtr(closure) - 8,
                .rbp = 0,
                .rip = @intFromPtr(&AsyncClosure.entry),
            },
            else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
        },
        .link = .{ .awaiter = null },
        .status = .{ .queue_next = null },
        .cancel_status = .unrequested,
        .cancel_protection = .unblocked,
        .name = if (tracy.enable) name: {
            const thread: *Thread = .current();
            var name_arena = thread.name_arena.promote(std.heap.page_allocator);
            defer thread.name_arena = name_arena.state;
            break :name std.fmt.allocPrintSentinel(
                name_arena.allocator(),
                "task {d}",
                .{@atomicRmw(u64, &Fiber.next_name, .Add, 1, .monotonic)},
                0,
            ) catch return error.ConcurrencyUnavailable;
        },
    };
    closure.* = .{
        .evented = ev,
        .fiber = fiber,
        .start = start,
        .result_align = result_alignment,
    };
    @memcpy(closure.contextPointer(), context);

    const thread: *Thread = .current();
    if (ev.schedule(thread, .{ .head = fiber, .tail = fiber })) thread.submit();
    return @ptrCast(fiber);
}

fn await(
    userdata: ?*anyopaque,
    future: *std.Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const awaiting: *Fiber = @ptrCast(@alignCast(future));
    if (@atomicLoad(?*Fiber, &awaiting.link.awaiter, .acquire) != Fiber.finished)
        ev.yield(null, .{ .await = awaiting });
    @memcpy(result, awaiting.resultBytes(result_alignment));
    awaiting.destroy();
}

fn cancel(
    userdata: ?*anyopaque,
    future: *std.Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const future_fiber: *Fiber = @ptrCast(@alignCast(future));
    future_fiber.requestCancel(ev);
    await(ev, future, result, result_alignment);
}

const Group = struct {
    ptr: *Io.Group,

    const List = packed struct(usize) {
        cancel_requested: bool,
        awaiter_delayed: bool,
        fibers: Fiber.PackedPtr,
    };
    fn listPtr(group: Group) *List {
        return @ptrCast(&group.ptr.token);
    }

    const Mutex = packed struct(u32) {
        locked: bool,
        contended: bool,
        shared2: u30,
    };
    fn mutexPtr(group: Group) *Mutex {
        return switch (comptime builtin.cpu.arch.endian()) {
            .little => @ptrCast(&group.ptr.state),
            .big => @ptrCast(@alignCast(
                @as([*]u8, @ptrCast(&group.ptr.state)) + @sizeOf(usize) - @sizeOf(u32),
            )),
        };
    }

    const Awaiter = packed struct(usize) {
        locked: bool,
        contended: bool,
        awaiter: Fiber.PackedPtr,
    };
    fn awaiterPtr(group: Group) *Awaiter {
        return @ptrCast(&group.ptr.state);
    }

    fn lock(group: Group, ev: *Evented) void {
        const mutex = group.mutexPtr();
        {
            const old_state = @atomicRmw(
                Mutex,
                mutex,
                .Or,
                .{ .locked = true, .contended = false, .shared2 = 0 },
                .acquire,
            );
            if (!old_state.locked) {
                @branchHint(.likely);
                return;
            }
            if (old_state.contended) {
                futexWaitUncancelable(ev, @ptrCast(mutex), @bitCast(old_state));
            }
        }
        while (true) {
            var old_state = @atomicRmw(
                Mutex,
                mutex,
                .Or,
                .{ .locked = true, .contended = true, .shared2 = 0 },
                .acquire,
            );
            if (!old_state.locked) {
                @branchHint(.likely);
                return;
            }
            old_state.contended = true;
            futexWaitUncancelable(ev, @ptrCast(mutex), @bitCast(old_state));
        }
    }

    fn unlock(group: Group, ev: *Evented) void {
        const mutex = group.mutexPtr();
        const old_state = @atomicRmw(
            Mutex,
            mutex,
            .And,
            .{ .locked = false, .contended = false, .shared2 = std.math.maxInt(u30) },
            .release,
        );
        assert(old_state.locked);
        if (old_state.contended) futexWake(ev, @ptrCast(mutex), 1);
    }

    fn addFiber(group: Group, ev: *Evented, fiber: *Fiber) void {
        group.lock(ev);
        defer group.unlock(ev);
        const list_ptr = group.listPtr();
        const list = @atomicLoad(List, list_ptr, .monotonic);
        if (list.cancel_requested) fiber.cancel_status = .{ .requested = true, .awaiting = .nothing };
        const old_head = list.fibers.unpack();
        if (old_head) |head| head.link.group.prev = fiber;
        fiber.link.group.next = old_head;
        @atomicStore(List, list_ptr, .{
            .cancel_requested = list.cancel_requested,
            .awaiter_delayed = list.awaiter_delayed,
            .fibers = .pack(fiber),
        }, .monotonic);
    }

    fn removeFiber(group: Group, ev: *Evented, fiber: *Fiber) ?*Fiber {
        group.lock(ev);
        defer group.unlock(ev);
        const list_ptr = group.listPtr();
        const list = @atomicLoad(List, list_ptr, .monotonic);
        if (fiber.link.group.next) |next| next.link.group.prev = fiber.link.group.prev;
        if (fiber.link.group.prev) |prev| {
            prev.link.group.next = fiber.link.group.next;
        } else if (fiber.link.group.next) |new_head| {
            @atomicStore(List, list_ptr, .{
                .cancel_requested = list.cancel_requested,
                .awaiter_delayed = list.awaiter_delayed,
                .fibers = .pack(new_head),
            }, .monotonic);
        } else if (@atomicLoad(Awaiter, group.awaiterPtr(), .monotonic).awaiter.unpack()) |awaiter| {
            if (!awaiter.cancel_status.changeAwaiting(.group, .nothing) or list.cancel_requested) {
                @atomicStore(List, list_ptr, .{
                    .cancel_requested = false,
                    .awaiter_delayed = false,
                    .fibers = .null,
                }, .release);
                assert(awaiter.status.awaiting_group.ptr == group.ptr);
                awaiter.status = .{ .queue_next = null };
                return awaiter;
            }
            // Race with `Fiber.requestCancel`
            @atomicStore(List, list_ptr, .{
                .cancel_requested = false,
                .awaiter_delayed = true,
                .fibers = .null,
            }, .monotonic);
        } else @atomicStore(List, list_ptr, .{
            .cancel_requested = false,
            .awaiter_delayed = false,
            .fibers = .null,
        }, .release);
        return null;
    }

    fn await(group: Group, ev: *Evented, awaiter: *Fiber) bool {
        group.lock(ev);
        defer group.unlock(ev);
        if (@atomicLoad(List, group.listPtr(), .monotonic).fibers.unpack()) |_| {
            if (group.registerAwaiter(awaiter) and awaiter.cancel_protection.check() == .unblocked) {
                // The awaiter already had an unacknowledged cancelation request before
                // attempting to await a group, so propagate the cancelation to the group.
                assert(!group.cancelLocked(ev, null));
            }
            return false;
        }
        return true;
    }

    fn cancel(group: Group, ev: *Evented, maybe_awaiter: ?*Fiber) bool {
        group.lock(ev);
        defer group.unlock(ev);
        return group.cancelLocked(ev, maybe_awaiter);
    }

    /// Assumes the mutex is held.
    fn cancelLocked(group: Group, ev: *Evented, maybe_awaiter: ?*Fiber) bool {
        const list_ptr = group.listPtr();
        const list = @atomicRmw(
            List,
            list_ptr,
            .Add,
            .{ .cancel_requested = true, .awaiter_delayed = false, .fibers = .null },
            .monotonic,
        );
        assert(!list.cancel_requested);
        if (list.fibers.unpack()) |head| {
            var maybe_fiber: ?*Fiber = head;
            while (maybe_fiber) |fiber| {
                fiber.requestCancel(ev);
                maybe_fiber = fiber.link.group.next;
            }
            if (maybe_awaiter) |awaiter| _ = group.registerAwaiter(awaiter);
            return false;
        }
        @atomicStore(
            List,
            list_ptr,
            .{ .cancel_requested = false, .awaiter_delayed = false, .fibers = .null },
            .release,
        );
        return if (maybe_awaiter) |_| true else list.awaiter_delayed;
    }

    /// Assumes the mutex is held.
    fn registerAwaiter(group: Group, awaiter: *Fiber) bool {
        assert(awaiter.status.queue_next == null);
        awaiter.status = .{ .awaiting_group = group };
        assert(@atomicRmw(
            Awaiter,
            group.awaiterPtr(),
            .Add,
            .{ .locked = false, .contended = false, .awaiter = .pack(awaiter) },
            .monotonic,
        ).awaiter == .null);
        return awaiter.cancel_status.changeAwaiting(.nothing, .group);
    }

    const AsyncClosure = struct {
        evented: *Evented,
        group: Group,
        fiber: *Fiber,
        start: *const fn (context: *const anyopaque) void,

        fn fromFiber(fiber: *Fiber) *Group.AsyncClosure {
            return @ptrFromInt(Fiber.max_context_align.max(.of(Group.AsyncClosure)).backward(
                @intFromPtr(fiber.allocatedEnd()) - Fiber.max_context_size,
            ) - @sizeOf(Group.AsyncClosure));
        }

        fn contextPointer(
            closure: *Group.AsyncClosure,
        ) [*]align(Fiber.max_context_align.toByteUnits()) u8 {
            return @alignCast(@as([*]u8, @ptrCast(closure)) + @sizeOf(Group.AsyncClosure));
        }

        fn entry() callconv(.naked) void {
            switch (builtin.cpu.arch) {
                .aarch64 => asm volatile (
                    \\ mov x0, sp
                    \\ b %[call]
                    :
                    : [call] "X" (&call),
                ),
                .riscv64 => asm volatile (
                    \\ mv a0, sp
                    \\ tail %[call]@plt
                    :
                    : [call] "X" (&call),
                ),
                .x86_64 => asm volatile (
                    \\ leaq 8(%%rsp), %%rdi
                    \\ jmp %[call:P]
                    :
                    : [call] "X" (&call),
                ),
                else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
            }
        }

        fn call(
            closure: *Group.AsyncClosure,
            message: *const SwitchMessage,
        ) callconv(.withStackAlign(.c, @alignOf(Group.AsyncClosure))) noreturn {
            const ev = closure.evented;
            const fiber = closure.fiber;
            message.handle(ev);
            assert(fiber.status.queue_next == null);
            closure.start(closure.contextPointer());
            ev.yield(closure.group.removeFiber(ev, fiber), .destroy);
            unreachable; // switched to dead fiber
        }
    };
};

fn groupAsync(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return groupConcurrent(ev, type_erased, context, context_alignment, start) catch {
        start(context.ptr);
    };
}

fn groupConcurrent(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) Io.ConcurrentError!void {
    assert(context_alignment.compare(.lte, Fiber.max_context_align)); // TODO
    assert(context.len <= Fiber.max_context_size); // TODO

    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const group: Group = .{ .ptr = type_erased };
    const fiber = Fiber.create(ev) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };

    const closure: *Group.AsyncClosure = .fromFiber(fiber);
    fiber.* = .{
        .required_align = {},
        .context = switch (builtin.cpu.arch) {
            .aarch64 => .{
                .sp = @intFromPtr(closure),
                .fp = 0,
                .pc = @intFromPtr(&Group.AsyncClosure.entry),
            },
            .riscv64 => .{
                .sp = @intFromPtr(closure),
                .fp = 0,
                .pc = @intFromPtr(&Group.AsyncClosure.entry),
            },
            .x86_64 => .{
                .rsp = @intFromPtr(closure) - 8,
                .rbp = 0,
                .rip = @intFromPtr(&Group.AsyncClosure.entry),
            },
            else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
        },
        .link = .{ .group = .{ .prev = null, .next = null } },
        .status = .{ .queue_next = null },
        .cancel_status = .unrequested,
        .cancel_protection = .unblocked,
        .name = if (tracy.enable) name: {
            const thread: *Thread = .current();
            var name_arena = thread.name_arena.promote(std.heap.page_allocator);
            defer thread.name_arena = name_arena.state;
            break :name std.fmt.allocPrintSentinel(
                name_arena.allocator(),
                "group task {d}",
                .{@atomicRmw(u64, &Fiber.next_name, .Add, 1, .monotonic)},
                0,
            ) catch return error.ConcurrencyUnavailable;
        },
    };
    closure.* = .{
        .evented = ev,
        .group = group,
        .fiber = fiber,
        .start = start,
    };
    @memcpy(closure.contextPointer(), context);
    group.addFiber(ev, fiber);
    const thread: *Thread = .current();
    if (ev.schedule(thread, .{ .head = fiber, .tail = fiber })) thread.submit();
}

fn groupAwait(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    initial_token: *anyopaque,
) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = initial_token;
    ev.yield(null, .{ .group_await = .{ .ptr = type_erased } });
}

fn groupCancel(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = initial_token;
    ev.yield(null, .{ .group_cancel = .{ .ptr = type_erased } });
}

fn recancel(userdata: ?*anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    Thread.current().currentFiber().cancel_protection.recancel();
}

fn swapCancelProtection(userdata: ?*anyopaque, new: Io.CancelProtection) Io.CancelProtection {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const cancel_protection = &Thread.current().currentFiber().cancel_protection;
    defer cancel_protection.user = new;
    return cancel_protection.user;
}

fn checkCancel(userdata: ?*anyopaque) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const fiber = Thread.current().currentFiber();
    switch (fiber.cancel_protection.check()) {
        .unblocked => {
            const cancel_status = @atomicLoad(Fiber.CancelStatus, &fiber.cancel_status, .monotonic);
            assert(cancel_status.awaiting == .nothing);
            if (cancel_status.requested) {
                @branchHint(.unlikely);
                fiber.cancel_protection.acknowledge();
                return error.Canceled;
            }
        },
        .blocked => {},
    }
}

fn futexWait(
    userdata: ?*anyopaque,
    ptr: *const u32,
    expected: u32,
    timeout: Io.Timeout,
) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const timespec: ?linux.kernel_timespec, const clock: Io.Clock, const timeout_flags: u32 = timespec: switch (timeout) {
        .none => .{
            null,
            .awake,
            linux.IORING_TIMEOUT_ABS,
        },
        .duration => |duration| {
            const ns = duration.raw.toNanoseconds();
            break :timespec .{
                .{
                    .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                    .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                },
                duration.clock,
                0,
            };
        },
        .deadline => |deadline| {
            const ns = deadline.raw.toNanoseconds();
            break :timespec .{
                .{
                    .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                    .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                },
                deadline.clock,
                linux.IORING_TIMEOUT_ABS,
            };
        },
    };
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    const thread = try cancel_region.awaitIoUring();
    thread.enqueue().* = .{
        .opcode = .FUTEX_WAIT,
        .flags = if (timespec) |_| linux.IOSQE_IO_LINK else 0,
        .ioprio = 0,
        .fd = @bitCast(linux.FUTEX2_FLAGS{ .size = .U32, .private = true }),
        .off = expected,
        .addr = @intFromPtr(ptr),
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromPtr(cancel_region.fiber),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = std.math.maxInt(u32),
        .resv = 0,
    };
    if (timespec) |*timespec_ptr| thread.enqueue().* = .{
        .opcode = .LINK_TIMEOUT,
        .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
        .ioprio = 0,
        .fd = 0,
        .off = 0,
        .addr = @intFromPtr(timespec_ptr),
        .len = 1,
        .rw_flags = timeout_flags | @as(u32, switch (clock) {
            .real => linux.IORING_TIMEOUT_REALTIME,
            else => 0,
            .boot => linux.IORING_TIMEOUT_BOOTTIME,
        }),
        .user_data = @intFromEnum(Completion.Userdata.wakeup),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    };
    ev.yield(null, .nothing);
    switch (cancel_region.errno()) {
        .SUCCESS => {}, // notified by `wake()`
        .INTR, .CANCELED => {}, // caller's responsibility to retry
        .AGAIN => {}, // ptr.* != expect
        .INVAL => {}, // possibly timeout overflow
        .TIMEDOUT => unreachable,
        .FAULT => recoverableOsBugDetected(), // ptr was invalid
        else => recoverableOsBugDetected(),
    }
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .initBlocked();
    defer cancel_region.deinit();
    const thread = cancel_region.awaitIoUring() catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    };
    thread.enqueue().* = .{
        .opcode = .FUTEX_WAIT,
        .flags = 0,
        .ioprio = 0,
        .fd = @bitCast(linux.FUTEX2_FLAGS{ .size = .U32, .private = true }),
        .off = expected,
        .addr = @intFromPtr(ptr),
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromPtr(cancel_region.fiber),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = std.math.maxInt(u32),
        .resv = 0,
    };
    ev.yield(null, .nothing);
    switch (cancel_region.errno()) {
        .SUCCESS => {}, // notified by `wake()`
        .INTR, .CANCELED => {}, // caller's responsibility to retry
        .AGAIN => {}, // ptr.* != expect
        .INVAL => {}, // possibly timeout overflow
        .FAULT => recoverableOsBugDetected(), // ptr was invalid
        else => recoverableOsBugDetected(),
    }
}

fn futexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const thread: *Thread = .current();
    thread.enqueue().* = .{
        .opcode = .FUTEX_WAKE,
        .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
        .ioprio = 0,
        .fd = @bitCast(linux.FUTEX2_FLAGS{ .size = .U32, .private = true }),
        .off = max_waiters,
        .addr = @intFromPtr(ptr),
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromEnum(Completion.Userdata.futex_wake),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = std.math.maxInt(u32),
        .resv = 0,
    };
    thread.submit();
}

fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    return switch (operation) {
        .file_read_streaming => |o| .{
            .file_read_streaming = ev.fileReadStreaming(
                &maybe_sync.cancel_region,
                o.file,
                o.data,
            ) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .file_write_streaming => |o| .{
            .file_write_streaming = ev.fileWriteStreaming(
                &maybe_sync.cancel_region,
                o.file,
                o.header,
                o.data,
                o.splat,
            ) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .device_io_control => |o| .{
            .device_io_control = try ev.deviceIoControl(try maybe_sync.enterSync(ev), o),
        },
        .net_receive => |o| .{
            .net_receive = r: {
                const opt_err, const n = ev.netReceive(&maybe_sync.cancel_region, o.socket_handle, o.message_buffer, o.data_buffer, o.flags);
                break :r .{
                    if (opt_err) |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| e,
                    } else null,
                    n,
                };
            },
        },
    };
}

fn fileReadStreaming(
    ev: *Evented,
    cancel_region: *CancelRegion,
    file: File,
    data: []const []u8,
) File.ReadStreamingError!usize {
    var iovecs_buffer: [max_iovecs_len]iovec = undefined;
    var i: usize = 0;
    for (data) |buf| {
        if (iovecs_buffer.len - i == 0) break;
        if (buf.len > 0) {
            iovecs_buffer[i] = .{ .base = buf.ptr, .len = buf.len };
            i += 1;
        }
    }
    const dest = iovecs_buffer[0..i];
    assert(dest[0].len > 0);

    const n = try ev.preadv(cancel_region, file.handle, dest, null);
    return if (n == 0) error.EndOfStream else n;
}

fn fileWriteStreaming(
    ev: *Evented,
    cancel_region: *CancelRegion,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) File.Writer.Error!usize {
    var iovecs: [max_iovecs_len]iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    addBuf(&iovecs, &iovlen, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(&iovecs, &iovlen, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0) switch (splat) {
        0 => {},
        1 => addBuf(&iovecs, &iovlen, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addBuf(&iovecs, &iovlen, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and iovecs.len - iovlen != 0) {
                    assert(buf.len == splat_buffer.len);
                    addBuf(&iovecs, &iovlen, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addBuf(&iovecs, &iovlen, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - iovlen)) |_| {
                addBuf(&iovecs, &iovlen, pattern);
            },
        },
    };
    return ev.pwritev(cancel_region, file.handle, iovecs[0..iovlen], null);
}

fn deviceIoControl(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    o: Io.Operation.DeviceIoControl,
) Io.Cancelable!i32 {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        const rc = linux.ioctl(o.file.handle, @bitCast(o.code), @intFromPtr(o.arg));
        switch (linux.errno(rc)) {
            .SUCCESS => return @bitCast(@as(u32, @truncate(rc))),
            .INTR => {},
            else => |err| return -@as(i32, @intFromEnum(err)),
        }
    }
}

fn batchAwaitAsync(userdata: ?*anyopaque, batch: *Io.Batch) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    ev.batchDrainSubmitted(&maybe_sync, batch, false) catch |err| switch (err) {
        error.ConcurrencyUnavailable => unreachable, // passed concurrency=false
        error.Canceled => |e| return e,
    };
    maybe_sync.leaveSync(ev);
    while (true) {
        batchDrainReady(batch) catch |err| switch (err) {
            error.Timeout => unreachable, // no timeout
        };
        if (batch.completed.head != .none or batch.pending.head == .none) return;
        ev.yield(null, .{ .batch_await = batch });
    }
}

fn batchAwaitConcurrent(
    userdata: ?*anyopaque,
    batch: *Io.Batch,
    timeout: Io.Timeout,
) Io.Batch.AwaitConcurrentError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    try ev.batchDrainSubmitted(&maybe_sync, batch, true);
    maybe_sync.leaveSync(ev);
    const timespec: linux.kernel_timespec, const clock: Io.Clock, const timeout_flags: u32 = while (true) {
        batchDrainReady(batch) catch |err| switch (err) {
            error.Timeout => unreachable, // no timeout
        };
        if (batch.completed.head != .none or batch.pending.head == .none) return;
        switch (timeout) {
            .none => ev.yield(null, .{ .batch_await = batch }),
            .duration => |duration| {
                const ns = duration.raw.toNanoseconds();
                break .{
                    .{
                        .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                        .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                    },
                    duration.clock,
                    0,
                };
            },
            .deadline => |deadline| {
                const ns = deadline.raw.toNanoseconds();
                break .{
                    .{
                        .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                        .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                    },
                    deadline.clock,
                    linux.IORING_TIMEOUT_ABS,
                };
            },
        }
    };
    {
        const thread = try maybe_sync.cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .TIMEOUT,
            .flags = 0,
            .ioprio = 0,
            .fd = 0,
            .off = 0,
            .addr = @intFromPtr(&timespec),
            .len = 1,
            .rw_flags = timeout_flags | @as(u32, switch (clock) {
                .real => linux.IORING_TIMEOUT_REALTIME,
                else => 0,
                .boot => linux.IORING_TIMEOUT_BOOTTIME,
            }),
            .user_data = @intFromPtr(&batch.userdata) | 0b11,
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
    }
    while (batch.completed.head == .none and batch.pending.head != .none) {
        ev.yield(null, .{ .batch_await = batch });
        batchDrainReady(batch) catch |err| switch (err) {
            error.Timeout => |e| return if (batch.completed.head == .none and
                batch.pending.head != .none) e,
        };
    }
    const thread = try maybe_sync.cancel_region.awaitIoUring();
    thread.enqueue().* = .{
        .opcode = .TIMEOUT_REMOVE,
        .flags = 0,
        .ioprio = 0,
        .fd = 0,
        .off = 0,
        .addr = @intFromPtr(&batch.userdata) | 0b11,
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromPtr(maybe_sync.cancel_region.fiber),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    };
    ev.yield(null, .nothing);
    switch (maybe_sync.cancel_region.errno()) {
        .SUCCESS => return,
        .BUSY, .NOENT => {},
        else => |err| unexpectedErrno(err) catch {},
    }
    while (true) {
        batchDrainReady(batch) catch |err| switch (err) {
            error.Timeout => return,
        };
        ev.yield(null, .{ .batch_await = batch });
    }
}

/// If `concurrency` is false, `error.ConcurrencyUnavailable` is unreachable.
fn batchDrainSubmitted(
    ev: *Evented,
    maybe_sync: *CancelRegion.Sync.Maybe,
    batch: *Io.Batch,
    concurrency: bool,
) (Io.ConcurrentError || Io.Cancelable)!void {
    var index = batch.submitted.head;
    if (index == .none) return;
    const thread = try maybe_sync.cancelRegion().awaitIoUring();
    errdefer batch.submitted.head = index;
    while (index != .none) {
        const storage = &batch.storage[index.toIndex()];
        const next_index = storage.submission.node.next;
        if (@as(?Io.Operation.Result, result: switch (storage.submission.operation) {
            .file_read_streaming => |o| {
                const buffer = for (o.data) |buffer| {
                    if (buffer.len > 0) break buffer;
                } else break :result .{ .file_read_streaming = 0 };
                const fd = o.file.handle;
                storage.* = .{ .pending = .{
                    .node = .{ .prev = batch.pending.tail, .next = .none },
                    .tag = .file_read_streaming,
                    .userdata = undefined,
                } };
                thread.enqueue().* = .{
                    .opcode = .READ,
                    .flags = 0,
                    .ioprio = 0,
                    .fd = fd,
                    .off = std.math.maxInt(u64),
                    .addr = @intFromPtr(buffer.ptr),
                    .len = @min(buffer.len, 0xfffff000),
                    .rw_flags = 0,
                    .user_data = @intFromPtr(&storage.pending.userdata) | 0b10,
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                };
                break :result null;
            },
            .file_write_streaming => |o| {
                const buffer = buffer: {
                    if (o.header.len != 0) break :buffer o.header;
                    for (o.data[0 .. o.data.len - 1]) |buffer| {
                        if (buffer.len > 0) break :buffer buffer;
                    }
                    if (o.splat > 0) break :buffer o.data[o.data.len - 1];
                    break :result .{ .file_write_streaming = 0 };
                };
                const fd = o.file.handle;
                storage.* = .{ .pending = .{
                    .node = .{ .prev = batch.pending.tail, .next = .none },
                    .tag = .file_write_streaming,
                    .userdata = undefined,
                } };
                thread.enqueue().* = .{
                    .opcode = .WRITE,
                    .flags = 0,
                    .ioprio = 0,
                    .fd = fd,
                    .off = std.math.maxInt(u64),
                    .addr = @intFromPtr(buffer.ptr),
                    .len = @min(buffer.len, 0xfffff000),
                    .rw_flags = 0,
                    .user_data = @intFromPtr(&storage.pending.userdata) | 0b10,
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                };
                break :result null;
            },
            .device_io_control => |o| if (concurrency)
                return error.ConcurrencyUnavailable
            else
                .{ .device_io_control = try ev.deviceIoControl(try maybe_sync.enterSync(ev), o) },
            .net_receive => |o| {
                _ = o;
                @panic("TODO implement batchDrainSubmitted for net_receive");
            },
        })) |result| {
            switch (batch.completed.tail) {
                .none => batch.completed.head = index,
                else => |tail_index| batch.storage[tail_index.toIndex()].completion.node.next = index,
            }
            batch.completed.tail = index;
            storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
        } else {
            switch (batch.pending.tail) {
                .none => batch.pending.head = index,
                else => |tail_index| batch.storage[tail_index.toIndex()].pending.node.next = index,
            }
            batch.pending.tail = index;
            storage.pending.userdata[0] = @intFromPtr(batch);
        }
        index = next_index;
    }
    batch.submitted = .{ .head = .none, .tail = .none };
}

fn batchDrainReady(batch: *Io.Batch) Io.Timeout.Error!void {
    while (@atomicRmw(?*anyopaque, &batch.userdata, .Xchg, null, .acquire)) |head| {
        var next: usize = @intFromPtr(head);
        var timeout = false;
        while (cond: switch (@as(u2, @truncate(next))) {
            0b00 => if (timeout) return error.Timeout else false,
            0b01 => {
                assert(!timeout);
                return error.Timeout;
            },
            0b10 => true,
            0b11 => {
                assert(!timeout);
                timeout = true;
                break :cond true;
            },
        }) {
            const operation_userdata: *Io.Operation.Storage.Pending.Userdata =
                @ptrFromInt(next & ~@as(usize, 0b11));
            next = operation_userdata[0];
            const completion: Completion = .{
                .result = @bitCast(@as(u32, @intCast(operation_userdata[1]))),
                .flags = @intCast(operation_userdata[2]),
            };
            const pending: *Io.Operation.Storage.Pending =
                @fieldParentPtr("userdata", operation_userdata);
            const storage: *Io.Operation.Storage = @fieldParentPtr("pending", pending);
            const index: Io.Operation.OptionalIndex = .fromIndex(storage - batch.storage.ptr);
            assert(completion.flags & linux.IORING_CQE_F_SKIP == 0);
            switch (pending.node.prev) {
                .none => batch.pending.head = pending.node.next,
                else => |prev_index| batch.storage[prev_index.toIndex()].pending.node.next =
                    pending.node.next,
            }
            switch (pending.node.next) {
                .none => batch.pending.tail = pending.node.prev,
                else => |prev_index| batch.storage[prev_index.toIndex()].pending.node.prev =
                    pending.node.prev,
            }
            if (@as(?Io.Operation.Result, result: switch (pending.tag) {
                .file_read_streaming => .{
                    .file_read_streaming = switch (completion.errno()) {
                        .SUCCESS => @as(u32, @bitCast(completion.result)),
                        .INTR => 0,
                        .CANCELED => break :result null,
                        .INVAL => |err| errnoBug(err),
                        .FAULT => |err| errnoBug(err),
                        .AGAIN => error.WouldBlock,
                        .BADF => |err| errnoBug(err), // File descriptor used after closed
                        .IO => error.InputOutput,
                        .ISDIR => error.IsDir,
                        .NOBUFS => error.SystemResources,
                        .NOMEM => error.SystemResources,
                        .NOTCONN => error.SocketUnconnected,
                        .CONNRESET => error.ConnectionResetByPeer,
                        else => |err| unexpectedErrno(err),
                    },
                },
                .file_write_streaming => .{
                    .file_write_streaming = switch (completion.errno()) {
                        .SUCCESS => @as(u32, @bitCast(completion.result)),
                        .INTR => 0,
                        .CANCELED => break :result null,
                        .INVAL => |err| errnoBug(err),
                        .FAULT => |err| errnoBug(err),
                        .AGAIN => error.WouldBlock,
                        .BADF => error.NotOpenForWriting, // Can be a race condition.
                        .DESTADDRREQ => |err| errnoBug(err), // `connect` was never called.
                        .DQUOT => error.DiskQuota,
                        .FBIG => error.FileTooBig,
                        .IO => error.InputOutput,
                        .NOSPC => error.NoSpaceLeft,
                        .PERM => error.PermissionDenied,
                        .PIPE => error.BrokenPipe,
                        .CONNRESET => |err| errnoBug(err), // Not a socket handle.
                        .BUSY => error.DeviceBusy,
                        else => |err| unexpectedErrno(err),
                    },
                },
                .device_io_control => unreachable,
                .net_receive => @panic("TODO"),
            })) |result| {
                switch (batch.completed.tail) {
                    .none => batch.completed.head = index,
                    else => |tail_index| batch.storage[tail_index.toIndex()].completion.node.next =
                        index,
                }
                storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
                batch.completed.tail = index;
            } else {
                switch (batch.unused.tail) {
                    .none => batch.unused.head = index,
                    else => |tail_index| batch.storage[tail_index.toIndex()].unused.next = index,
                }
                storage.* = .{ .unused = .{ .prev = batch.unused.tail, .next = .none } };
                batch.unused.tail = index;
            }
        }
    }
}

fn batchCancel(userdata: ?*anyopaque, batch: *Io.Batch) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    batchDrainReady(batch) catch |err| switch (err) {
        error.Timeout => unreachable, // no timeout
    };
    var index = batch.pending.head;
    if (index == .none) return;
    var cancel_region: CancelRegion = .initBlocked();
    defer cancel_region.deinit();
    const thread = cancel_region.awaitIoUring() catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    };
    while (index != .none) {
        const pending = &batch.storage[index.toIndex()].pending;
        thread.enqueue().* = .{
            .opcode = .ASYNC_CANCEL,
            .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
            .ioprio = 0,
            .fd = 0,
            .off = 0,
            .addr = @intFromPtr(&pending.userdata) | 0b10,
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromEnum(Completion.Userdata.wakeup),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        index = pending.node.next;
    }
    while (batch.pending.head != .none) batchDrainReady(batch) catch |err| switch (err) {
        error.Timeout => unreachable, // no timeout
    };
}

fn dirCreateDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .MKDIRAT,
            .flags = 0,
            .ioprio = 0,
            .fd = dir.handle,
            .off = 0,
            .addr = @intFromPtr(sub_path_posix.ptr),
            .len = permissions.toMode(),
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .ACCES => return error.AccessDenied,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .PERM => return error.PermissionDenied,
            .DQUOT => return error.DiskQuota,
            .EXIST => return error.PathAlreadyExists,
            .FAULT => |err| return errnoBug(err),
            .LOOP => return error.SymLinkLoop,
            .MLINK => return error.LinkQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .ROFS => return error.ReadOnlyFileSystem,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirCreateDirPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirPathError!Dir.CreatePathStatus {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var it = Dir.path.componentIterator(sub_path);
    var status: Dir.CreatePathStatus = .existed;
    var component = it.last() orelse return error.BadPathName;
    while (true) {
        if (dirCreateDir(ev, dir, component.path, permissions)) |_| {
            status = .created;
        } else |err| switch (err) {
            error.PathAlreadyExists => {
                // stat the file and return an error if it's not a directory
                // this is important because otherwise a dangling symlink
                // could cause an infinite loop
                const kind = try ev.filePathKind(dir, component.path);
                if (kind != .directory) return error.NotDir;
            },
            error.FileNotFound => |e| {
                component = it.previous() orelse return e;
                continue;
            },
            else => |e| return e,
        }
        component = it.next() orelse return status;
    }
}

fn filePathKind(ev: *Evented, dir: Dir, sub_path: []const u8) !File.Kind {
    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        var statx_buf = std.mem.zeroes(linux.Statx);
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .STATX,
            .flags = 0,
            .ioprio = 0,
            .fd = dir.handle,
            .off = @intFromPtr(&statx_buf),
            .addr = @intFromPtr(sub_path_posix.ptr),
            .len = @bitCast(linux.STATX{ .TYPE = true }),
            .rw_flags = linux.AT.NO_AUTOMOUNT | linux.AT.SYMLINK_NOFOLLOW,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => {
                if (!statx_buf.mask.TYPE) return error.Unexpected;
                return statxKind(statx_buf.mode);
            },
            .INTR, .CANCELED => {},
            .ACCES => |err| return errnoBug(err),
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .LOOP => |err| return errnoBug(err),
            .NAMETOOLONG => |err| return errnoBug(err),
            .NOENT => |err| return errnoBug(err),
            .NOMEM => return error.SystemResources,
            .NOTDIR => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirCreateDirPathOpen(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return dirOpenDir(ev, dir, sub_path, options) catch |err| switch (err) {
        error.FileNotFound => {
            _ = try dirCreateDirPath(ev, dir, sub_path, permissions);
            return dirOpenDir(ev, dir, sub_path, options);
        },
        else => |e| return e,
    };
}

fn dirOpenDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return .{
        .handle = ev.openat(&cancel_region, dir.handle, sub_path_posix, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .NOFOLLOW = !options.follow_symlinks,
            .CLOEXEC = true,
            .PATH = !options.iterate,
        }, 0) catch |err| switch (err) {
            error.IsDir => return errnoBug(.ISDIR),
            error.WouldBlock => return errnoBug(.AGAIN),
            error.FileTooBig => return errnoBug(.FBIG),
            error.NoSpaceLeft => return errnoBug(.NOSPC),
            error.DeviceBusy => return errnoBug(.BUSY), // EXCL unset.
            error.FileBusy => return errnoBug(.TXTBSY),
            error.PathAlreadyExists => return errnoBug(.EXIST), // Not creating.
            error.OperationUnsupported => return errnoBug(.OPNOTSUPP), // No TMPFILE, no locks.
            else => |e| return e,
        },
    };
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.stat(&cancel_region, dir.handle);
}

fn dirStatFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.statx(&cancel_region, dir.handle, sub_path_posix, linux.AT.NO_AUTOMOUNT |
        @as(u32, if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW));
}

fn dirAccess(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const mode: u32 =
        @as(u32, if (options.read) linux.R_OK else 0) |
        @as(u32, if (options.write) linux.W_OK else 0) |
        @as(u32, if (options.execute) linux.X_OK else 0);
    const flags: u32 = if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW;

    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.faccessat(dir.handle, sub_path_posix, mode, flags))) {
            .SUCCESS => return,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .ROFS => return error.ReadOnlyFileSystem,
            .LOOP => return error.SymLinkLoop,
            .TXTBSY => return error.FileBusy,
            .NOTDIR => return error.FileNotFound,
            .NOENT => return error.FileNotFound,
            .NAMETOOLONG => return error.NameTooLong,
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .IO => return error.InputOutput,
            .NOMEM => return error.SystemResources,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirCreateFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: File.CreateFlags,
) File.OpenError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    const fd = ev.openat(&maybe_sync.cancel_region, dir.handle, sub_path_posix, .{
        .ACCMODE = if (flags.read) .RDWR else .WRONLY,
        .CREAT = true,
        .TRUNC = flags.truncate,
        .EXCL = flags.exclusive,
        .CLOEXEC = true,
    }, flags.permissions.toMode()) catch |err| switch (err) {
        error.OperationUnsupported => return error.Unexpected, // TMPFILE unset.
        else => |e| return e,
    };
    errdefer ev.closeAsync(fd);

    switch (flags.lock) {
        .none => {},
        .shared, .exclusive => try ev.flock(
            try maybe_sync.enterSync(ev),
            fd,
            flags.lock,
            if (flags.lock_nonblocking) .nonblocking else .blocking,
        ),
    }

    return .{ .handle = fd, .flags = .{ .nonblocking = false } };
}

fn dirCreateFileAtomic(
    userdata: ?*anyopaque,
    dir: Dir,
    dest_path: []const u8,
    options: Dir.CreateFileAtomicOptions,
) Dir.CreateFileAtomicError!File.Atomic {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    // Linux has O_TMPFILE, but linkat() does not support AT_REPLACE, so it's
    // useless when we have to make up a bogus path name to do the rename()
    // anyway.
    if (!options.replace) tmpfile: {
        const flags: linux.O = if (@hasField(linux.O, "TMPFILE")) .{
            .ACCMODE = .RDWR,
            .TMPFILE = true,
            .DIRECTORY = true,
            .CLOEXEC = true,
        } else if (@hasField(linux.O, "TMPFILE0") and !@hasField(linux.O, "TMPFILE2")) .{
            .ACCMODE = .RDWR,
            .TMPFILE0 = true,
            .TMPFILE1 = true,
            .DIRECTORY = true,
            .CLOEXEC = true,
        } else break :tmpfile;

        const dest_dirname = Dir.path.dirname(dest_path);
        if (dest_dirname) |dirname| {
            // This has a nice side effect of preemptively triggering EISDIR or
            // ENOENT, avoiding the ambiguity below.
            _ = dirCreateDirPath(ev, dir, dirname, .default_dir) catch |err| switch (err) {
                // None of these make sense in this context.
                error.IsDir,
                error.Streaming,
                error.DiskQuota,
                error.PathAlreadyExists,
                error.LinkQuotaExceeded,
                error.PipeBusy,
                error.FileTooBig,
                error.DeviceBusy,
                error.FileLocksUnsupported,
                error.FileBusy,
                => return error.Unexpected,

                else => |e| return e,
            };
        }

        var path_buffer: [PATH_MAX]u8 = undefined;
        const sub_path_posix = try pathToPosix(dest_dirname orelse ".", &path_buffer);

        var cancel_region: CancelRegion = .init();
        defer cancel_region.deinit();
        return .{
            .file = .{
                .handle = ev.openat(
                    &cancel_region,
                    dir.handle,
                    sub_path_posix,
                    flags,
                    options.permissions.toMode(),
                ) catch |err| switch (err) {
                    error.IsDir, error.FileNotFound, error.OperationUnsupported => {
                        // Ambiguous error code. It might mean the file system
                        // does not support O_TMPFILE. Therefore, we must fall
                        // back to not using O_TMPFILE.
                        break :tmpfile;
                    },
                    error.FileTooBig => return errnoBug(.FBIG),
                    error.DeviceBusy => return errnoBug(.BUSY), // O_EXCL not passed
                    error.PathAlreadyExists => return errnoBug(.EXIST), // Not creating.
                    else => |e| return e,
                },
                .flags = .{ .nonblocking = false },
            },
            .file_basename_hex = 0,
            .dest_sub_path = dest_path,
            .file_open = true,
            .file_exists = false,
            .close_dir_on_deinit = false,
            .dir = dir,
        };
    }

    if (Dir.path.dirname(dest_path)) |dirname| {
        const new_dir = if (options.make_path)
            dirCreateDirPathOpen(ev, dir, dirname, .default_dir, .{}) catch |err| switch (err) {
                // None of these make sense in this context.
                error.IsDir,
                error.Streaming,
                error.DiskQuota,
                error.PathAlreadyExists,
                error.LinkQuotaExceeded,
                error.PipeBusy,
                error.FileTooBig,
                error.FileLocksUnsupported,
                error.DeviceBusy,
                => return error.Unexpected,

                else => |e| return e,
            }
        else
            try dirOpenDir(ev, dir, dirname, .{});

        return ev.atomicFileInit(Dir.path.basename(dest_path), options.permissions, new_dir, true);
    }

    return ev.atomicFileInit(dest_path, options.permissions, dir, false);
}

fn atomicFileInit(
    ev: *Evented,
    dest_basename: []const u8,
    permissions: File.Permissions,
    dir: Dir,
    close_dir_on_deinit: bool,
) Dir.CreateFileAtomicError!File.Atomic {
    while (true) {
        var random_integer: u64 = undefined;
        random(ev, @ptrCast(&random_integer));
        const tmp_sub_path = std.fmt.hex(random_integer);
        const file = dirCreateFile(ev, dir, &tmp_sub_path, .{
            .permissions = permissions,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.DeviceBusy => continue,
            error.FileBusy => continue,

            error.IsDir => return error.Unexpected, // No path components.
            error.FileTooBig => return error.Unexpected, // Creating, not opening.
            error.FileLocksUnsupported => return error.Unexpected, // Not asking for locks.
            error.PipeBusy => return error.Unexpected, // Not opening a pipe.

            else => |e| return e,
        };
        return .{
            .file = file,
            .file_basename_hex = random_integer,
            .dest_sub_path = dest_basename,
            .file_open = true,
            .file_exists = true,
            .close_dir_on_deinit = close_dir_on_deinit,
            .dir = dir,
        };
    }
}

fn dirOpenFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: File.OpenFlags,
) File.OpenError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    const fd = ev.openat(&maybe_sync.cancel_region, dir.handle, sub_path_posix, .{
        .ACCMODE = switch (flags.mode) {
            .read_only => .RDONLY,
            .write_only => .WRONLY,
            .read_write => .RDWR,
        },
        .NOCTTY = !flags.allow_ctty,
        .NOFOLLOW = !flags.follow_symlinks,
        .CLOEXEC = true,
        .PATH = flags.path_only,
    }, 0) catch |err| switch (err) {
        error.OperationUnsupported => return error.Unexpected, // TMPFILE unset.
        else => |e| return e,
    };
    errdefer ev.closeAsync(fd);

    if (!flags.allow_directory) {
        const is_dir = is_dir: {
            const s = ev.stat(&maybe_sync.cancel_region, fd) catch |err| switch (err) {
                // The directory-ness is either unknown or unknowable
                error.Streaming => break :is_dir false,
                else => |e| return e,
            };
            break :is_dir s.kind == .directory;
        };
        if (is_dir) return error.IsDir;
    }

    switch (flags.lock) {
        .none => {},
        .shared, .exclusive => try ev.flock(
            try maybe_sync.enterSync(ev),
            fd,
            flags.lock,
            if (flags.lock_nonblocking) .nonblocking else .blocking,
        ),
    }

    return .{ .handle = fd, .flags = .{ .nonblocking = false } };
}

fn dirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    for (dirs) |dir| ev.close(dir.handle);
}

fn dirRead(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            var sync: CancelRegion.Sync = try .init(ev);
            defer sync.deinit(ev);
            if (dr.state == .reset) {
                ev.lseek(&sync, dr.dir.handle, 0, linux.SEEK.SET) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const n = while (true) {
                try sync.cancel_region.await(.nothing);
                const rc = linux.getdents64(dr.dir.handle, dr.buffer.ptr, dr.buffer.len);
                switch (linux.errno(rc)) {
                    .SUCCESS => break rc,
                    .INTR => {},
                    .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability.
                    .FAULT => |err| return errnoBug(err),
                    .NOTDIR => |err| return errnoBug(err),
                    // To be consistent across platforms, iteration
                    // ends if the directory being iterated is deleted
                    // during iteration. This matches the behavior of
                    // non-Linux, non-WASI UNIX platforms.
                    .NOENT => {
                        dr.state = .finished;
                        return 0;
                    },
                    // This can occur when reading /proc/$PID/net, or
                    // if the provided buffer is too small. Neither
                    // scenario is intended to be handled by this API.
                    .INVAL => return error.Unexpected,
                    .ACCES => return error.AccessDenied, // Lacking permission to iterate this directory.
                    else => |err| return unexpectedErrno(err),
                }
            };
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = 0;
            dr.end = n;
        }
        // Linux aligns the header by padding after the null byte of the name
        // to align the next entry. This means we can find the end of the name
        // by looking at only the 8 bytes before the next record. However since
        // file names are usually short it's better to keep the machine code
        // simpler.
        //
        // Furthermore, I observed qemu user mode to not align this struct, so
        // this code makes the conservative choice to not assume alignment.
        const linux_entry: *align(1) linux.dirent64 = @ptrCast(&dr.buffer[dr.index]);
        const next_index = dr.index + linux_entry.reclen;
        dr.index = next_index;
        const name_ptr: [*]u8 = &linux_entry.name;
        const padded_name = name_ptr[0 .. linux_entry.reclen - @offsetOf(linux.dirent64, "name")];
        const name_len = std.mem.findScalar(u8, padded_name, 0).?;
        const name = name_ptr[0..name_len :0];

        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const entry_kind: File.Kind = switch (linux_entry.type) {
            linux.DT.BLK => .block_device,
            linux.DT.CHR => .character_device,
            linux.DT.DIR => .directory,
            linux.DT.FIFO => .named_pipe,
            linux.DT.LNK => .sym_link,
            linux.DT.REG => .file,
            linux.DT.SOCK => .unix_domain_socket,
            else => .unknown,
        };
        buffer[buffer_index] = .{
            .name = name,
            .kind = entry_kind,
            .inode = linux_entry.ino,
        };
        buffer_index += 1;
    }
    return buffer_index;
}

fn dirRealPath(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    return ev.realPath(&sync, dir.handle, out_buffer);
}

fn dirRealPathFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    out_buffer: []u8,
) Dir.RealPathFileError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    const fd = ev.openat(&maybe_sync.cancel_region, dir.handle, sub_path_posix, .{
        .CLOEXEC = true,
        .PATH = true,
    }, 0) catch |err| switch (err) {
        error.WouldBlock => return errnoBug(.AGAIN),
        error.OperationUnsupported => return errnoBug(.OPNOTSUPP), // Not asking for locks.
        else => |e| return e,
    };
    defer ev.closeAsync(fd);
    return ev.realPath(try maybe_sync.enterSync(ev), fd, out_buffer);
}

fn dirDeleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .UNLINKAT,
            .flags = 0,
            .ioprio = 0,
            .fd = dir.handle,
            .off = 0,
            .addr = @intFromPtr(sub_path_posix.ptr),
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .PERM => return error.PermissionDenied,
            .ACCES => return error.AccessDenied,
            .BUSY => return error.FileBusy,
            .FAULT => |err| return errnoBug(err),
            .IO => return error.FileSystem,
            .ISDIR => return error.IsDir,
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            .ROFS => return error.ReadOnlyFileSystem,
            .EXIST => |err| return errnoBug(err),
            .NOTEMPTY => |err| return errnoBug(err), // Not passing AT.REMOVEDIR
            .ILSEQ => return error.BadPathName,
            .INVAL => |err| return errnoBug(err), // invalid flags, or pathname has . as last component
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirDeleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .UNLINKAT,
            .flags = 0,
            .ioprio = 0,
            .fd = dir.handle,
            .off = 0,
            .addr = @intFromPtr(sub_path_posix.ptr),
            .len = 0,
            .rw_flags = linux.AT.REMOVEDIR,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .BUSY => return error.FileBusy,
            .FAULT => |err| return errnoBug(err),
            .IO => return error.FileSystem,
            .ISDIR => |err| return errnoBug(err),
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            .ROFS => return error.ReadOnlyFileSystem,
            .EXIST => |err| return errnoBug(err),
            .NOTEMPTY => return error.DirNotEmpty,
            .ILSEQ => return error.BadPathName,
            .INVAL => |err| return errnoBug(err), // invalid flags, or pathname has . as last component
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirRename(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var old_path_buffer: [PATH_MAX]u8 = undefined;
    var new_path_buffer: [PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.renameat(
        &cancel_region,
        old_dir.handle,
        old_sub_path_posix,
        new_dir.handle,
        new_sub_path_posix,
        .{},
    );
}

fn dirRenamePreserve(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var old_path_buffer: [PATH_MAX]u8 = undefined;
    var new_path_buffer: [PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.renameat(
        &cancel_region,
        old_dir.handle,
        old_sub_path_posix,
        new_dir.handle,
        new_sub_path_posix,
        .{ .NOREPLACE = true },
    );
}

fn dirSymLink(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = flags;

    var target_path_buffer: [PATH_MAX]u8 = undefined;
    var sym_link_path_buffer: [PATH_MAX]u8 = undefined;

    const target_path_posix = try pathToPosix(target_path, &target_path_buffer);
    const sym_link_path_posix = try pathToPosix(sym_link_path, &sym_link_path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .SYMLINKAT,
            .flags = 0,
            .ioprio = 0,
            .fd = dir.handle,
            .off = @intFromPtr(sym_link_path_posix.ptr),
            .addr = @intFromPtr(target_path_posix.ptr),
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .DQUOT => return error.DiskQuota,
            .EXIST => return error.PathAlreadyExists,
            .IO => return error.FileSystem,
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .ROFS => return error.ReadOnlyFileSystem,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirReadLink(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    buffer: []u8,
) Dir.ReadLinkError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var sub_path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &sub_path_buffer);

    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    while (true) {
        try sync.cancel_region.await(.nothing);
        const rc = linux.readlinkat(dir.handle, sub_path_posix, buffer.ptr, buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => return @bitCast(rc),
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .FAULT => |err| return errnoBug(err),
            .INVAL => return error.NotLink,
            .IO => return error.FileSystem,
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.NotDir,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirSetOwner(
    userdata: ?*anyopaque,
    dir: Dir,
    owner: ?File.Uid,
    group: ?File.Gid,
) Dir.SetOwnerError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.fchownat(
        &sync,
        dir.handle,
        "",
        owner orelse std.math.maxInt(linux.uid_t),
        group orelse std.math.maxInt(linux.gid_t),
        linux.AT.EMPTY_PATH,
    );
}

fn dirSetFileOwner(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    owner: ?File.Uid,
    group: ?File.Gid,
    options: Dir.SetFileOwnerOptions,
) Dir.SetFileOwnerError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.fchownat(
        &sync,
        dir.handle,
        sub_path_posix,
        owner orelse std.math.maxInt(linux.uid_t),
        group orelse std.math.maxInt(linux.gid_t),
        if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW,
    );
}

fn dirSetPermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    permissions: Dir.Permissions,
) Dir.SetPermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    ev.fchmodat(
        &sync,
        dir.handle,
        "",
        permissions.toMode(),
        linux.AT.EMPTY_PATH,
    ) catch |err| switch (err) {
        error.NameTooLong => return errnoBug(.NAMETOOLONG),
        error.BadPathName => return errnoBug(.ILSEQ),
        error.ProcessFdQuotaExceeded => return errnoBug(.MFILE),
        error.SystemFdQuotaExceeded => return errnoBug(.NFILE),
        error.OperationUnsupported => return errnoBug(.OPNOTSUPP),
        else => |e| return e,
    };
}

fn dirSetFilePermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.SetFilePermissionsOptions,
) Dir.SetFilePermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.fchmodat(
        &sync,
        dir.handle,
        sub_path_posix,
        permissions.toMode(),
        if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW,
    );
}

fn dirSetTimestamps(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.SetTimestampsOptions,
) Dir.SetTimestampsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var path_buffer: [PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    var cancel_region: CancelRegion.Sync = try .init(ev);
    defer cancel_region.deinit(ev);
    try ev.utimensat(
        &cancel_region,
        dir.handle,
        sub_path_posix,
        if (options.modify_timestamp != .now or options.access_timestamp != .now) &.{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        } else null,
        if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW,
    );
}

fn dirHardLink(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: Dir.HardLinkOptions,
) Dir.HardLinkError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var old_path_buffer: [PATH_MAX]u8 = undefined;
    var new_path_buffer: [PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.linkat(
        &cancel_region,
        old_dir.handle,
        old_sub_path_posix,
        new_dir.handle,
        new_sub_path_posix,
        if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW,
    );
}

fn fileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.stat(&cancel_region, file.handle);
}

fn fileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        var statx_buf = std.mem.zeroes(linux.Statx);
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .STATX,
            .flags = 0,
            .ioprio = 0,
            .fd = file.handle,
            .off = @intFromPtr(&statx_buf),
            .addr = @intFromPtr(""),
            .len = @bitCast(linux.STATX{ .SIZE = true }),
            .rw_flags = linux.AT.EMPTY_PATH,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => {
                if (!statx_buf.mask.SIZE) return error.Unexpected;
                return statx_buf.size;
            },
            .INTR, .CANCELED => {},
            .ACCES => |err| return errnoBug(err),
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .LOOP => |err| return errnoBug(err),
            .NAMETOOLONG => |err| return errnoBug(err),
            .NOENT => |err| return errnoBug(err),
            .NOMEM => return error.SystemResources,
            .NOTDIR => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileClose(userdata: ?*anyopaque, files: []const File) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    for (files) |file| ev.close(file.handle);
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) File.WritePositionalError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var iovecs: [max_iovecs_len]iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    addBuf(&iovecs, &iovlen, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(&iovecs, &iovlen, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0) switch (splat) {
        0 => {},
        1 => addBuf(&iovecs, &iovlen, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addBuf(&iovecs, &iovlen, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and iovecs.len - iovlen != 0) {
                    assert(buf.len == splat_buffer.len);
                    addBuf(&iovecs, &iovlen, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addBuf(&iovecs, &iovlen, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - iovlen)) |_| {
                addBuf(&iovecs, &iovlen, pattern);
            },
        },
    };

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.pwritev(&cancel_region, file.handle, iovecs[0..iovlen], offset);
}

/// This is either usize or u32. Since, either is fine, let's use the same
/// `addBuf` function for both writing to a file and sending network messages.
const iovlen_t = @FieldType(linux.msghdr_const, "iovlen");

fn addBuf(v: []iovec_const, i: *iovlen_t, bytes: []const u8) void {
    // OS checks ptr addr before length so zero length vectors must be omitted.
    if (bytes.len == 0) return;
    if (v.len - i.* == 0) return;
    v[i.*] = .{ .base = bytes.ptr, .len = bytes.len };
    i.* += 1;
}

fn fileWriteFileStreaming(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) File.Writer.WriteFileError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = file;
    _ = header;
    _ = file_reader;
    _ = limit;
    return error.Unimplemented;
}

fn fileWriteFilePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
    offset: u64,
) File.WriteFilePositionalError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = file;
    _ = header;
    _ = file_reader;
    _ = limit;
    _ = offset;
    return error.Unimplemented;
}

fn fileReadPositional(
    userdata: ?*anyopaque,
    file: File,
    data: []const []u8,
    offset: u64,
) File.ReadPositionalError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var iovecs_buffer: [max_iovecs_len]iovec = undefined;
    var i: usize = 0;
    for (data) |buf| {
        if (iovecs_buffer.len - i == 0) break;
        if (buf.len > 0) {
            iovecs_buffer[i] = .{ .base = buf.ptr, .len = buf.len };
            i += 1;
        }
    }
    if (i == 0) return 0;
    const dest = iovecs_buffer[0..i];
    assert(dest[0].len > 0);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.preadv(&cancel_region, file.handle, dest, offset) catch |err| switch (err) {
        error.SocketUnconnected => return errnoBug(.NOTCONN), // not a socket
        error.ConnectionResetByPeer => return errnoBug(.CONNRESET), // not a socket
        else => |e| return e,
    };
}

fn fileSeekBy(userdata: ?*anyopaque, file: File, offset: i64) File.SeekError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.lseek(&sync, file.handle, @bitCast(offset), linux.SEEK.CUR);
}

fn fileSeekTo(userdata: ?*anyopaque, file: File, offset: u64) File.SeekError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.lseek(&sync, file.handle, offset, linux.SEEK.SET);
}

fn fileSync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .FSYNC,
            .flags = 0,
            .ioprio = 0,
            .fd = file.handle,
            .off = 0,
            .addr = 0,
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .BADF => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .ROFS => |err| return errnoBug(err),
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .DQUOT => return error.DiskQuota,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileIsTty(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    while (true) {
        try sync.cancel_region.await(.nothing);
        var wsz: winsize = undefined;
        const rc = linux.ioctl(file.handle, linux.T.IOCGWINSZ, @intFromPtr(&wsz));
        switch (linux.errno(rc)) {
            .SUCCESS => return true,
            .INTR => {},
            else => return false,
        }
    }
}

fn fileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: File) File.EnableAnsiEscapeCodesError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (!try fileIsTty(ev, file)) return error.NotTerminalDevice;
}

fn fileSetLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .FTRUNCATE,
            .flags = 0,
            .ioprio = 0,
            .fd = file.handle,
            .off = length,
            .addr = 0,
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .FBIG => return error.FileTooBig,
            .IO => return error.InputOutput,
            .PERM => return error.PermissionDenied,
            .TXTBSY => return error.FileBusy,
            .BADF => |err| return errnoBug(err), // Handle not open for writing.
            .INVAL => return error.NonResizable, // This is returned for /dev/null for example.
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileSetOwner(
    userdata: ?*anyopaque,
    file: File,
    owner: ?File.Uid,
    group: ?File.Gid,
) File.SetOwnerError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.fchownat(
        &sync,
        file.handle,
        "",
        owner orelse std.math.maxInt(linux.uid_t),
        group orelse std.math.maxInt(linux.gid_t),
        linux.AT.EMPTY_PATH,
    );
}

fn fileSetPermissions(
    userdata: ?*anyopaque,
    file: File,
    permissions: File.Permissions,
) File.SetPermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    ev.fchmodat(
        &sync,
        file.handle,
        "",
        permissions.toMode(),
        linux.AT.EMPTY_PATH,
    ) catch |err| switch (err) {
        error.NameTooLong => return errnoBug(.NAMETOOLONG),
        error.BadPathName => return errnoBug(.ILSEQ),
        error.ProcessFdQuotaExceeded => return errnoBug(.MFILE),
        error.SystemFdQuotaExceeded => return errnoBug(.NFILE),
        error.OperationUnsupported => return errnoBug(.OPNOTSUPP),
        else => |e| return e,
    };
}

fn fileSetTimestamps(
    userdata: ?*anyopaque,
    file: File,
    options: File.SetTimestampsOptions,
) File.SetTimestampsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    try ev.utimensat(
        &sync,
        file.handle,
        "",
        if (options.modify_timestamp != .now or options.access_timestamp != .now) &.{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        } else null,
        linux.AT.EMPTY_PATH,
    );
}

fn fileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    ev.flock(&sync, file.handle, lock, .blocking) catch |err| switch (err) {
        error.WouldBlock => unreachable, // blocking
        else => |e| return e,
    };
}

fn fileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    ev.flock(&sync, file.handle, lock, switch (lock) {
        .none => .blocking,
        .shared, .exclusive => .nonblocking,
    }) catch |err| switch (err) {
        error.WouldBlock => return false,
        else => |e| return e,
    };
    return true;
}

fn fileUnlock(userdata: ?*anyopaque, file: File) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = .initBlocked(ev);
    defer sync.deinit(ev);
    ev.flock(&sync, file.handle, .none, .blocking) catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
        error.WouldBlock => unreachable, // blocking
        error.SystemResources => return recoverableOsBugDetected(), // Resource deallocation.
        error.FileLocksUnsupported => return recoverableOsBugDetected(), // We already got the lock.
        error.Unexpected => return recoverableOsBugDetected(), // Resource deallocation must succeed.
    };
}

fn fileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    ev.flock(&sync, file.handle, .shared, .nonblocking) catch |err| switch (err) {
        error.WouldBlock => return errnoBug(.AGAIN), // File was not locked in exclusive mode.
        error.SystemResources => return errnoBug(.NOLCK), // Lock already obtained.
        error.FileLocksUnsupported => return errnoBug(.OPNOTSUPP), // Lock already obtained.
        else => |e| return e,
    };
}

fn fileRealPath(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    return ev.realPath(&sync, file.handle, out_buffer);
}

fn fileHardLink(
    userdata: ?*anyopaque,
    file: File,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: File.HardLinkOptions,
) File.HardLinkError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var new_path_buffer: [PATH_MAX]u8 = undefined;
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    return ev.linkat(
        &cancel_region,
        file.handle,
        "",
        new_dir.handle,
        new_sub_path_posix,
        linux.AT.EMPTY_PATH | @as(u32, if (options.follow_symlinks) 0 else linux.AT.SYMLINK_NOFOLLOW),
    );
}

fn fileMemoryMapCreate(
    userdata: ?*anyopaque,
    file: File,
    options: File.MemoryMap.CreateOptions,
) File.MemoryMap.CreateError!File.MemoryMap {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    const prot: linux.PROT = .{
        .READ = options.protection.read,
        .WRITE = options.protection.write,
        .EXEC = options.protection.execute,
    };
    const flags: linux.MAP = .{
        .TYPE = .SHARED_VALIDATE,
        .POPULATE = options.populate,
    };

    const page_align = std.heap.page_size_min;

    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    const contents = while (true) {
        try sync.cancel_region.await(.nothing);
        const casted_offset = std.math.cast(i64, options.offset) orelse return error.Unseekable;
        const rc = linux.mmap(null, options.len, prot, flags, file.handle, casted_offset);
        switch (linux.errno(rc)) {
            .SUCCESS => break @as([*]align(page_align) u8, @ptrFromInt(rc))[0..options.len],
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .AGAIN => return error.LockedMemoryLimitExceeded,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NOMEM => return error.OutOfMemory,
            .PERM => return error.PermissionDenied,
            .OVERFLOW => return error.Unseekable,
            .BADF => |err| return errnoBug(err), // Always a race condition.
            .INVAL => |err| return errnoBug(err), // Invalid parameters to mmap()
            .OPNOTSUPP => |err| return errnoBug(err), // Bad flags with MAP.SHARED_VALIDATE on Linux.
            else => |err| return unexpectedErrno(err),
        }
    };
    return .{
        .file = file,
        .offset = options.offset,
        .memory = contents,
        .section = {},
    };
}

fn fileMemoryMapDestroy(userdata: ?*anyopaque, mm: *File.MemoryMap) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const memory = mm.memory;
    if (memory.len == 0) return;
    switch (linux.errno(linux.munmap(memory.ptr, memory.len))) {
        .SUCCESS => {},
        else => |err| if (builtin.mode == .Debug)
            std.log.err("failed to unmap {d} bytes at {*}: {t}", .{ memory.len, memory.ptr, err }),
    }
    mm.* = undefined;
}

fn fileMemoryMapSetLength(
    userdata: ?*anyopaque,
    mm: *File.MemoryMap,
    new_len: usize,
) File.MemoryMap.SetLengthError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const page_align = std.heap.page_size_min;
    const old_memory = mm.memory;

    if (alignment.forward(new_len) == alignment.forward(old_memory.len)) {
        mm.memory.len = new_len;
        return;
    }
    const flags: linux.MREMAP = .{ .MAYMOVE = true };
    const addr_hint: ?[*]const u8 = null;
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    const new_memory = while (true) {
        try sync.cancel_region.await(.nothing);
        const rc = linux.mremap(old_memory.ptr, old_memory.len, new_len, flags, addr_hint);
        switch (linux.errno(rc)) {
            .SUCCESS => break @as([*]align(page_align) u8, @ptrFromInt(rc))[0..new_len],
            .INTR => {},
            .AGAIN => return error.LockedMemoryLimitExceeded,
            .NOMEM => return error.OutOfMemory,
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    };
    mm.memory = new_memory;
}

fn fileMemoryMapRead(userdata: ?*anyopaque, mm: *File.MemoryMap) File.ReadPositionalError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = mm;
}

fn fileMemoryMapWrite(userdata: ?*anyopaque, mm: *File.MemoryMap) File.WritePositionalError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = mm;
}

fn processExecutableOpen(
    userdata: ?*anyopaque,
    flags: File.OpenFlags,
) process.OpenExecutableError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return dirOpenFile(ev, .{ .handle = linux.AT.FDCWD }, "/proc/self/exe", flags);
}

fn processExecutablePath(userdata: ?*anyopaque, out_buffer: []u8) process.ExecutablePathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return dirReadLink(ev, .cwd(), "/proc/self/exe", out_buffer) catch |err| switch (err) {
        error.UnsupportedReparsePointType => unreachable, // Windows-only
        error.NetworkNotFound => unreachable, // Windows-only
        error.FileBusy => unreachable, // Windows-only
        else => |e| return e,
    };
}

fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    ev.stderr_mutex.lockUncancelable(ev_io);
    errdefer ev.stderr_mutex.unlock(ev_io);
    return ev.initLockedStderr(terminal_mode);
}

fn tryLockStderr(
    userdata: ?*anyopaque,
    terminal_mode: ?Io.Terminal.Mode,
) Io.Cancelable!?Io.LockedStderr {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const ev_io = ev.io();
    if (!ev.stderr_mutex.tryLock()) return null;
    errdefer ev.stderr_mutex.unlock(ev_io);
    return try ev.initLockedStderr(terminal_mode);
}

fn initLockedStderr(ev: *Evented, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    if (!ev.stderr_writer_initialized) {
        const ev_io = ev.io();
        const cancel_protection = swapCancelProtection(ev, .blocked);
        defer assert(swapCancelProtection(ev, cancel_protection) == .blocked);
        ev.scanEnviron() catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
        const NO_COLOR = ev.environ.exist.NO_COLOR;
        const CLICOLOR_FORCE = ev.environ.exist.CLICOLOR_FORCE;
        ev.stderr_mode = Io.Terminal.Mode.detect(
            ev_io,
            ev.stderr_writer.file,
            NO_COLOR,
            CLICOLOR_FORCE,
        ) catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
        ev.stderr_writer_initialized = true;
    }
    return .{
        .file_writer = &ev.stderr_writer,
        .terminal_mode = terminal_mode orelse ev.stderr_mode,
    };
}

fn unlockStderr(userdata: ?*anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (ev.stderr_writer.err == null) ev.stderr_writer.interface.flush() catch {};
    if (ev.stderr_writer.err) |err| {
        switch (err) {
            error.Canceled => Thread.current().currentFiber().cancel_protection.recancel(),
            else => {},
        }
        ev.stderr_writer.err = null;
    }
    ev.stderr_writer.interface.end = 0;
    ev.stderr_writer.interface.buffer = &.{};
    ev.stderr_mutex.unlock(ev.io());
}

fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) process.CurrentPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.getcwd(buffer.ptr, buffer.len))) {
            .SUCCESS => return std.mem.findScalar(u8, buffer, 0).?,
            .INTR => {},
            .NOENT => return error.CurrentDirUnlinked,
            .RANGE => return error.NameTooLong,
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn processSetCurrentDir(userdata: ?*anyopaque, dir: Dir) process.SetCurrentDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (dir.handle == linux.AT.FDCWD) return;
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    return fchdir(&sync, dir.handle);
}

fn processSetCurrentPath(userdata: ?*anyopaque, dir_path: []const u8) process.SetCurrentPathError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var path_buffer: [PATH_MAX]u8 = undefined;
    const dir_path_posix = try pathToPosix(dir_path, &path_buffer);
    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    return chdir(&sync, dir_path_posix);
}

fn processReplace(userdata: ?*anyopaque, options: process.ReplaceOptions) process.ReplaceError {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    try ev.scanEnviron(); // for PATH
    const PATH = ev.environ.string.PATH orelse default_PATH;

    var arena_allocator = std.heap.ArenaAllocator.init(ev.allocator());
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const argv_buf = try arena.allocSentinel(?[*:0]const u8, options.argv.len, null);
    for (options.argv, 0..) |arg, i| argv_buf[i] = (try arena.dupeZ(u8, arg)).ptr;

    const env_block = env_block: {
        const prog_fd: i32 = -1;
        if (options.environ_map) |environ_map| break :env_block try environ_map.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
        break :env_block try ev.environ.process_environ.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
    };

    var sync: CancelRegion.Sync = try .init(ev);
    defer sync.deinit(ev);
    return execv(&sync, options.expand_arg0, argv_buf.ptr[0].?, argv_buf.ptr, env_block, PATH);
}

fn processReplacePath(
    userdata: ?*anyopaque,
    dir: Dir,
    options: process.ReplaceOptions,
) process.ReplaceError {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = dir;
    _ = options;
    @panic("TODO processReplacePath");
}

fn processSpawn(userdata: ?*anyopaque, options: process.SpawnOptions) process.SpawnError!process.Child {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const spawned = try ev.spawn(options);
    var cancel_region: CancelRegion = .initBlocked();
    defer cancel_region.deinit();
    defer ev.closeAsync(spawned.err_fd);

    // Wait for the child to report any errors in or before `execvpe`.
    var child_err: ForkBailError = undefined;
    ev.readAll(&cancel_region, spawned.err_fd, @ptrCast(&child_err)) catch |read_err| {
        switch (read_err) {
            error.Canceled => unreachable, // blocked
            error.EndOfStream => {
                // Write end closed by CLOEXEC at the time of the `execvpe` call,
                // indicating success.
            },
            else => {
                // Problem reading the error from the error reporting pipe. We
                // don't know if the child is alive or dead. Better to assume it is
                // alive so the resource does not risk being leaked.
            },
        }
        return .{
            .id = spawned.pid,
            .thread_handle = {},
            .stdin = spawned.stdin,
            .stdout = spawned.stdout,
            .stderr = spawned.stderr,
            .request_resource_usage_statistics = options.request_resource_usage_statistics,
        };
    };
    return child_err;
}

fn processSpawnPath(
    userdata: ?*anyopaque,
    dir: Dir,
    options: process.SpawnOptions,
) process.SpawnError!process.Child {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = dir;
    _ = options;
    @panic("TODO processSpawnPath");
}

const prog_fileno = @max(linux.STDIN_FILENO, linux.STDOUT_FILENO, linux.STDERR_FILENO);

const Spawned = struct {
    pid: pid_t,
    err_fd: fd_t,
    stdin: ?File,
    stdout: ?File,
    stderr: ?File,
};
fn spawn(ev: *Evented, options: process.SpawnOptions) process.SpawnError!Spawned {
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();

    // The child process does need to access (one end of) these pipes. However,
    // we must initially set CLOEXEC to avoid a race condition. If another thread
    // is racing to spawn a different child process, we don't want it to inherit
    // these FDs in any scenario; that would mean that, for instance, calls to
    // `poll` from the parent would not report the child's stdout as closing when
    // expected, since the other child may retain a reference to the write end of
    // the pipe. So, we create the pipes with CLOEXEC initially. After fork, we
    // need to do something in the new child to make sure we preserve the reference
    // we want. We could use `fcntl` to remove CLOEXEC from the FD, but as it
    // turns out, we `dup2` everything anyway, so there's no need!
    const pipe_flags: linux.O = .{ .CLOEXEC = true };

    const stdin_pipe = if (options.stdin == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stdin == .pipe) {
        ev.destroyPipe(stdin_pipe);
    };

    const stdout_pipe = if (options.stdout == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stdout == .pipe) {
        ev.destroyPipe(stdout_pipe);
    };

    const stderr_pipe = if (options.stderr == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stderr == .pipe) {
        ev.destroyPipe(stderr_pipe);
    };

    const any_ignore =
        options.stdin == .ignore or options.stdout == .ignore or options.stderr == .ignore;
    const dev_null_fd = if (any_ignore) try ev.null_fd.open(ev, &cancel_region, "/dev/null", .{
        .ACCMODE = .RDWR,
    }) else undefined;

    const prog_pipe: [2]fd_t = if (options.progress_node.index != .none) pipe: {
        // We use CLOEXEC for the same reason as in `pipe_flags`.
        const pipe = try pipe2(.{ .NONBLOCK = true, .CLOEXEC = true });
        _ = linux.fcntl(pipe[0], linux.F.SETPIPE_SZ, @as(u32, std.Progress.max_packet_len * 2));
        break :pipe pipe;
    } else .{ -1, -1 };
    errdefer ev.destroyPipe(prog_pipe);

    var arena_allocator = std.heap.ArenaAllocator.init(ev.allocator());
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    // The POSIX standard does not allow malloc() between fork() and execve(),
    // and this allocator may be a libc allocator.
    // I have personally observed the child process deadlocking when it tries
    // to call malloc() due to a heap allocation between fork() and execve(),
    // in musl v1.1.24.
    // Additionally, we want to reduce the number of possible ways things
    // can fail between fork() and execve().
    // Therefore, we do all the allocation for the execve() before the fork().
    // This means we must do the null-termination of argv and env vars here.
    const argv_buf = try arena.allocSentinel(?[*:0]const u8, options.argv.len, null);
    for (options.argv, 0..) |arg, i| argv_buf[i] = (try arena.dupeZ(u8, arg)).ptr;

    const env_block = env_block: {
        const prog_fd: i32 = if (prog_pipe[1] == -1) -1 else prog_fileno;
        if (options.environ_map) |environ_map| break :env_block try environ_map.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
        break :env_block try ev.environ.process_environ.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
    };

    // This pipe communicates to the parent errors in the child between `fork` and `execvpe`.
    // It is closed by the child (via CLOEXEC) without writing if `execvpe` succeeds.
    const err_pipe: [2]fd_t = try pipe2(.{ .CLOEXEC = true });
    errdefer ev.destroyPipe(err_pipe);

    try ev.scanEnviron(); // for PATH
    const PATH = ev.environ.string.PATH orelse default_PATH;

    const pid_result: pid_t = fork: {
        const rc = linux.fork();
        switch (linux.errno(rc)) {
            .SUCCESS => break :fork @intCast(rc),
            .AGAIN => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOSYS => return error.OperationUnsupported,
            else => |err| return unexpectedErrno(err),
        }
    };

    if (pid_result == 0) {
        defer comptime unreachable; // We are the child.
        // Note that the parent uring is no longer accessible, so we must no longer reference `ev`.
        var sync: CancelRegion.Sync = .{ .cancel_region = .initBlocked() };
        const err = setUpChild(&sync, .{
            .stdin_pipe = stdin_pipe[0],
            .stdout_pipe = stdout_pipe[1],
            .stderr_pipe = stderr_pipe[1],
            .dev_null_fd = dev_null_fd,
            .prog_pipe = prog_pipe[1],
            .argv_buf = argv_buf,
            .env_block = env_block,
            .PATH = PATH,
            .spawn = options,
        });
        writeAllSync(&sync, err_pipe[1], @ptrCast(&err)) catch {};
        const exit = if (builtin.single_threaded) linux.exit else linux.exit_group;
        exit(1);
    }

    const pid: pid_t = @intCast(pid_result); // We are the parent.
    errdefer comptime unreachable; // The child is forked; we must not error from now on

    ev.closeAsync(err_pipe[1]); // make sure only the child holds the write end open

    if (options.stdin == .pipe) ev.closeAsync(stdin_pipe[0]);
    if (options.stdout == .pipe) ev.closeAsync(stdout_pipe[1]);
    if (options.stderr == .pipe) ev.closeAsync(stderr_pipe[1]);

    if (prog_pipe[1] != -1) ev.closeAsync(prog_pipe[1]);

    options.progress_node.setIpcFile(ev, .{ .handle = prog_pipe[0], .flags = .{ .nonblocking = true } });

    return .{
        .pid = pid,
        .err_fd = err_pipe[0],
        .stdin = switch (options.stdin) {
            .pipe => .{ .handle = stdin_pipe[1], .flags = .{ .nonblocking = false } },
            else => null,
        },
        .stdout = switch (options.stdout) {
            .pipe => .{ .handle = stdout_pipe[0], .flags = .{ .nonblocking = false } },
            else => null,
        },
        .stderr = switch (options.stderr) {
            .pipe => .{ .handle = stderr_pipe[0], .flags = .{ .nonblocking = false } },
            else => null,
        },
    };
}

pub const PipeError = error{
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
} || Io.UnexpectedError;
pub fn pipe2(flags: linux.O) PipeError![2]fd_t {
    var fds: [2]fd_t = undefined;
    switch (linux.errno(linux.pipe2(&fds, flags))) {
        .SUCCESS => return fds,
        .INVAL => |err| return errnoBug(err), // Invalid flags
        .NFILE => return error.SystemFdQuotaExceeded,
        .MFILE => return error.ProcessFdQuotaExceeded,
        else => |err| return unexpectedErrno(err),
    }
}
fn destroyPipe(ev: *Evented, pipe: [2]fd_t) void {
    if (pipe[0] != -1) ev.closeAsync(pipe[0]);
    if (pipe[0] != pipe[1]) ev.closeAsync(pipe[1]);
}

/// Errors that can occur between fork() and execv()
const ForkBailError = process.SetCurrentDirError || ChdirError ||
    process.SpawnError || process.ReplaceError;
fn setUpChild(sync: *CancelRegion.Sync, options: struct {
    stdin_pipe: fd_t,
    stdout_pipe: fd_t,
    stderr_pipe: fd_t,
    dev_null_fd: fd_t,
    prog_pipe: fd_t,
    argv_buf: [:null]?[*:0]const u8,
    env_block: process.Environ.Block,
    PATH: []const u8,
    spawn: process.SpawnOptions,
}) ForkBailError {
    try setUpChildIo(
        sync,
        options.spawn.stdin,
        options.stdin_pipe,
        linux.STDIN_FILENO,
        options.dev_null_fd,
    );
    try setUpChildIo(
        sync,
        options.spawn.stdout,
        options.stdout_pipe,
        linux.STDOUT_FILENO,
        options.dev_null_fd,
    );
    try setUpChildIo(
        sync,
        options.spawn.stderr,
        options.stderr_pipe,
        linux.STDERR_FILENO,
        options.dev_null_fd,
    );

    switch (options.spawn.cwd) {
        .inherit => {},
        .dir => |cwd_dir| try fchdir(sync, cwd_dir.handle),
        .path => |cwd_path| {
            var cwd_path_buffer: [PATH_MAX]u8 = undefined;
            const cwd_path_posix = try pathToPosix(cwd_path, &cwd_path_buffer);
            try chdir(sync, cwd_path_posix);
        },
    }

    // Must happen after fchdir above, the cwd file descriptor might be
    // equal to prog_fileno and be clobbered by this dup2 call.
    if (options.prog_pipe != -1) try dup2(sync, options.prog_pipe, prog_fileno);

    if (options.spawn.gid) |gid| {
        switch (linux.errno(linux.setregid(gid, gid))) {
            .SUCCESS => {},
            .AGAIN => return error.ResourceLimitReached,
            .INVAL => return error.InvalidUserId,
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }

    if (options.spawn.uid) |uid| {
        switch (linux.errno(linux.setreuid(uid, uid))) {
            .SUCCESS => {},
            .AGAIN => return error.ResourceLimitReached,
            .INVAL => return error.InvalidUserId,
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }

    if (options.spawn.pgid) |pid| {
        switch (linux.errno(linux.setpgid(0, pid))) {
            .SUCCESS => {},
            .ACCES => return error.ProcessAlreadyExec,
            .INVAL => return error.InvalidProcessGroupId,
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }

    if (options.spawn.start_suspended) {
        switch (linux.errno(linux.kill(0, .STOP))) {
            .SUCCESS => {},
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }

    return execv(
        sync,
        options.spawn.expand_arg0,
        options.argv_buf.ptr[0].?,
        options.argv_buf.ptr,
        options.env_block,
        options.PATH,
    );
}

fn setUpChildIo(
    sync: *CancelRegion.Sync,
    stdio: process.SpawnOptions.StdIo,
    pipe_fd: fd_t,
    std_fileno: i32,
    dev_null_fd: fd_t,
) !void {
    switch (stdio) {
        .pipe => try dup2(sync, pipe_fd, std_fileno),
        .close => _ = linux.close(std_fileno),
        .inherit => {},
        .ignore => try dup2(sync, dev_null_fd, std_fileno),
        .file => |file| try dup2(sync, file.handle, std_fileno),
    }
}

pub const DupError = error{
    ProcessFdQuotaExceeded,
    SystemResources,
} || Io.UnexpectedError || Io.Cancelable;
pub fn dup2(sync: *CancelRegion.Sync, old_fd: fd_t, new_fd: fd_t) DupError!void {
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.dup2(old_fd, new_fd))) {
            .SUCCESS => return,
            .BUSY, .INTR => {},
            .INVAL => |err| return errnoBug(err), // invalid parameters
            .BADF => |err| return errnoBug(err), // use after free
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NOMEM => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn execv(
    sync: *CancelRegion.Sync,
    arg0_expand: process.ArgExpansion,
    file: [*:0]const u8,
    child_argv: [*:null]?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
    PATH: []const u8,
) process.ReplaceError {
    const file_slice = std.mem.sliceTo(file, 0);
    if (std.mem.findScalar(u8, file_slice, '/') != null)
        return execvPath(sync, file, child_argv, env_block);

    // Use of PATH_MAX here is valid as the path_buf will be passed
    // directly to the operating system in posixExecvPath.
    var path_buf: [PATH_MAX]u8 = undefined;
    var it = std.mem.tokenizeScalar(u8, PATH, ':');
    var seen_eacces = false;
    var err: process.ReplaceError = error.FileNotFound;

    // In case of expanding arg0 we must put it back if we return with an error.
    const prev_arg0 = child_argv[0];
    defer switch (arg0_expand) {
        .expand => child_argv[0] = prev_arg0,
        .no_expand => {},
    };

    while (it.next()) |search_path| {
        const path_len = search_path.len + file_slice.len + 1;
        if (path_buf.len < path_len + 1) return error.NameTooLong;
        @memcpy(path_buf[0..search_path.len], search_path);
        path_buf[search_path.len] = '/';
        @memcpy(path_buf[search_path.len + 1 ..][0..file_slice.len], file_slice);
        path_buf[path_len] = 0;
        const full_path = path_buf[0..path_len :0].ptr;
        switch (arg0_expand) {
            .expand => child_argv[0] = full_path,
            .no_expand => {},
        }
        err = execvPath(sync, full_path, child_argv, env_block);
        switch (err) {
            error.AccessDenied => seen_eacces = true,
            error.FileNotFound, error.NotDir => {},
            else => |e| return e,
        }
    }
    if (seen_eacces) return error.AccessDenied;
    return err;
}
/// This function ignores PATH environment variable.
pub fn execvPath(
    sync: *CancelRegion.Sync,
    path: [*:0]const u8,
    child_argv: [*:null]const ?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
) process.ReplaceError {
    try sync.cancel_region.await(.nothing);
    switch (linux.errno(linux.execve(path, child_argv, env_block.slice.ptr))) {
        .FAULT => |err| return errnoBug(err), // Bad pointer parameter.
        .@"2BIG" => return error.SystemResources,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NAMETOOLONG => return error.NameTooLong,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM => return error.SystemResources,
        .ACCES => return error.AccessDenied,
        .PERM => return error.PermissionDenied,
        .INVAL => return error.InvalidExe,
        .NOEXEC => return error.InvalidExe,
        .IO => return error.FileSystem,
        .LOOP => return error.FileSystem,
        .ISDIR => return error.IsDir,
        .NOENT => return error.FileNotFound,
        .NOTDIR => return error.NotDir,
        .TXTBSY => return error.FileBusy,
        .LIBBAD => return error.InvalidExe,
        else => |err| return unexpectedErrno(err),
    }
}

fn childWait(userdata: ?*anyopaque, child: *process.Child) process.Child.WaitError!process.Child.Term {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    defer ev.childCleanup(child);

    const pid = child.id.?;
    var info: linux.siginfo_t = undefined;
    while (true) {
        const thread = try maybe_sync.cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .WAITID,
            .flags = 0,
            .ioprio = 0,
            .fd = pid,
            .off = @intFromPtr(&info),
            .addr = 0,
            .len = @intFromEnum(linux.P.PID),
            .rw_flags = 0,
            .user_data = @intFromPtr(maybe_sync.cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = linux.W.EXITED |
                @as(i32, if (child.request_resource_usage_statistics) linux.W.NOWAIT else 0),
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (maybe_sync.cancel_region.errno()) {
            .SUCCESS => {
                if (child.request_resource_usage_statistics) {
                    const sync = try maybe_sync.enterSync(ev);
                    while (true) {
                        try sync.cancel_region.await(.nothing);
                        var rusage: linux.rusage = undefined;
                        switch (linux.errno(linux.waitid(
                            .PID,
                            pid,
                            &info,
                            linux.W.EXITED | linux.W.NOHANG,
                            &rusage,
                        ))) {
                            .SUCCESS => {
                                child.resource_usage_statistics.rusage = rusage;
                                break;
                            },
                            .INTR, .CANCELED => {},
                            .CHILD => |err| return errnoBug(err), // Double-free.
                            else => |err| return unexpectedErrno(err),
                        }
                    }
                }
                const status: u32 = @bitCast(info.fields.common.second.sigchld.status);
                const code: linux.CLD = @enumFromInt(info.code);
                return switch (code) {
                    .EXITED => .{ .exited = @truncate(status) },
                    .KILLED, .DUMPED => .{ .signal = @enumFromInt(status) },
                    .TRAPPED, .STOPPED => .{ .stopped = @enumFromInt(status) },
                    _, .CONTINUED => .{ .unknown = status },
                };
            },
            .INTR, .CANCELED => {},
            .CHILD => |err| return errnoBug(err), // Double-free.
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn childKill(userdata: ?*anyopaque, child: *process.Child) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var maybe_sync: CancelRegion.Sync.Maybe = .{ .sync = .initBlocked(ev) };
    defer maybe_sync.deinit(ev);
    defer ev.childCleanup(child);

    const pid = child.id.?;
    while (true) switch (linux.errno(linux.kill(pid, .TERM))) {
        .SUCCESS => break,
        .INTR => {},
        .PERM => return,
        .INVAL => |err| return errnoBug(err) catch {},
        .SRCH => |err| return errnoBug(err) catch {},
        else => |err| return unexpectedErrno(err) catch {},
    };
    maybe_sync.leaveSync(ev);

    var info: linux.siginfo_t = undefined;
    while (true) {
        const thread = maybe_sync.cancel_region.awaitIoUring() catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
        thread.enqueue().* = .{
            .opcode = .WAITID,
            .flags = 0,
            .ioprio = 0,
            .fd = pid,
            .off = @intFromPtr(&info),
            .addr = 0,
            .len = @intFromEnum(linux.P.PID),
            .rw_flags = 0,
            .user_data = @intFromPtr(maybe_sync.cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = linux.W.EXITED,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (maybe_sync.cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .CHILD => |err| return errnoBug(err) catch {}, // Double-free.
            else => |err| return unexpectedErrno(err) catch {},
        }
    }
}

fn childCleanup(ev: *Evented, child: *process.Child) void {
    if (child.stdin) |*stdin| {
        ev.closeAsync(stdin.handle);
        child.stdin = null;
    }
    if (child.stdout) |*stdout| {
        ev.closeAsync(stdout.handle);
        child.stdout = null;
    }
    if (child.stderr) |*stderr| {
        ev.closeAsync(stderr.handle);
        child.stderr = null;
    }
    child.id = null;
}

fn progressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const cancel_protection = swapCancelProtection(ev, .blocked);
    defer assert(swapCancelProtection(ev, cancel_protection) == .blocked);
    ev.scanEnviron() catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    };
    return ev.environ.zig_progress_file;
}

fn scanEnviron(ev: *Evented) Io.Cancelable!void {
    const ev_io = ev.io();
    try ev.environ_mutex.lock(ev_io);
    defer ev.environ_mutex.unlock(ev_io);
    if (ev.environ_initialized) return;
    ev.environ.scan(ev.allocator());
    ev.environ_initialized = true;
}

fn clockResolution(userdata: ?*anyopaque, clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const clock_id = clockToPosix(clock);
    var timespec: linux.timespec = undefined;
    return switch (linux.errno(linux.clock_getres(clock_id, &timespec))) {
        .SUCCESS => .fromNanoseconds(nanosecondsFromPosix(&timespec)),
        .INVAL => return error.ClockUnavailable,
        else => |err| return unexpectedErrno(err),
    };
}

fn now(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    var tp: linux.timespec = undefined;
    switch (linux.errno(linux.clock_gettime(clockToPosix(clock), &tp))) {
        .SUCCESS => return timestampFromPosix(&tp),
        else => return .zero,
    }
}

fn sleep(userdata: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    const timespec: linux.kernel_timespec, const clock: Io.Clock, const timeout_flags: u32 = timespec: switch (timeout) {
        .none => .{
            .{
                .sec = std.math.maxInt(i64),
                .nsec = std.time.ns_per_s - 1,
            },
            .awake,
            linux.IORING_TIMEOUT_ABS,
        },
        .duration => |duration| {
            const ns = duration.raw.toNanoseconds();
            break :timespec .{
                .{
                    .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                    .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                },
                duration.clock,
                0,
            };
        },
        .deadline => |deadline| {
            const ns = deadline.raw.toNanoseconds();
            break :timespec .{
                .{
                    .sec = @intCast(@divFloor(ns, std.time.ns_per_s)),
                    .nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                },
                deadline.clock,
                linux.IORING_TIMEOUT_ABS,
            };
        },
    };
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    const thread = try cancel_region.awaitIoUring();
    thread.enqueue().* = .{
        .opcode = .TIMEOUT,
        .flags = 0,
        .ioprio = 0,
        .fd = 0,
        .off = 0,
        .addr = @intFromPtr(&timespec),
        .len = 1,
        .rw_flags = timeout_flags | @as(u32, switch (clock) {
            .real => linux.IORING_TIMEOUT_REALTIME,
            else => 0,
            .boot => linux.IORING_TIMEOUT_BOOTTIME,
        }),
        .user_data = @intFromPtr(cancel_region.fiber),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    };
    ev.yield(null, .nothing);
    // Handles SUCCESS as well as clock not available and unexpected
    // errors. The user had a chance to check clock resolution before
    // getting here, which would have reported 0, making this a legal
    // amount of time to sleep.
}

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var thread: *Thread = .current();
    if (!thread.csprng.isInitialized()) {
        @branchHint(.unlikely);
        var seed: [Csprng.seed_len]u8 = undefined;
        {
            const ev_io = ev.io();
            ev.csprng_mutex.lockUncancelable(ev_io);
            defer ev.csprng_mutex.unlock(ev_io);
            if (!ev.csprng.isInitialized()) {
                @branchHint(.unlikely);
                var cancel_region: CancelRegion = .initBlocked();
                defer cancel_region.deinit();
                ev.urandomReadAll(&cancel_region, &seed) catch |err| switch (err) {
                    error.Canceled => unreachable, // blocked
                    else => fallbackSeed(ev, &seed),
                };
                ev.csprng.rng = .init(seed);
                thread = .current();
            }
            ev.csprng.rng.fill(&seed);
        }
        if (!thread.csprng.isInitialized()) {
            @branchHint(.likely);
            thread.csprng.rng = .init(seed);
        } else thread.csprng.rng.addEntropy(&seed);
    }
    thread.csprng.rng.fill(buffer);
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (buffer.len == 0) return;
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    ev.urandomReadAll(&cancel_region, buffer) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return error.EntropyUnavailable,
    };
}

fn netListenIpUnavailable(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.ListenOptions,
) net.IpAddress.ListenError!net.Socket {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = address;
    _ = options;
    return error.NetworkDown;
}

fn netAcceptUnavailable(
    userdata: ?*anyopaque,
    listen_handle: net.Socket.Handle,
    options: net.Server.AcceptOptions,
) net.Server.AcceptError!net.Socket {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = listen_handle;
    _ = options;
    return error.NetworkDown;
}

fn netBindIp(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.BindOptions,
) net.IpAddress.BindError!net.Socket {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const family = posixAddressFamily(address);
    var maybe_sync: CancelRegion.Sync.Maybe = .{ .cancel_region = .init() };
    defer maybe_sync.deinit(ev);
    const socket_fd = try ev.socket(&maybe_sync.cancel_region, family, options);
    errdefer ev.closeAsync(socket_fd);
    var storage: PosixAddress = undefined;
    var addr_len = addressToPosix(address, &storage);
    try ev.bind(&maybe_sync.cancel_region, socket_fd, &storage.any, addr_len);
    if (options.allow_broadcast) try ev.setsockopt(&maybe_sync.cancel_region, socket_fd, linux.SOL.SOCKET, linux.SO.BROADCAST, 1);
    try ev.getsockname(try maybe_sync.enterSync(ev), socket_fd, &storage.any, &addr_len);
    return .{ .handle = socket_fd, .address = addressFromPosix(&storage) };
}

fn netConnectIpUnavailable(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.ConnectOptions,
) net.IpAddress.ConnectError!net.Socket {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = address;
    _ = options;
    return error.NetworkDown;
}

fn netListenUnixUnavailable(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
    options: net.UnixAddress.ListenOptions,
) net.UnixAddress.ListenError!net.Socket.Handle {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = address;
    _ = options;
    return error.AddressFamilyUnsupported;
}

fn netConnectUnixUnavailable(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
) net.UnixAddress.ConnectError!net.Socket.Handle {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = address;
    return error.AddressFamilyUnsupported;
}

fn netSocketCreatePairUnavailable(
    userdata: ?*anyopaque,
    options: net.Socket.CreatePairOptions,
) net.Socket.CreatePairError![2]net.Socket {
    _ = userdata;
    _ = options;
    return error.OperationUnsupported;
}

fn netSendUnavailable(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    messages: []net.OutgoingMessage,
    flags: net.SendFlags,
) struct { ?net.Socket.SendError, usize } {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = handle;
    _ = messages;
    _ = flags;
    return .{ error.NetworkDown, 0 };
}

fn netReceive(
    ev: *Evented,
    cancel_region: *CancelRegion,
    handle: net.Socket.Handle,
    message_buffer: []net.IncomingMessage,
    data_buffer: []u8,
    flags: net.ReceiveFlags,
) struct { ?net.Socket.ReceiveError, usize } {
    var message_i: usize = 0;
    var data_i: usize = 0;

    while (true) {
        if (message_buffer.len - message_i == 0) return .{ null, message_i };
        const message = &message_buffer[message_i];
        const remaining_data_buffer = data_buffer[data_i..];
        var storage: PosixAddress = undefined;
        var iov: iovec = .{ .base = remaining_data_buffer.ptr, .len = remaining_data_buffer.len };
        var msg: linux.msghdr = .{
            .name = &storage.any,
            .namelen = @sizeOf(PosixAddress),
            .iov = (&iov)[0..1],
            .iovlen = 1,
            .control = message.control.ptr,
            .controllen = @intCast(message.control.len),
            .flags = undefined,
        };

        const thread = cancel_region.awaitIoUring() catch |err| return .{ err, message_i };
        thread.enqueue().* = .{
            .opcode = .RECVMSG,
            .flags = 0,
            .ioprio = 0,
            .fd = handle,
            .off = 0,
            .addr = @intFromPtr(&msg),
            .len = 0,
            .rw_flags = linux.MSG.NOSIGNAL |
                @as(u32, if (flags.oob) linux.MSG.OOB else 0) |
                @as(u32, if (flags.peek) linux.MSG.PEEK else 0) |
                @as(u32, if (flags.trunc) linux.MSG.TRUNC else 0),
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        const completion = cancel_region.completion();
        switch (completion.errno()) {
            .SUCCESS => {
                const data = remaining_data_buffer[0..@intCast(completion.result)];
                data_i += data.len;
                message.* = .{
                    .from = addressFromPosix(&storage),
                    .data = data,
                    .control = if (msg.control) |ptr| @as([*]u8, @ptrCast(ptr))[0..msg.controllen] else message.control,
                    .flags = .{
                        .eor = msg.flags & linux.MSG.EOR != 0,
                        .trunc = msg.flags & linux.MSG.TRUNC != 0,
                        .ctrunc = msg.flags & linux.MSG.CTRUNC != 0,
                        .oob = msg.flags & linux.MSG.OOB != 0,
                        .errqueue = msg.flags & linux.MSG.ERRQUEUE != 0,
                    },
                };
                message_i += 1;
                continue;
            },
            .AGAIN => unreachable,
            .INTR, .CANCELED => {},
            .BADF => |err| return .{ errnoBug(err), message_i },
            .NFILE => return .{ error.SystemFdQuotaExceeded, message_i },
            .MFILE => return .{ error.ProcessFdQuotaExceeded, message_i },
            .FAULT => |err| return .{ errnoBug(err), message_i },
            .INVAL => |err| return .{ errnoBug(err), message_i },
            .NOBUFS => return .{ error.SystemResources, message_i },
            .NOMEM => return .{ error.SystemResources, message_i },
            .NOTCONN => return .{ error.SocketUnconnected, message_i },
            .NOTSOCK => |err| return .{ errnoBug(err), message_i },
            .MSGSIZE => return .{ error.MessageOversize, message_i },
            .PIPE => return .{ error.SocketUnconnected, message_i },
            .OPNOTSUPP => |err| return .{ errnoBug(err), message_i },
            .CONNRESET => return .{ error.ConnectionResetByPeer, message_i },
            .NETDOWN => return .{ error.NetworkDown, message_i },
            else => |err| return .{ unexpectedErrno(err), message_i },
        }
    }
}

fn netReadUnavailable(
    userdata: ?*anyopaque,
    fd: net.Socket.Handle,
    data: [][]u8,
) net.Stream.Reader.Error!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = fd;
    _ = data;
    return error.NetworkDown;
}

fn netWriteUnavailable(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) net.Stream.Writer.Error!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = handle;
    _ = header;
    _ = data;
    _ = splat;
    return error.NetworkDown;
}

fn netWriteFileUnavailable(
    userdata: ?*anyopaque,
    socket_handle: net.Socket.Handle,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) net.Stream.Writer.WriteFileError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = socket_handle;
    _ = header;
    _ = file_reader;
    _ = limit;
    return error.NetworkDown;
}

fn netClose(userdata: ?*anyopaque, handles: []const net.Socket.Handle) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    for (handles) |handle| ev.close(handle);
}

fn netShutdown(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    how: net.ShutdownHow,
) net.ShutdownError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var cancel_region: CancelRegion = .init();
    defer cancel_region.deinit();
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .SHUTDOWN,
            .flags = 0,
            .ioprio = 0,
            .fd = handle,
            .off = 0,
            .addr = 0,
            .len = switch (how) {
                .recv => linux.SHUT.RD,
                .send => linux.SHUT.WR,
                .both => linux.SHUT.RDWR,
            },
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .BADF, .NOTSOCK, .INVAL => |err| return errnoBug(err),
            .NOTCONN => return error.SocketUnconnected,
            .NOBUFS => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn netInterfaceNameResolveUnavailable(
    userdata: ?*anyopaque,
    name: *const net.Interface.Name,
) net.Interface.Name.ResolveError!net.Interface {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = name;
    return error.InterfaceNotFound;
}

fn netInterfaceNameUnavailable(
    userdata: ?*anyopaque,
    interface: net.Interface,
) net.Interface.NameError!net.Interface.Name {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = interface;
    return error.Unexpected;
}

fn netLookupUnavailable(
    userdata: ?*anyopaque,
    host_name: net.HostName,
    resolved: *Io.Queue(net.HostName.LookupResult),
    options: net.HostName.LookupOptions,
) net.HostName.LookupError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = host_name;
    _ = options;
    resolved.close(ev.io());
    return error.NetworkDown;
}

fn bind(
    ev: *Evented,
    cancel_region: *CancelRegion,
    socket_fd: fd_t,
    addr: *const linux.sockaddr,
    addr_len: linux.socklen_t,
) !void {
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .BIND,
            .flags = 0,
            .ioprio = 0,
            .fd = socket_fd,
            .off = addr_len,
            .addr = @intFromPtr(addr),
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .ADDRINUSE => return error.AddressInUse,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .INVAL => |err| return errnoBug(err), // invalid parameters
            .NOTSOCK => |err| return errnoBug(err), // invalid `sockfd`
            .AFNOSUPPORT => return error.AddressFamilyUnsupported,
            .ADDRNOTAVAIL => return error.AddressUnavailable,
            .FAULT => |err| return errnoBug(err), // invalid `addr` pointer
            .NOMEM => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn chdir(sync: *CancelRegion.Sync, path: [*:0]const u8) ChdirError!void {
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.chdir(path))) {
            .SUCCESS => return,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .IO => return error.FileSystem,
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.NotDir,
            .ILSEQ => return error.BadPathName,
            .FAULT => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn close(ev: *Evented, fd: fd_t) void {
    var cancel_region: CancelRegion = .initBlocked();
    defer cancel_region.deinit();
    const thread = cancel_region.awaitIoUring() catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    };
    thread.enqueue().* = .{
        .opcode = .CLOSE,
        .flags = 0,
        .ioprio = 0,
        .fd = fd,
        .off = 0,
        .addr = 0,
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromPtr(cancel_region.fiber),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    };
    ev.yield(null, .nothing);
    switch (cancel_region.errno()) {
        .BADF => recoverableOsBugDetected(), // Always a race condition.
        .INTR => {}, // This is still a success. See https://github.com/ziglang/zig/issues/2425
        else => {},
    }
}

fn closeAsync(ev: *Evented, fd: fd_t) void {
    _ = ev;
    const thread: *Thread = .current();
    thread.enqueue().* = .{
        .opcode = .CLOSE,
        .flags = linux.IOSQE_CQE_SKIP_SUCCESS,
        .ioprio = 0,
        .fd = fd,
        .off = 0,
        .addr = 0,
        .len = 0,
        .rw_flags = 0,
        .user_data = @intFromEnum(Completion.Userdata.close),
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    };
}

fn fchdir(sync: *CancelRegion.Sync, dir: fd_t) process.SetCurrentDirError!void {
    if (dir == linux.AT.FDCWD) return;
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.fchdir(dir))) {
            .SUCCESS => return,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .NOTDIR => return error.NotDir,
            .IO => return error.FileSystem,
            .BADF => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fchmodat(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    dir: fd_t,
    path: [*:0]const u8,
    mode: linux.mode_t,
    flags: u32,
) Dir.SetFilePermissionsError!void {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.fchmodat2(dir, path, mode, flags))) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .ACCES => return error.AccessDenied,
            .IO => return error.InputOutput,
            .LOOP => return error.SymLinkLoop,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.FileNotFound,
            .OPNOTSUPP => return error.OperationUnsupported,
            .PERM => return error.PermissionDenied,
            .ROFS => return error.ReadOnlyFileSystem,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fchownat(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    dir: fd_t,
    path: [*:0]const u8,
    owner: linux.uid_t,
    group: linux.gid_t,
    flags: u32,
) File.SetOwnerError!void {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.fchownat(dir, path, owner, group, flags))) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err), // likely fd refers to directory opened without `Dir.OpenOptions.iterate`
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .ACCES => return error.AccessDenied,
            .IO => return error.InputOutput,
            .LOOP => return error.SymLinkLoop,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.FileNotFound,
            .PERM => return error.PermissionDenied,
            .ROFS => return error.ReadOnlyFileSystem,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn flock(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    fd: fd_t,
    op: File.Lock,
    blocking: enum { blocking, nonblocking },
) (File.LockError || error{WouldBlock})!void {
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.flock(fd, LOCK.NB | @as(i32, switch (op) {
            .none => LOCK.UN,
            .shared => LOCK.SH,
            .exclusive => LOCK.EX,
        })))) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err), // invalid parameters
            .NOLCK => return error.SystemResources,
            .AGAIN => {
                const thread = try sync.cancel_region.awaitIoUring();
                thread.enqueue().* = .{
                    .opcode = .NOP,
                    .flags = 0,
                    .ioprio = 0,
                    .fd = 0,
                    .off = 0,
                    .addr = 0,
                    .len = 0,
                    .rw_flags = 0,
                    .user_data = @intFromPtr(sync.cancel_region.fiber),
                    .buf_index = 0,
                    .personality = 0,
                    .splice_fd_in = 0,
                    .addr3 = 0,
                    .resv = 0,
                };
                ev.yield(null, .nothing);
                switch (sync.cancel_region.errno()) {
                    .SUCCESS, .INTR, .CANCELED => {},
                    else => unreachable,
                }
                switch (blocking) {
                    .blocking => continue,
                    .nonblocking => return error.WouldBlock,
                }
            },
            .OPNOTSUPP => return error.FileLocksUnsupported,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn getsockname(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    socket_fd: fd_t,
    addr: *linux.sockaddr,
    addr_len: *linux.socklen_t,
) !void {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.getsockname(socket_fd, addr, addr_len))) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err), // invalid parameters
            .NOTSOCK => |err| return errnoBug(err), // always a race condition
            .NOBUFS => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn linkat(
    ev: *Evented,
    cancel_region: *CancelRegion,
    old_dir: fd_t,
    old_path: [*:0]const u8,
    new_dir: fd_t,
    new_path: [*:0]const u8,
    flags: u32,
) File.HardLinkError!void {
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .LINKAT,
            .flags = 0,
            .ioprio = 0,
            .fd = old_dir,
            .off = @intFromPtr(new_path),
            .addr = @intFromPtr(old_path),
            .len = @bitCast(new_dir),
            .rw_flags = flags,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .ACCES => return error.AccessDenied,
            .DQUOT => return error.DiskQuota,
            .EXIST => return error.PathAlreadyExists,
            .IO => return error.HardwareFailure,
            .LOOP => return error.SymLinkLoop,
            .MLINK => return error.LinkQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .ROFS => return error.ReadOnlyFileSystem,
            .XDEV => return error.CrossDevice,
            .ILSEQ => return error.BadPathName,
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn lseek(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    fd: fd_t,
    offset: u64,
    whence: u32,
) File.SeekError!void {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        var result: u64 = undefined;
        switch (linux.errno(switch (@sizeOf(usize)) {
            else => comptime unreachable,
            4 => linux.llseek(fd, offset, &result, whence),
            8 => linux.lseek(fd, @bitCast(offset), whence),
        })) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .INVAL => return error.Unseekable,
            .OVERFLOW => return error.Unseekable,
            .SPIPE => return error.Unseekable,
            .NXIO => return error.Unseekable,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn openat(
    ev: *Evented,
    cancel_region: *CancelRegion,
    dir: fd_t,
    path: [*:0]const u8,
    flags: linux.O,
    mode: linux.mode_t,
) !fd_t {
    var mut_flags = flags;
    if (@hasField(linux.O, "LARGEFILE")) mut_flags.LARGEFILE = true;
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .OPENAT,
            .flags = 0,
            .ioprio = 0,
            .fd = dir,
            .off = 0,
            .addr = @intFromPtr(path),
            .len = mode,
            .rw_flags = @bitCast(mut_flags),
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        const completion = cancel_region.completion();
        switch (completion.errno()) {
            .SUCCESS => return completion.result,
            .INTR, .CANCELED => {},
            .FAULT => |err| return errnoBug(err),
            .INVAL => return error.BadPathName,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .ACCES => return error.AccessDenied,
            .FBIG => return error.FileTooBig,
            .OVERFLOW => return error.FileTooBig,
            .ISDIR => return error.IsDir,
            .LOOP => return error.SymLinkLoop,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NODEV => return error.NoDevice,
            .NOENT => return error.FileNotFound,
            .SRCH => return error.FileNotFound, // Linux when opening procfs files.
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .EXIST => return error.PathAlreadyExists,
            .BUSY => return error.DeviceBusy,
            // This can be triggered by file locking and TMPFILE, but those
            // flags are mutually exclusive.
            .OPNOTSUPP => return error.OperationUnsupported,
            .AGAIN => return error.WouldBlock,
            .TXTBSY => return error.FileBusy,
            .NXIO => return error.NoDevice,
            .ROFS => return error.ReadOnlyFileSystem,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn preadv(
    ev: *Evented,
    cancel_region: *CancelRegion,
    fd: fd_t,
    iov: []const iovec,
    offset: ?u64,
) File.Reader.Error!usize {
    if (iov.len == 0) return 0;
    const gather = iov.len > 1 or iov[0].len > 0xfffff000;
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = if (gather) .READV else .READ,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = offset orelse std.math.maxInt(u64),
            .addr = if (gather) @intFromPtr(iov.ptr) else @intFromPtr(iov[0].base),
            .len = @intCast(if (gather) iov.len else iov[0].len),
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        const completion = cancel_region.completion();
        switch (completion.errno()) {
            .SUCCESS => return @as(u32, @bitCast(completion.result)),
            .INTR, .CANCELED => {},
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .AGAIN => return error.WouldBlock,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed
            .IO => return error.InputOutput,
            .ISDIR => return error.IsDir,
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOTCONN => return error.SocketUnconnected,
            .CONNRESET => return error.ConnectionResetByPeer,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn pwritev(
    ev: *Evented,
    cancel_region: *CancelRegion,
    fd: fd_t,
    iov: []const iovec_const,
    offset: ?u64,
) File.Writer.Error!usize {
    if (iov.len == 0) return 0;
    const scatter = iov.len > 1 or iov[0].len > 0xfffff000;
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = if (scatter) .WRITEV else .WRITE,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = offset orelse std.math.maxInt(u64),
            .addr = if (scatter) @intFromPtr(iov.ptr) else @intFromPtr(iov[0].base),
            .len = @intCast(if (scatter) iov.len else iov[0].len),
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        const completion = cancel_region.completion();
        switch (completion.errno()) {
            .SUCCESS => return @as(u32, @bitCast(completion.result)),
            .INTR, .CANCELED => {},
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .AGAIN => return error.WouldBlock,
            .BADF => return error.NotOpenForWriting, // Can be a race condition.
            .DESTADDRREQ => |err| return errnoBug(err), // `connect` was never called.
            .DQUOT => return error.DiskQuota,
            .FBIG => return error.FileTooBig,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .PERM => return error.PermissionDenied,
            .PIPE => return error.BrokenPipe,
            .CONNRESET => |err| return errnoBug(err), // Not a socket handle.
            .BUSY => return error.DeviceBusy,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn readAll(
    ev: *Evented,
    cancel_region: *CancelRegion,
    fd: fd_t,
    buffer: []u8,
) (File.Reader.Error || error{EndOfStream})!void {
    var index: usize = 0;
    while (buffer.len - index != 0) {
        const len = try ev.preadv(cancel_region, fd, &.{
            .{ .base = buffer[index..].ptr, .len = buffer.len - index },
        }, null);
        if (len == 0) return error.EndOfStream;
        index += len;
    }
}

fn realPath(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    fd: fd_t,
    out_buffer: []u8,
) File.RealPathError!usize {
    _ = ev;
    var procfs_buf: [std.fmt.count("/proc/self/fd/{d}\x00", .{std.math.minInt(fd_t)})]u8 = undefined;
    const proc_path = std.fmt.bufPrintSentinel(&procfs_buf, "/proc/self/fd/{d}", .{fd}, 0) catch
        unreachable;
    while (true) {
        try sync.cancel_region.await(.nothing);
        const rc = linux.readlink(proc_path, out_buffer.ptr, out_buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .FAULT => |err| return errnoBug(err),
            .IO => return error.FileSystem,
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.NotDir,
            .ILSEQ => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn renameat(
    ev: *Evented,
    cancel_region: *CancelRegion,
    old_dir: fd_t,
    old_path: [*:0]const u8,
    new_dir: fd_t,
    new_path: [*:0]const u8,
    flags: linux.RENAME,
) Dir.RenameError!void {
    while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .RENAMEAT,
            .flags = 0,
            .ioprio = 0,
            .fd = old_dir,
            .off = @intFromPtr(new_path),
            .addr = @intFromPtr(old_path),
            .len = @bitCast(new_dir),
            .rw_flags = @bitCast(flags),
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .BUSY => return error.FileBusy,
            .DQUOT => return error.DiskQuota,
            .ISDIR => return error.IsDir,
            .IO => return error.HardwareFailure,
            .LOOP => return error.SymLinkLoop,
            .MLINK => return error.LinkQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .EXIST => return error.DirNotEmpty,
            .NOTEMPTY => return error.DirNotEmpty,
            .ROFS => return error.ReadOnlyFileSystem,
            .XDEV => return error.CrossDevice,
            .ILSEQ => return error.BadPathName,
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn setsockopt(
    ev: *Evented,
    cancel_region: *CancelRegion,
    fd: fd_t,
    level: i32,
    opt_name: u32,
    option: u32,
) !void {
    const o: []const u8 = @ptrCast(&option);
    while (true) {
        const off: extern struct {
            cmd_op: linux.IO_URING_SOCKET_OP,
            pad: u32,
        } align(@alignOf(u64)) = .{
            .cmd_op = .SETSOCKOPT,
            .pad = 0,
        };
        const addr: extern struct { level: i32, opt_name: u32 } align(@alignOf(u64)) = .{
            .level = level,
            .opt_name = opt_name,
        };
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .URING_CMD,
            .flags = 0,
            .ioprio = 0,
            .fd = fd,
            .off = @as(*const u64, @ptrCast(&off)).*,
            .addr = @as(*const u64, @ptrCast(&addr)).*,
            .len = 0,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = @intCast(o.len),
            .addr3 = @intFromPtr(o.ptr),
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return,
            .INTR, .CANCELED => {},
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .NOTSOCK => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn socket(
    ev: *Evented,
    cancel_region: *CancelRegion,
    family: linux.sa_family_t,
    options: net.IpAddress.BindOptions,
) error{
    AddressFamilyUnsupported,
    ProtocolUnsupportedBySystem,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    SystemResources,
    ProtocolUnsupportedByAddressFamily,
    SocketModeUnsupported,
    OptionUnsupported,
    Unexpected,
    Canceled,
}!fd_t {
    const mode, const protocol = try posixSocketModeProtocol(family, options.mode, options.protocol);
    const socket_fd = while (true) {
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .SOCKET,
            .flags = 0,
            .ioprio = 0,
            .fd = family,
            .off = mode | linux.SOCK.CLOEXEC,
            .addr = 0,
            .len = protocol,
            .rw_flags = 0,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        const completion = cancel_region.completion();
        switch (completion.errno()) {
            .SUCCESS => break completion.result,
            .INTR, .CANCELED => {},
            .AFNOSUPPORT => return error.AddressFamilyUnsupported,
            .INVAL => return error.ProtocolUnsupportedBySystem,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .PROTONOSUPPORT => return error.ProtocolUnsupportedByAddressFamily,
            .PROTOTYPE => return error.SocketModeUnsupported,
            else => |err| return unexpectedErrno(err),
        }
    };
    errdefer ev.closeAsync(socket_fd);

    if (options.ip6_only) {
        if (linux.IPV6 == void) return error.OptionUnsupported;
        try ev.setsockopt(cancel_region, socket_fd, linux.IPPROTO.IPV6, linux.IPV6.V6ONLY, 0);
    }

    return socket_fd;
}

fn stat(ev: *Evented, cancel_region: *CancelRegion, fd: fd_t) Dir.StatError!Dir.Stat {
    return ev.statx(cancel_region, fd, "", linux.AT.EMPTY_PATH) catch |err| switch (err) {
        error.BadPathName, error.NameTooLong => unreachable, // path is empty
        error.AccessDenied => return errnoBug(.ACCES),
        error.SymLinkLoop => return errnoBug(.LOOP),
        error.FileNotFound => return errnoBug(.NOENT),
        error.NotDir => return errnoBug(.NOTDIR),
        else => |e| return e,
    };
}

fn statx(
    ev: *Evented,
    cancel_region: *CancelRegion,
    dir: fd_t,
    path: [*:0]const u8,
    flags: u32,
) (Dir.StatError || Dir.PathNameError || error{ FileNotFound, NotDir, SymLinkLoop })!Dir.Stat {
    while (true) {
        var statx_buf = std.mem.zeroes(linux.Statx);
        const thread = try cancel_region.awaitIoUring();
        thread.enqueue().* = .{
            .opcode = .STATX,
            .flags = 0,
            .ioprio = 0,
            .fd = dir,
            .off = @intFromPtr(&statx_buf),
            .addr = @intFromPtr(path),
            .len = @bitCast(linux_statx_request),
            .rw_flags = flags,
            .user_data = @intFromPtr(cancel_region.fiber),
            .buf_index = 0,
            .personality = 0,
            .splice_fd_in = 0,
            .addr3 = 0,
            .resv = 0,
        };
        ev.yield(null, .nothing);
        switch (cancel_region.errno()) {
            .SUCCESS => return statFromLinux(&statx_buf),
            .INTR, .CANCELED => {},
            .ACCES => return error.AccessDenied,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => |err| return errnoBug(err),
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            .NOMEM => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn urandomReadAll(
    ev: *Evented,
    cancel_region: *CancelRegion,
    buffer: []u8,
) (File.OpenError || File.Reader.Error || error{EndOfStream})!void {
    return ev.readAll(cancel_region, try ev.random_fd.open(ev, cancel_region, "/dev/urandom", .{
        .ACCMODE = .RDONLY,
        .CLOEXEC = true,
    }), buffer);
}

fn utimensat(
    ev: *Evented,
    sync: *CancelRegion.Sync,
    dir: fd_t,
    path: [*:0]const u8,
    times: ?*const [2]linux.timespec,
    flags: u32,
) File.SetTimestampsError!void {
    _ = ev;
    while (true) {
        try sync.cancel_region.await(.nothing);
        switch (linux.errno(linux.utimensat(dir, path, times, flags))) {
            .SUCCESS => return,
            .INTR => {},
            .BADF => |err| return errnoBug(err), // always a race condition
            .FAULT => |err| return errnoBug(err),
            .INVAL => |err| return errnoBug(err),
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .ROFS => return error.ReadOnlyFileSystem,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn writeAllSync(sync: *CancelRegion.Sync, fd: fd_t, buffer: []const u8) File.Writer.Error!void {
    var index: usize = 0;
    while (buffer.len - index != 0) index += try writeSync(sync, fd, buffer[index..]);
}

fn writeSync(sync: *CancelRegion.Sync, fd: fd_t, buffer: []const u8) File.Writer.Error!usize {
    while (true) {
        try sync.cancel_region.await(.nothing);
        const rc = linux.write(fd, buffer.ptr, buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => {},
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .AGAIN => return error.WouldBlock,
            .BADF => return error.NotOpenForWriting, // Can be a race condition.
            .DESTADDRREQ => |err| return errnoBug(err), // `connect` was never called.
            .DQUOT => return error.DiskQuota,
            .FBIG => return error.FileTooBig,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .PERM => return error.PermissionDenied,
            .PIPE => return error.BrokenPipe,
            .CONNRESET => |err| return errnoBug(err), // Not a socket handle.
            .BUSY => return error.DeviceBusy,
            else => |err| return unexpectedErrno(err),
        }
    }
}

test {
    _ = Fiber.CancelProtection;
}
