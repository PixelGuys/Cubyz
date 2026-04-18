const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const Argv0 = Io.Threaded.Argv0;
const assert = std.debug.assert;
const builtin = @import("builtin");
const c = std.c;
const ChdirError = Io.Threaded.ChdirError;
const clockToPosix = Io.Threaded.clockToPosix;
const closeFd = Io.Threaded.closeFd;
const Csprng = Io.Threaded.Csprng;
const default_PATH = Io.Threaded.default_PATH;
const Dir = Io.Dir;
const Environ = Io.Threaded.Environ;
const errnoBug = Io.Threaded.errnoBug;
const Evented = @This();
const fallbackSeed = Io.Threaded.fallbackSeed;
const File = Io.File;
const Io = std.Io;
const iovec = std.posix.iovec;
const iovec_const = std.posix.iovec_const;
const log = std.log.scoped(.dispatch);
const max_iovecs_len = Io.Threaded.max_iovecs_len;
const nanosecondsFromPosix = Io.Threaded.nanosecondsFromPosix;
const net = Io.net;
const pathToPosix = Io.Threaded.pathToPosix;
const process = std.process;
const recoverableOsBugDetected = Io.Threaded.recoverableOsBugDetected;
const setTimestampToPosix = Io.Threaded.setTimestampToPosix;
const splat_buffer_size = Io.Threaded.splat_buffer_size;
const statFromPosix = Io.Threaded.statFromPosix;
const statusToTerm = Io.Threaded.statusToTerm;
const std = @import("std");
const timestampFromPosix = Io.Threaded.timestampFromPosix;
const unexpectedErrno = std.posix.unexpectedErrno;
const UseSendfile = Io.Threaded.UseSendfile;
const UseFcopyfile = Io.Threaded.UseFcopyfile;

/// Empirically saw >4KB being used by the llvm aarch64 backend.
const main_loop_stack_size = 8 * 1024;

queue: c.dispatch.queue_t,
backing_allocator_needs_mutex: bool,
backing_allocator_mutex: Mutex,
/// Does not need to be thread-safe if not used elsewhere.
backing_allocator: Allocator,
main_fiber: Fiber,
main_loop_stack: [*]align(builtin.target.stackAlignment()) u8,
exit_semaphore: c.dispatch.semaphore_t,

use_sendfile: UseSendfile,
use_fcopyfile: UseFcopyfile,
leeway: u64,

futexes: [1 << 8]Futex,

init_stderr_writer: c.dispatch.once_t,
stderr_mutex: Mutex,
stderr_writer: File.Writer,
stderr_mode: Io.Terminal.Mode,

scan_environ: c.dispatch.once_t,
environ: Environ,

open_dev_null: c.dispatch.once_t,
dev_null_file: File.OpenError!File,

csprng_mutex: Mutex,
csprng: Csprng,

const Thread = struct {
    main_context: Io.fiber.Context,
    current_context: ?*Io.fiber.Context,
    seed_csprng: c.dispatch.once_t,
    csprng: Csprng,

    threadlocal var self: Thread = .{
        .main_context = undefined,
        .current_context = null,
        .seed_csprng = .init,
        .csprng = undefined,
    };

    noinline fn current() *Thread {
        return &self;
    }

    fn currentFiber(thread: *Thread) *Fiber {
        assert(thread.current_context != &thread.main_context);
        return @fieldParentPtr("context", thread.current_context.?);
    }

    const List = struct {
        allocated: []Thread,
        reserved: u32,
        active: u32,
    };
};

const Fiber = struct {
    required_align: void align(4),
    evented: *Evented,
    context: Io.fiber.Context,
    link: union {
        awaiter: ?*Fiber,
        group: struct { prev: ?*Fiber, next: ?*Fiber },
    },
    awaiting_group: Group,
    cancel_status: CancelStatus,
    cancel_protection: CancelProtection,

    var next_name: u64 = 0;

    const CancelStatus = packed struct(usize) {
        requested: bool,
        awaiting: Awaiting,

        const unrequested: CancelStatus = .{ .requested = false, .awaiting = .nothing };

        const Awaiting = enum(@Int(.unsigned, @bitSizeOf(usize) - shift)) {
            nothing = 0,
            group = 1,
            _,

            const shift = 1;

            fn subWrap(lhs: Awaiting, rhs: Awaiting) Awaiting {
                return @enumFromInt(@intFromEnum(lhs) -% @intFromEnum(rhs));
            }

            fn fromCancelable(cancelable: *Cancelable) Awaiting {
                return @enumFromInt(@shrExact(@intFromPtr(cancelable), shift));
            }

            fn toCancelable(awaiting: Awaiting) *Cancelable {
                return @ptrFromInt(@shlExact(@as(usize, @intFromEnum(awaiting)), shift));
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
            }, .release);
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

    fn create(ev: *Evented) error{OutOfMemory}!*Fiber {
        return @ptrCast(try ev.allocator().alignedAlloc(u8, .of(Fiber), allocation_size));
    }

    fn destroy(fiber: *Fiber, ev: *Evented) void {
        ev.allocator().free(fiber.allocatedSlice());
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
            .{ .requested = true, .awaiting = .nothing },
            .acquire,
        );
        assert(!cancel_status.requested);
        switch (cancel_status.awaiting) {
            .nothing => {},
            .group => {
                // The awaiter received a cancelation request while awaiting a group,
                // so propagate the cancelation to the group.
                if (fiber.awaiting_group.cancel(ev, null)) {
                    fiber.awaiting_group = undefined;
                    ev.queue.async(fiber, &Fiber.@"resume");
                }
            },
            _ => |awaiting| awaiting.toCancelable().async(),
        }
    }

    fn @"resume"(context: ?*anyopaque) callconv(.c) void {
        const fiber: *Fiber = @ptrCast(@alignCast(context));
        const thread: *Thread = .current();
        const message: SwitchMessage = .{
            .contexts = .{
                .old = &thread.main_context,
                .new = &fiber.context,
            },
            .pending_task = .nothing,
        };
        contextSwitch(&message).handle(fiber.evented);
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
    ev.backing_allocator_mutex.lockUncancelable(ev);
    defer ev.backing_allocator_mutex.unlock();
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
    ev.backing_allocator_mutex.lockUncancelable(ev);
    defer ev.backing_allocator_mutex.unlock();
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
    ev.backing_allocator_mutex.lockUncancelable(ev);
    defer ev.backing_allocator_mutex.unlock();
    return ev.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
}

fn free(userdata: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    ev.backing_allocator_mutex.lockUncancelable(ev);
    defer ev.backing_allocator_mutex.unlock();
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
            .netBindIp = netBindIpUnavailable,
            .netConnectIp = netConnectIpUnavailable,
            .netListenUnix = netListenUnixUnavailable,
            .netConnectUnix = netConnectUnixUnavailable,
            .netSocketCreatePair = netSocketCreatePairUnavailable,
            .netSend = netSendUnavailable,
            .netRead = netReadUnavailable,
            .netWrite = netWriteUnavailable,
            .netWriteFile = netWriteFileUnavailable,
            .netClose = netClose,
            .netShutdown = netShutdownUnavailable,
            .netInterfaceNameResolve = netInterfaceNameResolveUnavailable,
            .netInterfaceName = netInterfaceNameUnavailable,
            .netLookup = netLookupUnavailable,
        },
    };
}

pub const InitOptions = struct {
    backing_allocator_needs_mutex: bool = true,
    target_queue: ?c.dispatch.queue_t = .TARGET_DEFAULT,
    /// Upper limit on the allowable delay in processing timeouts in order to improve power
    /// consumption and system performance.
    leeway: Io.Duration = .fromMilliseconds(10),

    /// Affects the following operations:
    /// * `processExecutablePath` on OpenBSD and Haiku.
    argv0: Argv0 = .empty,
    /// Affects the following operations:
    /// * `fileIsTty`
    /// * `processSpawn`, `processSpawnPath`, `processReplace`, `processReplacePath`
    environ: process.Environ = .empty,
};

pub fn init(ev: *Evented, backing_allocator: Allocator, options: InitOptions) !void {
    const queue = c.dispatch.queue_create_with_target(
        "org.ziglang.std.Io.Dispatch",
        .CONCURRENT(),
        options.target_queue,
    ) orelse return error.SystemResources;
    errdefer queue.as_object().release();
    const main_loop_stack = try backing_allocator.alignedAlloc(
        u8,
        .fromByteUnits(builtin.target.stackAlignment()),
        main_loop_stack_size,
    );
    errdefer backing_allocator.free(main_loop_stack);
    const exit_semaphore = c.dispatch.semaphore_create(0) orelse return error.SystemResources;
    errdefer exit_semaphore.as_object().release();
    ev.* = .{
        .queue = queue,
        .backing_allocator_needs_mutex = options.backing_allocator_needs_mutex,
        .backing_allocator_mutex = undefined,
        .backing_allocator = backing_allocator,
        .main_fiber = .{
            .required_align = {},
            .evented = ev,
            .context = undefined,
            .link = .{ .awaiter = null },
            .awaiting_group = undefined,
            .cancel_status = .unrequested,
            .cancel_protection = .unblocked,
        },
        .main_loop_stack = main_loop_stack.ptr,
        .exit_semaphore = exit_semaphore,

        .use_fcopyfile = .default,
        .use_sendfile = .default,
        .leeway = std.math.lossyCast(u64, options.leeway.toNanoseconds()),

        .futexes = undefined,

        .init_stderr_writer = .init,
        .stderr_mutex = undefined,
        .stderr_writer = .{
            .io = ev.io(),
            .interface = Io.File.Writer.initInterface(&.{}),
            .file = .stderr(),
            .mode = .streaming,
        },
        .stderr_mode = .no_color,

        .scan_environ = if (options.environ.block.isEmpty()) .done else .init,
        .environ = .{ .process_environ = options.environ },

        .open_dev_null = .init,
        .dev_null_file = error.FileNotFound,

        .csprng_mutex = undefined,
        .csprng = .uninitialized,
    };
    try ev.backing_allocator_mutex.init(queue);
    errdefer ev.backing_allocator_mutex.deinit();
    var initialized_futexes: usize = 0;
    errdefer for (ev.futexes[0..initialized_futexes]) |*futex| futex.deinit();
    for (&ev.futexes) |*futex| {
        try futex.init(queue);
        initialized_futexes += 1;
    }
    try ev.stderr_mutex.init(queue);
    errdefer ev.stderr_mutex.deinit();
    try ev.csprng_mutex.init(queue);
    errdefer ev.csprng_mutex.deinit();
    const thread: *Thread = .current();
    thread.main_context = switch (builtin.cpu.arch) {
        .aarch64 => .{
            .sp = @intFromPtr(main_loop_stack[main_loop_stack_size..].ptr),
            .fp = @intFromPtr(ev),
            .pc = @intFromPtr(&mainLoopEntry),
        },
        .x86_64 => .{
            .rsp = @intFromPtr(main_loop_stack[main_loop_stack_size..].ptr) - 8,
            .rbp = @intFromPtr(ev),
            .rip = @intFromPtr(&mainLoopEntry),
        },
        else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
    };
    thread.current_context = &ev.main_fiber.context;
}

pub fn deinit(ev: *Evented) void {
    assert(Thread.current().currentFiber() == &ev.main_fiber);
    ev.yield(.exit);
    ev.csprng_mutex.deinit();
    if (ev.dev_null_file) |file| fileClose(ev, &.{file}) else |_| {}
    ev.stderr_mutex.deinit();
    for (&ev.futexes) |*futex| futex.deinit();
    ev.exit_semaphore.as_object().release();
    ev.backing_allocator.free(ev.main_loop_stack[0..main_loop_stack_size]);
    ev.queue.as_object().release();
}

fn yield(ev: *Evented, pending_task: SwitchMessage.PendingTask) void {
    const thread: *Thread = .current();
    const message: SwitchMessage = .{
        .contexts = .{
            .old = thread.current_context.?,
            .new = &thread.main_context,
        },
        .pending_task = pending_task,
    };
    contextSwitch(&message).handle(ev);
}

fn mainLoopEntry() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .aarch64 => asm volatile (
            \\ mov x0, fp
            \\ mov fp, #0
            \\ b %[mainLoop]
            :
            : [mainLoop] "X" (&mainLoop),
        ),
        .x86_64 => asm volatile (
            \\ movq %%rbp, %%rdi
            \\ xor %%ebp, %%ebp
            \\ jmp %[mainLoop:P]
            :
            : [mainLoop] "X" (&mainLoop),
        ),
        else => |arch| @compileError("unimplemented architecture: " ++ @tagName(arch)),
    }
}

fn mainLoop(ev: *Evented, message: *const SwitchMessage) callconv(.c) noreturn {
    message.handle(ev);
    assert(ev.exit_semaphore.wait(.FOREVER) == 0);
    Fiber.@"resume"(&ev.main_fiber);
    unreachable; // switched to dead fiber
}

const SwitchMessage = struct {
    contexts: Io.fiber.Switch,
    pending_task: PendingTask,

    const PendingTask = union(enum) {
        nothing,
        await: *Fiber,
        activate: c.dispatch.object_t,
        @"resume": c.dispatch.object_t,
        group_await: Group,
        group_cancel: Group,
        mutex_wait: *Mutex.Waiter,
        futex_wait: *Futex.Waiter,
        futex_wake: *Futex.Waker,
        sleep_wait: *SleepWaiter,
        after: c.dispatch.time_t,
        destroy,
        exit,
    };

    fn handle(message: *const SwitchMessage, ev: *Evented) void {
        const thread: *Thread = .current();
        thread.current_context = message.contexts.new;
        switch (message.pending_task) {
            .nothing => {},
            .await => |awaiting| {
                const awaiter: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (@atomicRmw(?*Fiber, &awaiting.link.awaiter, .Xchg, awaiter, .acq_rel) ==
                    Fiber.finished) ev.queue.async(awaiter, &Fiber.@"resume");
            },
            .activate => |object| object.activate(),
            .@"resume" => |object| object.@"resume"(),
            .group_await => |group| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (group.await(ev, fiber)) ev.queue.async(fiber, &Fiber.@"resume");
            },
            .group_cancel => |group| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                if (group.cancel(ev, fiber)) ev.queue.async(fiber, &Fiber.@"resume");
            },
            .mutex_wait => |waiter| {
                waiter.sleeper =
                    .init(ev.queue, @alignCast(@fieldParentPtr("context", message.contexts.old)));
                switch (waiter.sleeper.fiber.cancel_protection.check()) {
                    .unblocked => {},
                    .blocked => waiter.cancelable = .blocked,
                }
                waiter.mutex.queue.async(waiter, &Mutex.Waiter.add);
            },
            .futex_wait => |waiter| {
                waiter.sleeper =
                    .init(ev.queue, @alignCast(@fieldParentPtr("context", message.contexts.old)));
                switch (waiter.sleeper.fiber.cancel_protection.check()) {
                    .unblocked => {},
                    .blocked => waiter.cancelable = .blocked,
                }
                waiter.futex.queue.async(waiter, &Futex.Waiter.add);
            },
            .futex_wake => |waker| {
                waker.sleeper =
                    .init(ev.queue, @alignCast(@fieldParentPtr("context", message.contexts.old)));
                waker.futex.queue.async(waker, &Futex.Waker.remove);
            },
            .sleep_wait => |waiter| {
                waiter.sleeper =
                    .init(ev.queue, @alignCast(@fieldParentPtr("context", message.contexts.old)));
                const queue = waiter.cancelable.queue;
                switch (waiter.sleeper.fiber.cancel_protection.check()) {
                    .unblocked => {},
                    .blocked => waiter.cancelable = .blocked,
                }
                queue.async(waiter, &SleepWaiter.start);
            },
            .after => |when| {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                when.after(ev.queue, fiber, &Fiber.@"resume");
            },
            .destroy => {
                const fiber: *Fiber = @alignCast(@fieldParentPtr("context", message.contexts.old));
                fiber.destroy(ev);
            },
            .exit => _ = ev.exit_semaphore.signal(),
        }
    }
};

inline fn contextSwitch(message: *const SwitchMessage) *const SwitchMessage {
    return @fieldParentPtr("contexts", Io.fiber.contextSwitch(&message.contexts));
}

const Cancelable = struct {
    required_align: void align(2) = {},
    queue: c.dispatch.queue_t,
    cancel: c.dispatch.function_t,

    const fn_ptr_align = std.meta.alignment(c.dispatch.function_t);
    const is_blocked: c.dispatch.function_t = @ptrFromInt(fn_ptr_align * 1);
    const is_requested: c.dispatch.function_t = @ptrFromInt(fn_ptr_align * 2);

    const blocked: Cancelable = .{ .queue = undefined, .cancel = is_blocked };

    const RequestedError = error{CancelRequested};

    fn enter(cancelable: *Cancelable, fiber: *Fiber) RequestedError!void {
        const function = cancelable.cancel;
        assert(function != is_requested);
        if (function == is_blocked) {
            @branchHint(.unlikely);
            return;
        }
        if (@cmpxchgStrong(
            Fiber.CancelStatus,
            &fiber.cancel_status,
            .{ .requested = false, .awaiting = .nothing },
            .{ .requested = false, .awaiting = .fromCancelable(cancelable) },
            .release,
            .monotonic,
        )) |cancel_status| {
            assert(cancel_status.requested and cancel_status.awaiting == .nothing);
            cancelable.cancel = is_requested;
            return error.CancelRequested;
        }
    }

    fn leave(cancelable: *Cancelable, fiber: *Fiber) RequestedError!void {
        const function = cancelable.cancel;
        assert(function != is_requested);
        if (function == is_blocked) {
            @branchHint(.unlikely);
            return;
        }
        const cancel_status = @atomicRmw(Fiber.CancelStatus, &fiber.cancel_status, .And, .{
            .requested = true,
            .awaiting = .nothing,
        }, .monotonic);
        assert(cancel_status.awaiting.toCancelable() == cancelable);
        if (cancel_status.requested) return error.CancelRequested;
    }

    fn async(cancelable: *Cancelable) void {
        const function = cancelable.cancel;
        assert(function != is_blocked and function != is_requested);
        cancelable.queue.async(cancelable, function);
    }

    fn requested(cancelable: *Cancelable, fiber: *Fiber) void {
        const function = cancelable.cancel;
        assert(function != is_blocked and function != is_requested);
        assert(@atomicLoad(Fiber.CancelStatus, &fiber.cancel_status, .monotonic) == Fiber.CancelStatus{
            .requested = true,
            .awaiting = .fromCancelable(cancelable),
        });
        cancelable.cancel = is_requested;
        @atomicStore(Fiber.CancelStatus, &fiber.cancel_status, .{
            .requested = true,
            .awaiting = .nothing,
        }, .monotonic);
    }

    fn acknowledge(cancelable: *Cancelable, fiber: *Fiber) Io.Cancelable!void {
        if (cancelable.cancel == is_requested) {
            @branchHint(.unlikely);
            fiber.cancel_protection.acknowledge();
            return error.Canceled;
        }
    }
};

const Sleeper = struct {
    queue: c.dispatch.queue_t,
    fiber: *Fiber,

    fn init(queue: c.dispatch.queue_t, fiber: *Fiber) Sleeper {
        queue.as_object().retain();
        return .{ .queue = queue, .fiber = fiber };
    }

    fn wake(context: ?*anyopaque) callconv(.c) void {
        const sleeper: *Sleeper = @ptrCast(@alignCast(context));
        const queue = sleeper.queue;
        sleeper.queue = undefined;
        queue.async(sleeper.fiber, &Fiber.@"resume");
        queue.as_object().release();
    }
};

const Mutex = struct {
    state: State,
    queue: c.dispatch.queue_t,
    waiters: std.DoublyLinkedList,

    const State = packed struct(usize) {
        locked: bool,
        num_waiters: NumWaiters,

        const NumWaiters = @Int(.unsigned, @bitSizeOf(usize) - 1);
    };

    const Waiter = struct {
        sleeper: Sleeper = undefined,
        cancelable: Cancelable,
        mutex: *Mutex,
        node: std.DoublyLinkedList.Node = undefined,

        fn add(context: ?*anyopaque) callconv(.c) void {
            const waiter: *Waiter = @ptrCast(@alignCast(context));
            waiter.cancelable.enter(waiter.sleeper.fiber) catch |err| switch (err) {
                error.CancelRequested => return waiter.wake(),
            };
            var state = @atomicRmw(State, &waiter.mutex.state, .Add, .{
                .locked = false,
                .num_waiters = 1,
            }, .monotonic);
            state.num_waiters += 1;
            while (!state.locked) {
                @branchHint(.unlikely);
                state = @cmpxchgWeak(State, &waiter.mutex.state, state, .{
                    .locked = true,
                    .num_waiters = state.num_waiters - 1,
                }, .acquire, .monotonic) orelse break;
            } else return waiter.mutex.waiters.append(&waiter.node);
            waiter.cancelable.leave(waiter.sleeper.fiber) catch |err| switch (err) {
                error.CancelRequested => {
                    waiter.node.next = &waiter.node;
                    return;
                },
            };
            waiter.wake();
        }

        fn canceled(context: ?*anyopaque) callconv(.c) void {
            const cancelable: *Cancelable = @ptrCast(@alignCast(context));
            const waiter: *Waiter = @fieldParentPtr("cancelable", cancelable);
            cancelable.requested(waiter.sleeper.fiber);
            const mutex = waiter.mutex;
            if (waiter.node.next != &waiter.node) {
                @branchHint(.likely);
                mutex.waiters.remove(&waiter.node);
                assert(@atomicRmw(State, &mutex.state, .Sub, .{
                    .locked = false,
                    .num_waiters = 1,
                }, .monotonic).num_waiters >= 1);
            }
            waiter.node = undefined;
            waiter.wake();
        }

        fn remove(context: ?*anyopaque) callconv(.c) void {
            const mutex: *Mutex = @ptrCast(@alignCast(context));
            var state = @atomicLoad(State, &mutex.state, .monotonic);
            while (!state.locked and state.num_waiters > 0) {
                @branchHint(.likely);
                state = @cmpxchgWeak(State, &mutex.state, state, .{
                    .locked = true,
                    .num_waiters = state.num_waiters - 1,
                }, .acquire, .monotonic) orelse break;
            } else return;
            var num_removed: State.NumWaiters = 0;
            while (mutex.waiters.popFirst()) |node| {
                @branchHint(.likely);
                const waiter: *Waiter = @fieldParentPtr("node", node);
                node.* = undefined;
                waiter.cancelable.leave(waiter.sleeper.fiber) catch |err| switch (err) {
                    error.CancelRequested => {
                        num_removed += 1;
                        node.next = node;
                        continue;
                    },
                };
                break;
            }
            if (num_removed > 0) {
                @branchHint(.unlikely);
                assert(@atomicRmw(State, &mutex.state, .Sub, .{
                    .locked = false,
                    .num_waiters = num_removed,
                }, .monotonic).num_waiters >= num_removed);
            }
        }

        fn wake(waiter: *Waiter) void {
            Sleeper.wake(&waiter.sleeper);
        }
    };

    fn init(mutex: *Mutex, queue: c.dispatch.queue_t) error{SystemResources}!void {
        mutex.* = .{
            .state = .{ .locked = false, .num_waiters = 0 },
            .queue = c.dispatch.queue_create_with_target(
                "org.ziglang.std.Io.Dispatch.Mutex",
                .SERIAL(),
                queue,
            ) orelse return error.SystemResources,
            .waiters = .{},
        };
    }

    fn deinit(mutex: *Mutex) void {
        assert(mutex.state == State{ .locked = false, .num_waiters = 0 });
        assert(mutex.waiters.first == null and mutex.waiters.last == null);
        mutex.queue.as_object().release();
        mutex.* = undefined;
    }

    fn tryLock(mutex: *Mutex) bool {
        const state =
            @atomicRmw(State, &mutex.state, .Or, .{ .locked = true, .num_waiters = 0 }, .acquire);
        if (state.locked) {
            @branchHint(.unlikely);
        }
        return !state.locked;
    }

    fn lock(mutex: *Mutex, ev: *Evented) Io.Cancelable!void {
        if (mutex.tryLock()) return;
        var waiter: Waiter = .{
            .cancelable = .{ .queue = mutex.queue, .cancel = &Mutex.Waiter.canceled },
            .mutex = mutex,
        };
        ev.yield(.{ .mutex_wait = &waiter });
        try waiter.cancelable.acknowledge(waiter.sleeper.fiber);
    }

    fn lockUncancelable(mutex: *Mutex, ev: *Evented) void {
        if (mutex.tryLock()) return;
        var waiter: Waiter = .{ .cancelable = .blocked, .mutex = mutex };
        ev.yield(.{ .mutex_wait = &waiter });
        waiter.cancelable.acknowledge(waiter.sleeper.fiber) catch |err| switch (err) {
            error.Canceled => unreachable, // blocked
        };
    }

    fn unlock(mutex: *Mutex) void {
        const state = @atomicRmw(State, &mutex.state, .And, .{
            .locked = false,
            .num_waiters = std.math.maxInt(State.NumWaiters),
        }, .release);
        if (state.num_waiters > 0) {
            @branchHint(.unlikely);
            mutex.queue.async(mutex, &Waiter.remove);
        }
    }
};

fn crashHandler(userdata: ?*anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const thread = &Thread.self;
    if (thread.current_context == null) std.process.abort();
    if (thread.current_context == &thread.main_context) std.process.abort();
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
        if (@atomicRmw(?*Fiber, &fiber.link.awaiter, .Xchg, Fiber.finished, .acq_rel)) |awaiter|
            ev.queue.async(awaiter, &Fiber.@"resume");
        ev.yield(.nothing);
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
        .evented = ev,
        .context = switch (builtin.cpu.arch) {
            .aarch64 => .{
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
        .awaiting_group = undefined,
        .cancel_status = .unrequested,
        .cancel_protection = .unblocked,
    };
    closure.* = .{
        .evented = ev,
        .fiber = fiber,
        .start = start,
        .result_align = result_alignment,
    };
    @memcpy(closure.contextPointer(), context);

    ev.queue.async(fiber, &Fiber.@"resume");
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
        ev.yield(.{ .await = awaiting });
    @memcpy(result, awaiting.resultBytes(result_alignment));
    awaiting.destroy(ev);
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
    fn mutexPtr(group: Group) *Group.Mutex {
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
                Group.Mutex,
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
                Group.Mutex,
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
            Group.Mutex,
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
                assert(awaiter.awaiting_group.ptr == group.ptr);
                awaiter.awaiting_group = undefined;
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
        awaiter.awaiting_group = group;
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
            closure.start(closure.contextPointer());
            if (closure.group.removeFiber(ev, fiber)) |awaiter| ev.queue.async(awaiter, &Fiber.@"resume");
            ev.yield(.destroy);
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
        .evented = ev,
        .context = switch (builtin.cpu.arch) {
            .aarch64 => .{
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
        .awaiting_group = undefined,
        .cancel_status = .unrequested,
        .cancel_protection = .unblocked,
    };
    closure.* = .{
        .evented = ev,
        .group = group,
        .fiber = fiber,
        .start = start,
    };
    @memcpy(closure.contextPointer(), context);
    group.addFiber(ev, fiber);
    ev.queue.async(fiber, &Fiber.@"resume");
}

fn groupAwait(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    initial_token: *anyopaque,
) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = initial_token;
    ev.yield(.{ .group_await = .{ .ptr = type_erased } });
}

fn groupCancel(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = initial_token;
    ev.yield(.{ .group_cancel = .{ .ptr = type_erased } });
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

const Futex = struct {
    num_waiters: usize,
    queue: c.dispatch.queue_t,
    waiters: std.DoublyLinkedList,

    const Waiter = struct {
        sleeper: Sleeper = undefined,
        cancelable: Cancelable,
        futex: *Futex,
        node: std.DoublyLinkedList.Node = .{},
        ptr: *const u32,
        expected: u32,
        timeout: c.dispatch.time_t = .FOREVER,
        leeway: u64,
        timer: ?c.dispatch.source_t = null,

        const already_signaled: c.dispatch.source_t = @ptrFromInt(1);

        fn add(context: ?*anyopaque) callconv(.c) void {
            const waiter: *Waiter = @ptrCast(@alignCast(context));
            const futex = waiter.futex;
            _ = @atomicRmw(usize, &futex.num_waiters, .Add, 1, .acquire);
            waiter.tryAdd() catch |err| switch (err) {
                error.CancelRequested => {
                    wake(waiter);
                    assert(@atomicRmw(usize, &futex.num_waiters, .Sub, 1, .monotonic) >= 1);
                },
            };
        }

        fn tryAdd(waiter: *Waiter) Cancelable.RequestedError!void {
            if (@atomicLoad(u32, waiter.ptr, .monotonic) != waiter.expected)
                return error.CancelRequested;
            try waiter.cancelable.enter(waiter.sleeper.fiber);
            const futex = waiter.futex;
            switch (waiter.timeout) {
                .FOREVER => {},
                else => |timeout| {
                    const timer = c.dispatch.source_create(.TIMER, 0, .none, futex.queue) orelse {
                        log.warn("failed to create timer for futex timeout", .{});
                        return error.CancelRequested;
                    };
                    timer.as_object().set_context(waiter);
                    timer.set_event_handler(&timedOut);
                    timer.set_cancel_handler(&wake);
                    timer.set_timer(timeout, c.dispatch.TIME_FOREVER, waiter.leeway);
                    timer.as_object().activate();
                    waiter.timer = timer;
                },
            }
            futex.waiters.append(&waiter.node);
        }

        fn canceled(context: ?*anyopaque) callconv(.c) void {
            const cancelable: *Cancelable = @ptrCast(@alignCast(context));
            const waiter: *Waiter = @fieldParentPtr("cancelable", cancelable);
            cancelable.requested(waiter.sleeper.fiber);
            const futex = waiter.futex;
            waiter.remove();
            assert(@atomicRmw(usize, &futex.num_waiters, .Sub, 1, .monotonic) >= 1);
        }

        fn timedOut(context: ?*anyopaque) callconv(.c) void {
            const waiter: *Waiter = @ptrCast(@alignCast(context));
            const futex = waiter.futex;
            waiter.tryRemove() catch |err| switch (err) {
                error.CancelRequested => return,
            };
            assert(@atomicRmw(usize, &futex.num_waiters, .Sub, 1, .monotonic) >= 1);
        }

        fn tryRemove(waiter: *Waiter) Cancelable.RequestedError!void {
            try waiter.cancelable.leave(waiter.sleeper.fiber);
            waiter.remove();
        }

        fn remove(waiter: *Waiter) void {
            waiter.futex.waiters.remove(&waiter.node);
            if (waiter.timer) |timer| timer.cancel() else wake(waiter);
        }

        fn wake(context: ?*anyopaque) callconv(.c) void {
            const waiter: *Waiter = @ptrCast(@alignCast(context));
            if (waiter.timer) |timer| timer.as_object().release();
            Sleeper.wake(&waiter.sleeper);
        }
    };

    const Waker = struct {
        sleeper: Sleeper = undefined,
        futex: *Futex,
        ptr: *const u32,
        max_waiters: u32,

        fn remove(context: ?*anyopaque) callconv(.c) void {
            const waker: *Waker = @ptrCast(@alignCast(context));
            const futex = waker.futex;
            const ptr = waker.ptr;
            const max_waiters = waker.max_waiters;

            var num_removed: usize = 0;
            var next_node = futex.waiters.first;
            while (num_removed < max_waiters) {
                const waiter: *Waiter = @fieldParentPtr("node", next_node orelse break);
                next_node = waiter.node.next;
                if (waiter.ptr != ptr) {
                    @branchHint(.unlikely);
                    continue;
                }
                waiter.tryRemove() catch |err| switch (err) {
                    error.CancelRequested => continue,
                };
                num_removed += 1;
            }
            assert(@atomicRmw(usize, &futex.num_waiters, .Sub, num_removed, .monotonic) >= num_removed);

            var sleeper = waker.sleeper;
            waker.* = undefined;
            Sleeper.wake(&sleeper);
        }
    };

    fn init(futex: *Futex, queue: c.dispatch.queue_t) error{SystemResources}!void {
        futex.* = .{
            .num_waiters = 0,
            .queue = c.dispatch.queue_create_with_target(
                "org.ziglang.std.Io.Dispatch.Futex",
                .SERIAL(),
                queue,
            ) orelse return error.SystemResources,
            .waiters = .{},
        };
    }

    fn deinit(futex: *Futex) void {
        assert(futex.num_waiters == 0 and futex.waiters.first == null and futex.waiters.last == null);
        futex.queue.as_object().release();
        futex.* = undefined;
    }
};

fn futexForAddress(ev: *Evented, address: usize) *Futex {
    // Here we use Fibonacci hashing: the golden ratio can be used to evenly redistribute input
    // values across a range, giving a poor, but extremely quick to compute, hash.

    // This literal is the rounded value of '2^64 / phi' (where 'phi' is the golden ratio). The
    // shift then converts it to '2^b / phi', where 'b' is the pointer bit width.
    const fibonacci_multiplier = 0x9E3779B97F4A7C15 >> (64 - @bitSizeOf(usize));
    const hashed = address *% fibonacci_multiplier;
    comptime assert(std.math.isPowerOfTwo(ev.futexes.len));
    // The high bits of `hashed` have better entropy than the low bits.
    return &ev.futexes[hashed >> @clz(ev.futexes.len - 1)];
}

fn futexWait(
    userdata: ?*anyopaque,
    ptr: *const u32,
    expected: u32,
    timeout: Io.Timeout,
) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const futex = ev.futexForAddress(@intFromPtr(ptr));
    var waiter: Futex.Waiter = .{
        .cancelable = .{ .queue = futex.queue, .cancel = &Futex.Waiter.canceled },
        .futex = futex,
        .ptr = ptr,
        .expected = expected,
        .timeout = ev.timeFromTimeout(timeout),
        .leeway = ev.leeway,
    };
    ev.yield(.{ .futex_wait = &waiter });
    try waiter.cancelable.acknowledge(waiter.sleeper.fiber);
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const futex = ev.futexForAddress(@intFromPtr(ptr));
    var waiter: Futex.Waiter = .{
        .cancelable = .blocked,
        .futex = futex,
        .ptr = ptr,
        .expected = expected,
        .leeway = ev.leeway,
    };
    ev.yield(.{ .futex_wait = &waiter });
    waiter.cancelable.acknowledge(waiter.sleeper.fiber) catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    };
}

fn futexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (max_waiters == 0) return;
    const futex = ev.futexForAddress(@intFromPtr(ptr));
    switch (@atomicRmw(usize, &futex.num_waiters, .Add, 0, .release)) {
        0 => return,
        else => {
            @branchHint(.unlikely);
            var waker: Futex.Waker = .{ .futex = futex, .ptr = ptr, .max_waiters = max_waiters };
            ev.yield(.{ .futex_wake = &waker });
        },
    }
}

fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    switch (operation) {
        .file_read_streaming => |o| return .{
            .file_read_streaming = ev.fileReadStreaming(o.file, o.data) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .file_write_streaming => |o| return .{
            .file_write_streaming = ev.fileWriteStreaming(
                o.file,
                o.header,
                o.data,
                o.splat,
            ) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .device_io_control => |*o| return .{ .device_io_control = try deviceIoControl(o) },
        .net_receive => @panic("TODO implement net_receive operation"),
    }
}

fn fileReadStreaming(ev: *Evented, file: File, data: []const []u8) File.ReadStreamingError!usize {
    if (file.flags.nonblocking) nonblocking: {
        return fileReadStreamingLimit(file.handle, data, .unlimited) catch |err| switch (err) {
            error.WouldBlock => break :nonblocking,
            else => |e| return e,
        };
    }
    const source = c.dispatch.source_create(
        .READ,
        @bitCast(@as(isize, file.handle)),
        .none,
        ev.queue,
    ) orelse return error.SystemResources;
    source.as_object().set_context(Thread.current().currentFiber());
    source.set_event_handler(&Fiber.@"resume");
    ev.yield(.{ .activate = source.as_object() });
    const limit = source.get_data();
    source.as_object().release();
    while (true) return fileReadStreamingLimit(
        file.handle,
        data,
        .limited(limit),
    ) catch |err| switch (err) {
        error.WouldBlock => {
            ev.yield(.nothing);
            continue;
        },
        else => |e| return e,
    };
}
fn fileReadStreamingLimit(
    handle: File.Handle,
    data: []const []u8,
    limit: Io.Limit,
) File.ReadStreamingError!usize {
    var iovecs: [max_iovecs_len]iovec = undefined;
    var iovlen: iovlen_t = 0;
    // .nothing can mean that the write side has been closed,
    // in which case the buffer still needs to be drained
    var remaining = if (limit == .nothing) .unlimited else limit;
    for (data) |buf| addBuf(false, &iovecs, &iovlen, &remaining, buf);
    if (iovlen == 0) return 0;
    while (true) {
        const rc = c.readv(handle, &iovecs, iovlen);
        switch (c.errno(rc)) {
            .SUCCESS => return if (rc == 0) error.EndOfStream else @intCast(rc),
            .INTR => continue,
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

fn fileWriteStreaming(
    ev: *Evented,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) File.Writer.Error!usize {
    if (file.flags.nonblocking) nonblocking: {
        return fileWriteStreamingLimit(
            file.handle,
            header,
            data,
            splat,
            .unlimited,
        ) catch |err| switch (err) {
            error.WouldBlock => break :nonblocking,
            else => |e| return e,
        };
    }
    const source = c.dispatch.source_create(
        .WRITE,
        @bitCast(@as(isize, file.handle)),
        .none,
        ev.queue,
    ) orelse return error.SystemResources;
    source.as_object().set_context(Thread.current().currentFiber());
    source.set_event_handler(&Fiber.@"resume");
    ev.yield(.{ .activate = source.as_object() });
    const limit = source.get_data();
    source.as_object().release();
    while (true) return fileWriteStreamingLimit(
        file.handle,
        header,
        data,
        splat,
        .limited(limit),
    ) catch |err| switch (err) {
        error.WouldBlock => {
            ev.yield(.nothing);
            continue;
        },
        else => |e| return e,
    };
}
fn fileWriteStreamingLimit(
    handle: File.Handle,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    limit: Io.Limit,
) File.Writer.Error!usize {
    if (limit == .nothing) return 0;
    var iovecs: [max_iovecs_len]iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    var remaining = limit;
    addBuf(true, &iovecs, &iovlen, &remaining, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(true, &iovecs, &iovlen, &remaining, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0 and remaining != .nothing) switch (splat) {
        0 => {},
        1 => addBuf(true, &iovecs, &iovlen, &remaining, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addBuf(true, &iovecs, &iovlen, &remaining, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and iovecs.len - iovlen != 0 and remaining != .nothing) {
                    assert(buf.len == splat_buffer.len);
                    addBuf(true, &iovecs, &iovlen, &remaining, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addBuf(true, &iovecs, &iovlen, &remaining, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - iovlen)) |_| {
                if (remaining == .nothing) break;
                addBuf(true, &iovecs, &iovlen, &remaining, pattern);
            },
        },
    };
    if (iovlen == 0) return 0;
    while (true) {
        const rc = c.writev(handle, &iovecs, iovlen);
        switch (c.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
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

fn deviceIoControl(o: *const Io.Operation.DeviceIoControl) Io.Cancelable!i32 {
    while (true) {
        const rc = c.ioctl(o.file.handle, @bitCast(o.code), @intFromPtr(o.arg));
        switch (c.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => {},
            else => |err| return -@as(i32, @intFromEnum(err)),
        }
    }
}

const BatchWaiter = struct {
    sleeper: Sleeper,
    queue: c.dispatch.queue_t,
    timer: ?c.dispatch.source_t = null,

    const already_signaled: c.dispatch.source_t = @ptrFromInt(1);

    fn signal(context: ?*anyopaque) callconv(.c) void {
        const waiter: *BatchWaiter = @ptrCast(@alignCast(context));
        if (waiter.timer) |timer| {
            if (timer != already_signaled) timer.cancel();
        } else {
            waiter.timer = already_signaled;
            waiter.queue.async(waiter, &@"suspend");
        }
    }

    fn @"suspend"(context: ?*anyopaque) callconv(.c) void {
        const waiter: *BatchWaiter = @ptrCast(@alignCast(context));
        if (waiter.timer) |timer| if (timer != already_signaled) timer.as_object().release();
        waiter.queue.as_object().@"suspend"();
        waiter.wake();
    }

    fn wake(waiter: *BatchWaiter) void {
        var sleeper = waiter.sleeper;
        waiter.* = undefined;
        Sleeper.wake(&sleeper);
    }
};

fn batchAwaitAsync(userdata: ?*anyopaque, batch: *Io.Batch) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const queue = ev.batchDrainSubmitted(batch, false) catch |err| switch (err) {
        error.ConcurrencyUnavailable => unreachable, // passed concurrency=false
        error.Canceled => |e| return e,
    } orelse return;
    if (batch.pending.head == .none) return;
    var waiter: BatchWaiter = .{
        .sleeper = .init(ev.queue, Thread.current().currentFiber()),
        .queue = queue,
    };
    if (batch.completed.head != .none) BatchWaiter.signal(&waiter);
    queue.as_object().set_context(&waiter);
    ev.yield(.{ .@"resume" = queue.as_object() });
}

fn batchAwaitConcurrent(
    userdata: ?*anyopaque,
    batch: *Io.Batch,
    timeout: Io.Timeout,
) Io.Batch.AwaitConcurrentError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const queue = try ev.batchDrainSubmitted(batch, true) orelse return;
    if (batch.pending.head == .none) return;
    var waiter: BatchWaiter = .{
        .sleeper = .init(ev.queue, Thread.current().currentFiber()),
        .queue = queue,
    };
    if (batch.completed.head == .none) switch (timeout) {
        .none => {},
        else => {
            const timer = c.dispatch.source_create(.TIMER, 0, .none, queue) orelse
                return error.ConcurrencyUnavailable;
            assert(timer != BatchWaiter.already_signaled);
            timer.as_object().set_context(&waiter);
            timer.set_event_handler(&BatchWaiter.signal);
            timer.set_cancel_handler(&BatchWaiter.@"suspend");
            timer.set_timer(ev.timeFromTimeout(timeout), c.dispatch.TIME_FOREVER, ev.leeway);
            timer.as_object().activate();
            waiter.timer = timer;
        },
    } else BatchWaiter.signal(&waiter);
    queue.as_object().set_context(&waiter);
    ev.yield(.{ .@"resume" = queue.as_object() });
}

fn batchCancel(userdata: ?*anyopaque, batch: *Io.Batch) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    var index = batch.pending.head;
    while (index != .none) {
        const storage = &batch.storage[index.toIndex()];
        const pending = &storage.pending;
        const operation_userdata: *BatchOperationUserdata = .fromErased(&pending.userdata);
        assert(operation_userdata.batch == batch);
        operation_userdata.source.cancel();
    }
    const queue: c.dispatch.queue_t = @ptrCast(batch.userdata orelse return);
    if (batch.pending.head != .none) {
        var waiter: BatchWaiter = .{
            .sleeper = .init(ev.queue, Thread.current().currentFiber()),
            .queue = queue,
            .timer = BatchWaiter.already_signaled,
        };
        if (batch.pending.head == .none) queue.async(&waiter, &BatchWaiter.signal);
        queue.as_object().set_context(&waiter);
        ev.yield(.{ .@"resume" = queue.as_object() });
    }
    batch.userdata = null;
}

const BatchOperationUserdata = extern struct {
    batch: *Io.Batch,
    source: c.dispatch.source_t,
    operation: extern union {
        file_read_streaming: extern struct {
            data_ptr: [*]const []u8,
            data_len: usize,
        },
        file_write_streaming: extern struct {
            header_ptr: [*]const u8,
            header_len: usize,
            data_ptr: [*]const []const u8,
            data_len: usize,
            splat: usize,

            fn header(operation: *const @This()) []const u8 {
                return operation.header_ptr[0..operation.header_len];
            }

            fn data(operation: *const @This()) []const []const u8 {
                return operation.data_ptr[0..operation.data_len];
            }
        },
    },

    const Erased = Io.Operation.Storage.Pending.Userdata;

    comptime {
        assert(@sizeOf(BatchOperationUserdata) <= @sizeOf(Erased));
    }

    fn toErased(userdata: *BatchOperationUserdata) *Erased {
        return @ptrCast(userdata);
    }

    fn fromErased(erased: *Erased) *BatchOperationUserdata {
        return @ptrCast(erased);
    }
};

/// If `concurrency` is false, `error.ConcurrencyUnavailable` is unreachable.
fn batchDrainSubmitted(
    ev: *Evented,
    batch: *Io.Batch,
    concurrency: bool,
) (Io.ConcurrentError || Io.Cancelable)!?c.dispatch.queue_t {
    var index = batch.submitted.head;
    if (index == .none) return @ptrCast(batch.userdata);
    errdefer batch.submitted.head = index;
    const maybe_queue: ?c.dispatch.queue_t = if (batch.userdata) |batch_userdata|
        @ptrCast(batch_userdata)
    else maybe_queue: {
        const queue = c.dispatch.queue_create_with_target(
            "org.ziglang.std.Io.Dispatch.Batch",
            .SERIAL(),
            ev.queue,
        ) orelse if (concurrency) return error.ConcurrencyUnavailable else break :maybe_queue null;
        queue.as_object().@"suspend"();
        batch.userdata = queue;
        break :maybe_queue queue;
    };
    while (index != .none) {
        const storage = &batch.storage[index.toIndex()];
        const next_index = storage.submission.node.next;
        if (@as(?Io.Operation.Result, result: {
            if (maybe_queue) |queue| switch (storage.submission.operation) {
                .file_read_streaming => |operation| {
                    const data = for (operation.data, 0..) |buffer, data_index| {
                        if (buffer.len > 0) break operation.data[data_index..];
                    } else break :result .{ .file_read_streaming = 0 };
                    const source = c.dispatch.source_create(
                        .READ,
                        @bitCast(@as(isize, operation.file.handle)),
                        .none,
                        queue,
                    ) orelse break :result .{ .file_read_streaming = error.SystemResources };
                    storage.* = .{ .pending = .{
                        .node = .{ .prev = batch.pending.tail, .next = .none },
                        .tag = .file_read_streaming,
                        .userdata = undefined,
                    } };
                    const operation_userdata: *BatchOperationUserdata =
                        .fromErased(&storage.pending.userdata);
                    operation_userdata.* = .{
                        .batch = batch,
                        .source = source,
                        .operation = .{ .file_read_streaming = .{
                            .data_ptr = data.ptr,
                            .data_len = data.len,
                        } },
                    };
                    source.as_object().set_context(storage);
                    source.set_event_handler(&batchSourceEvent);
                    source.set_cancel_handler(&batchSourceCancel);
                    source.as_object().activate();
                    break :result null;
                },
                .file_write_streaming => |operation| {
                    const data = for (operation.data, 0..) |buffer, data_index| {
                        if (buffer.len > 0) break operation.data[data_index..];
                    } else if (operation.header.len > 0)
                        operation.data[0..1]
                    else
                        break :result .{ .file_write_streaming = 0 };
                    const source = c.dispatch.source_create(
                        .WRITE,
                        @bitCast(@as(isize, operation.file.handle)),
                        .none,
                        queue,
                    ) orelse break :result .{ .file_write_streaming = error.SystemResources };
                    storage.* = .{ .pending = .{
                        .node = .{ .prev = batch.pending.tail, .next = .none },
                        .tag = .file_write_streaming,
                        .userdata = undefined,
                    } };
                    const operation_userdata: *BatchOperationUserdata =
                        .fromErased(&storage.pending.userdata);
                    operation_userdata.* = .{
                        .batch = batch,
                        .source = source,
                        .operation = .{ .file_write_streaming = .{
                            .header_ptr = operation.header.ptr,
                            .header_len = operation.header.len,
                            .data_ptr = data.ptr,
                            .data_len = data.len,
                            .splat = operation.splat,
                        } },
                    };
                    source.as_object().set_context(storage);
                    source.set_event_handler(&batchSourceEvent);
                    source.set_cancel_handler(&batchSourceCancel);
                    source.as_object().activate();
                    break :result null;
                },
                .device_io_control => {},
                .net_receive => @panic("TODO implement batched net_receive"),
            };
            if (concurrency) return error.ConcurrencyUnavailable;
            break :result try operate(ev, storage.submission.operation);
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
        }
        index = next_index;
    }
    batch.submitted = .{ .head = .none, .tail = .none };
    return maybe_queue;
}

fn batchSourceEvent(context: ?*anyopaque) callconv(.c) void {
    const storage: *Io.Operation.Storage = @ptrCast(@alignCast(context));
    const pending = &storage.pending;
    const operation_userdata: *BatchOperationUserdata = .fromErased(&pending.userdata);
    const batch = operation_userdata.batch;
    const source = operation_userdata.source;
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - batch.storage.ptr);
    const result: Io.Operation.Result = result: switch (pending.tag) {
        .file_read_streaming => {
            const operation = &operation_userdata.operation.file_read_streaming;
            break :result .{ .file_read_streaming = fileReadStreamingLimit(
                @intCast(source.get_handle()),
                operation.data_ptr[0..operation.data_len],
                .limited(source.get_data()),
            ) catch |err| switch (err) {
                error.Canceled => return Thread.current().currentFiber().cancel_protection.recancel(),
                error.WouldBlock => return,
                else => |e| e,
            } };
        },
        .file_write_streaming => {
            const operation = &operation_userdata.operation.file_write_streaming;
            break :result .{ .file_write_streaming = fileWriteStreamingLimit(
                @intCast(source.get_handle()),
                operation.header_ptr[0..operation.header_len],
                operation.data_ptr[0..operation.data_len],
                operation.splat,
                .limited(source.get_data()),
            ) catch |err| switch (err) {
                error.Canceled => return Thread.current().currentFiber().cancel_protection.recancel(),
                error.WouldBlock => return,
                else => |e| e,
            } };
        },
        .device_io_control => unreachable,
        .net_receive => @panic("TODO implement batched net_receive"),
    };

    switch (pending.node.prev) {
        .none => batch.pending.head = pending.node.next,
        else => |prev_index| batch.storage[prev_index.toIndex()].pending.node.next = pending.node.next,
    }
    switch (pending.node.next) {
        .none => batch.pending.tail = pending.node.prev,
        else => |next_index| batch.storage[next_index.toIndex()].pending.node.prev = pending.node.prev,
    }

    switch (batch.completed.tail) {
        .none => batch.completed.head = index,
        else => |tail_index| batch.storage[tail_index.toIndex()].completion.node.next = index,
    }
    storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
    batch.completed.tail = index;

    source.as_object().release();
    const queue: c.dispatch.queue_t = @ptrCast(batch.userdata);
    const waiter: *BatchWaiter = @ptrCast(@alignCast(queue.as_object().get_context()));
    BatchWaiter.signal(waiter);
}

fn batchSourceCancel(context: ?*anyopaque) callconv(.c) void {
    const storage: *Io.Operation.Storage = @ptrCast(@alignCast(context));
    const pending = &storage.pending;
    const operation_userdata: *BatchOperationUserdata = .fromErased(&pending.userdata);
    const batch = operation_userdata.batch;
    const source = operation_userdata.source;
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - batch.storage.ptr);

    switch (pending.node.prev) {
        .none => batch.pending.head = pending.node.next,
        else => |prev_index| batch.storage[prev_index.toIndex()].pending.node.next = pending.node.next,
    }
    switch (pending.node.next) {
        .none => batch.pending.tail = pending.node.prev,
        else => |next_index| batch.storage[next_index.toIndex()].pending.node.prev = pending.node.prev,
    }

    const tail_index = batch.unused.tail;
    switch (tail_index) {
        .none => batch.unused.head = index,
        else => batch.storage[tail_index.toIndex()].unused.next = index,
    }
    storage.* = .{ .unused = .{ .prev = tail_index, .next = .none } };
    batch.unused.tail = index;

    source.as_object().release();
    if (batch.pending.head != .none) return;
    const queue: c.dispatch.queue_t = @ptrCast(batch.userdata);
    const waiter: *BatchWaiter = @ptrCast(@alignCast(queue.as_object().get_context()));
    queue.as_object().release();
    waiter.wake();
}

fn dirCreateDir(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    while (true) {
        switch (c.errno(c.mkdirat(dir.handle, sub_path_posix, permissions.toMode()))) {
            .SUCCESS => return,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .DQUOT => return error.DiskQuota,
            .EXIST => return error.PathAlreadyExists,
            .LOOP => return error.SymLinkLoop,
            .MLINK => return error.LinkQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .ROFS => return error.ReadOnlyFileSystem,
            .ILSEQ => return error.BadPathName,
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return errnoBug(err),
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
                // It is important to return an error if it's not a directory
                // because otherwise a dangling symlink could cause an infinite
                // loop.
                const fstat = try dirStatFile(ev, dir, component.path, .{});
                if (fstat.kind != .directory) return error.NotDir;
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
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: c.O = .{
        .ACCMODE = .RDONLY,
        .NOFOLLOW = !options.follow_symlinks,
        .DIRECTORY = true,
        .CLOEXEC = true,
    };

    while (true) {
        const rc = c.openat(dir.handle, sub_path_posix, flags);
        switch (c.errno(rc)) {
            .SUCCESS => return .{ .handle = @intCast(rc) },
            .INTR => {},
            .INVAL => return error.BadPathName,
            .ACCES => return error.AccessDenied,
            .LOOP => return error.SymLinkLoop,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NAMETOOLONG => return error.NameTooLong,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NODEV => return error.NoDevice,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .NXIO => return error.NoDevice,
            .ILSEQ => return error.BadPathName,
            .FAULT => |err| return errnoBug(err),
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .BUSY => |err| return errnoBug(err), // O_EXCL not passed
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return fileStat(ev, .{
        .handle = dir.handle,
        .flags = .{ .nonblocking = false },
    });
}

fn dirStatFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: u32 = if (options.follow_symlinks) 0 else c.AT.SYMLINK_NOFOLLOW;

    while (true) {
        var stat = std.mem.zeroes(c.Stat);
        switch (c.errno(c.fstatat(dir.handle, sub_path_posix, &stat, flags))) {
            .SUCCESS => return statFromPosix(&stat),
            .INTR => {},
            .INVAL => |err| return errnoBug(err),
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .NOMEM => return error.SystemResources,
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .FAULT => |err| return errnoBug(err),
            .NAMETOOLONG => return error.NameTooLong,
            .LOOP => return error.SymLinkLoop,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.FileNotFound,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn dirAccess(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: u32 = if (options.follow_symlinks) 0 else c.AT.SYMLINK_NOFOLLOW;

    const mode: u32 =
        @as(u32, if (options.read) c.R_OK else 0) |
        @as(u32, if (options.write) c.W_OK else 0) |
        @as(u32, if (options.execute) c.X_OK else 0);

    while (true) switch (c.errno(c.faccessat(dir.handle, sub_path_posix, mode, flags))) {
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
    };
}

fn dirCreateFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: File.CreateFlags,
) File.OpenError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const os_flags: c.O = .{
        .ACCMODE = if (flags.read) .RDWR else .WRONLY,
        .NONBLOCK = flags.lock == .none or flags.lock_nonblocking,
        .SHLOCK = flags.lock == .shared,
        .EXLOCK = flags.lock == .exclusive,
        .CREAT = true,
        .TRUNC = flags.truncate,
        .EXCL = flags.exclusive,
        .CLOEXEC = true,
    };

    const fd: c.fd_t = while (true) {
        const rc = c.openat(dir.handle, sub_path_posix, os_flags, flags.permissions.toMode());
        switch (c.errno(rc)) {
            .SUCCESS => break @intCast(rc),
            .INTR => {},
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
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .EXIST => return error.PathAlreadyExists,
            .BUSY => return error.DeviceBusy,
            .OPNOTSUPP => return error.FileLocksUnsupported,
            .AGAIN => return error.WouldBlock,
            .TXTBSY => return error.FileBusy,
            .ROFS => return error.ReadOnlyFileSystem,
            .NXIO => return error.NoDevice,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    };
    errdefer closeFd(fd);

    return .{
        .handle = fd,
        .flags = .{ .nonblocking = os_flags.NONBLOCK },
    };
}

fn dirCreateFileAtomic(
    userdata: ?*anyopaque,
    dir: Dir,
    dest_path: []const u8,
    options: Dir.CreateFileAtomicOptions,
) Dir.CreateFileAtomicError!File.Atomic {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
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

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const os_flags: c.O = .{
        .ACCMODE = switch (flags.mode) {
            .read_only => .RDONLY,
            .write_only => .WRONLY,
            .read_write => .RDWR,
        },
        .NONBLOCK = flags.lock == .none or flags.lock_nonblocking,
        .SHLOCK = flags.lock == .shared,
        .EXLOCK = flags.lock == .exclusive,
        .NOFOLLOW = !flags.follow_symlinks,
        .NOCTTY = !flags.allow_ctty,
        .CLOEXEC = true,
    };

    const fd: c.fd_t = while (true) {
        const rc = c.openat(dir.handle, sub_path_posix, os_flags);
        switch (c.errno(rc)) {
            .SUCCESS => break @intCast(rc),
            .INTR => {},
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
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .EXIST => return error.PathAlreadyExists,
            .BUSY => return error.DeviceBusy,
            .OPNOTSUPP => return error.FileLocksUnsupported,
            .AGAIN => return error.WouldBlock,
            .TXTBSY => return error.FileBusy,
            .NXIO => return error.NoDevice,
            .ROFS => return error.ReadOnlyFileSystem,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    };
    errdefer closeFd(fd);

    if (!flags.allow_directory) {
        const is_dir = is_dir: {
            const stat = fileStat(ev, .{
                .handle = fd,
                .flags = .{ .nonblocking = false },
            }) catch |err| switch (err) {
                // The directory-ness is either unknown or unknowable
                error.Streaming => break :is_dir false,
                else => |e| return e,
            };
            break :is_dir stat.kind == .directory;
        };
        if (is_dir) return error.IsDir;
    }

    return .{
        .handle = fd,
        .flags = .{ .nonblocking = os_flags.NONBLOCK },
    };
}

fn dirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    for (dirs) |dir| closeFd(dir.handle);
}

fn dirRead(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const Header = extern struct {
        seek: i64,
    };
    const header: *Header = @ptrCast(dr.buffer.ptr);
    const header_end: usize = @sizeOf(Header);
    if (dr.index < header_end) {
        // Initialize header.
        dr.index = header_end;
        dr.end = header_end;
        header.* = .{ .seek = 0 };
    }
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .reset) {
                ev.lseek(dr.dir.handle, 0, c.SEEK.SET) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const dents_buffer = dr.buffer[header_end..];
            const n: usize = while (true) {
                const rc = c.getdirentries(dr.dir.handle, dents_buffer.ptr, dents_buffer.len, &header.seek);
                switch (c.errno(rc)) {
                    .SUCCESS => break @intCast(rc),
                    .INTR => {},
                    .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability.
                    .FAULT => |err| return errnoBug(err),
                    .NOTDIR => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    else => |err| return unexpectedErrno(err),
                }
            };
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = header_end;
            dr.end = header_end + n;
        }
        const darwin_entry = @as(*align(1) c.dirent, @ptrCast(&dr.buffer[dr.index]));
        const next_index = dr.index + darwin_entry.reclen;
        dr.index = next_index;

        const name = @as([*]u8, @ptrCast(&darwin_entry.name))[0..darwin_entry.namlen];
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or (darwin_entry.ino == 0))
            continue;

        const entry_kind: File.Kind = switch (darwin_entry.type) {
            c.DT.BLK => .block_device,
            c.DT.CHR => .character_device,
            c.DT.DIR => .directory,
            c.DT.FIFO => .named_pipe,
            c.DT.LNK => .sym_link,
            c.DT.REG => .file,
            c.DT.SOCK => .unix_domain_socket,
            c.DT.WHT => .whiteout,
            else => .unknown,
        };
        buffer[buffer_index] = .{
            .name = name,
            .kind = entry_kind,
            .inode = darwin_entry.ino,
        };
        buffer_index += 1;
    }
    return buffer_index;
}

fn dirRealPath(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return ev.realPath(dir.handle, out_buffer);
}

fn realPath(ev: *Evented, fd: c.fd_t, out_buffer: []u8) File.RealPathError!usize {
    _ = ev;
    var buffer: [c.PATH_MAX]u8 = undefined;
    @memset(&buffer, 0);
    while (true) {
        switch (c.errno(c.fcntl(fd, c.F.GETPATH, &buffer))) {
            .SUCCESS => break,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .BADF => return error.FileNotFound,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NameTooLong,
            .RANGE => return error.NameTooLong,
            else => |err| return unexpectedErrno(err),
        }
    }
    const n = std.mem.indexOfScalar(u8, &buffer, 0) orelse buffer.len;
    if (n > out_buffer.len) return error.NameTooLong;
    @memcpy(out_buffer[0..n], buffer[0..n]);
    return n;
}

fn dirRealPathFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    out_buffer: []u8,
) Dir.RealPathFileError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    if (dir.handle == c.AT.FDCWD) {
        if (out_buffer.len < c.PATH_MAX) return error.NameTooLong;
        while (true) {
            if (c.realpath(sub_path_posix, out_buffer.ptr)) |redundant_pointer| {
                assert(redundant_pointer == out_buffer.ptr);
                return std.mem.indexOfScalar(u8, out_buffer, 0) orelse out_buffer.len;
            }
            const err: c.E = @enumFromInt(c._errno().*);
            switch (err) {
                .INTR => {},
                .INVAL => return errnoBug(err),
                .BADF => return errnoBug(err),
                .FAULT => return errnoBug(err),
                .ACCES => return error.AccessDenied,
                .NOENT => return error.FileNotFound,
                .OPNOTSUPP => return error.OperationUnsupported,
                .NOTDIR => return error.NotDir,
                .NAMETOOLONG => return error.NameTooLong,
                .LOOP => return error.SymLinkLoop,
                .IO => return error.InputOutput,
                else => return unexpectedErrno(err),
            }
        }
    }

    const os_flags: c.O = .{
        .NONBLOCK = true,
        .CLOEXEC = true,
    };

    const fd: c.fd_t = while (true) {
        const rc = c.openat(dir.handle, sub_path_posix, os_flags);
        switch (c.errno(rc)) {
            .SUCCESS => break @intCast(rc),
            .INTR => {},
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
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NoSpaceLeft,
            .NOTDIR => return error.NotDir,
            .PERM => return error.PermissionDenied,
            .EXIST => return error.PathAlreadyExists,
            .BUSY => return error.DeviceBusy,
            .NXIO => return error.NoDevice,
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    };
    defer closeFd(fd);
    return ev.realPath(fd, out_buffer);
}

fn dirDeleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    while (true) switch (c.errno(c.unlinkat(dir.handle, sub_path_posix, 0))) {
        .SUCCESS => return,
        .INTR => {},
        // Some systems return permission errors when trying to delete a
        // directory, so we need to handle that case specifically and
        // translate the error.
        .PERM => {
            // Don't follow symlinks to match unlinkat (which acts on symlinks rather than follows them).
            var st = std.mem.zeroes(c.Stat);
            while (true) switch (c.errno(c.fstatat(
                dir.handle,
                sub_path_posix,
                &st,
                c.AT.SYMLINK_NOFOLLOW,
            ))) {
                .SUCCESS => break,
                .INTR => {},
                else => return error.PermissionDenied,
            };
            if (st.mode & c.S.IFMT == c.S.IFDIR) return error.IsDir else return error.PermissionDenied;
        },
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
    };
}

fn dirDeleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    while (true) switch (c.errno(c.unlinkat(dir.handle, sub_path_posix, c.AT.REMOVEDIR))) {
        .SUCCESS => return,
        .INTR => {},
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
    };
}

fn dirRename(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var old_path_buffer: [c.PATH_MAX]u8 = undefined;
    var new_path_buffer: [c.PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    while (true) switch (c.errno(c.renameat(old_dir.handle, old_sub_path_posix, new_dir.handle, new_sub_path_posix))) {
        .SUCCESS => return,
        .INTR => {},
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
    };
}

fn dirRenamePreserve(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    // Make a hard link then delete the original.
    try dirHardLink(ev, old_dir, old_sub_path, new_dir, new_sub_path, .{ .follow_symlinks = false });
    const prev = swapCancelProtection(ev, .blocked);
    defer _ = swapCancelProtection(ev, prev);
    dirDeleteFile(ev, old_dir, old_sub_path) catch {};
}

fn dirSymLink(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = flags;

    var target_path_buffer: [c.PATH_MAX]u8 = undefined;
    var sym_link_path_buffer: [c.PATH_MAX]u8 = undefined;

    const target_path_posix = try pathToPosix(target_path, &target_path_buffer);
    const sym_link_path_posix = try pathToPosix(sym_link_path, &sym_link_path_buffer);

    while (true) switch (c.errno(c.symlinkat(target_path_posix, dir.handle, sym_link_path_posix))) {
        .SUCCESS => return,
        .INTR => {},
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
    };
}

fn dirReadLink(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    buffer: []u8,
) Dir.ReadLinkError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    var sub_path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &sub_path_buffer);
    while (true) {
        const rc = c.readlinkat(dir.handle, sub_path_posix, buffer.ptr, buffer.len);
        switch (c.errno(rc)) {
            .SUCCESS => return @intCast(rc),
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
    _ = ev;
    return fchown(dir.handle, owner, group);
}

fn fchown(fd: c.fd_t, owner: ?File.Uid, group: ?File.Gid) File.SetOwnerError!void {
    const uid = owner orelse std.math.maxInt(c.uid_t);
    const gid = group orelse std.math.maxInt(c.gid_t);
    while (true) switch (c.errno(c.fchown(fd, uid, gid))) {
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
    };
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
    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);
    _ = ev;
    while (true) switch (c.errno(c.fchownat(
        dir.handle,
        sub_path_posix,
        owner orelse std.math.maxInt(c.uid_t),
        group orelse std.math.maxInt(c.gid_t),
        if (options.follow_symlinks) 0 else c.AT.SYMLINK_NOFOLLOW,
    ))) {
        .SUCCESS => return,
        .INTR => continue,
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
    };
}

fn dirSetPermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    permissions: Dir.Permissions,
) Dir.SetPermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return ev.fchmod(dir.handle, permissions.toMode());
}

fn dirSetFilePermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.SetFilePermissionsOptions,
) Dir.SetFilePermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const mode = permissions.toMode();
    const flags: u32 = if (options.follow_symlinks) 0 else c.AT.SYMLINK_NOFOLLOW;

    while (true) switch (c.errno(c.fchmodat(dir.handle, sub_path_posix, mode, flags))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err),
        .FAULT => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err),
        .ACCES => return error.AccessDenied,
        .IO => return error.InputOutput,
        .LOOP => return error.SymLinkLoop,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NAMETOOLONG => return error.NameTooLong,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOENT => return error.FileNotFound,
        .NOTDIR => return error.FileNotFound,
        .NOMEM => return error.SystemResources,
        .OPNOTSUPP => return error.OperationUnsupported,
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        else => |err| return unexpectedErrno(err),
    };
}

fn dirSetTimestamps(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.SetTimestampsOptions,
) Dir.SetTimestampsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var times_buffer: [2]c.timespec = undefined;
    const times = if (options.modify_timestamp == .now and options.access_timestamp == .now) null else p: {
        times_buffer = .{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        };
        break :p &times_buffer;
    };

    const flags: u32 = if (options.follow_symlinks) 0 else c.AT.SYMLINK_NOFOLLOW;

    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    while (true) switch (c.errno(c.utimensat(dir.handle, sub_path_posix, times, flags))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err), // always a race condition
        .FAULT => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err),
        .ACCES => return error.AccessDenied,
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        else => |err| return unexpectedErrno(err),
    };
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
    _ = ev;

    var old_path_buffer: [c.PATH_MAX]u8 = undefined;
    var new_path_buffer: [c.PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    const flags: u32 = if (options.follow_symlinks) c.AT.SYMLINK_FOLLOW else 0;
    return linkat(old_dir.handle, old_sub_path_posix, new_dir.handle, new_sub_path_posix, flags);
}

fn fileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    while (true) {
        var stat = std.mem.zeroes(c.Stat);
        switch (c.errno(c.fstat(file.handle, &stat))) {
            .SUCCESS => return statFromPosix(&stat),
            .INTR => {},
            .INVAL => |err| return errnoBug(err),
            .BADF => |err| return errnoBug(err), // File descriptor used after closed.
            .NOMEM => return error.SystemResources,
            .ACCES => return error.AccessDenied,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const stat = try fileStat(ev, file);
    return stat.size;
}

fn fileClose(userdata: ?*anyopaque, files: []const File) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    for (files) |file| closeFd(file.handle);
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
    _ = ev;
    var iovecs: [max_iovecs_len]iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    var remaining: Io.Limit = .unlimited;
    addBuf(true, &iovecs, &iovlen, &remaining, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(true, &iovecs, &iovlen, &remaining, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0 and remaining != .nothing) switch (splat) {
        0 => {},
        1 => addBuf(true, &iovecs, &iovlen, &remaining, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addBuf(true, &iovecs, &iovlen, &remaining, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and iovecs.len - iovlen != 0 and remaining != .nothing) {
                    assert(buf.len == splat_buffer.len);
                    addBuf(true, &iovecs, &iovlen, &remaining, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addBuf(true, &iovecs, &iovlen, &remaining, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - iovlen)) |_| {
                if (remaining == .nothing) break;
                addBuf(true, &iovecs, &iovlen, &remaining, pattern);
            },
        },
    };
    if (iovlen == 0) return 0;
    while (true) {
        const rc = c.pwritev(file.handle, &iovecs, iovlen, @bitCast(offset));
        switch (c.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => {},
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .DESTADDRREQ => |err| return errnoBug(err), // `connect` was never called.
            .CONNRESET => |err| return errnoBug(err), // Not a socket handle.
            .BADF => return error.NotOpenForWriting,
            .AGAIN => return error.WouldBlock,
            .DQUOT => return error.DiskQuota,
            .FBIG => return error.FileTooBig,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .PERM => return error.PermissionDenied,
            .PIPE => return error.BrokenPipe,
            .BUSY => return error.DeviceBusy,
            .TXTBSY => return error.FileBusy,
            .NXIO => return error.Unseekable,
            .SPIPE => return error.Unseekable,
            .OVERFLOW => return error.Unseekable,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileWriteFileStreaming(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) File.Writer.WriteFileError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @intFromEnum(limit)) {
        const n = try fileWriteStreaming(ev, file, header, &.{limit.slice(reader_buffered)}, 1);
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    const file_limit = @intFromEnum(limit) - reader_buffered.len;
    const out_fd = file.handle;
    const in_fd = file_reader.file.handle;

    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWriteStreaming(ev, file, header, &.{limit.slice(reader_buffered)}, 1);
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }

    if (@atomicLoad(UseSendfile, &ev.use_sendfile, .monotonic) == .disabled) return error.Unimplemented;
    const offset = std.math.cast(c.off_t, file_reader.pos) orelse return error.Unimplemented;
    var hdtr_data: c.sf_hdtr = undefined;
    var headers: [2]iovec_const = undefined;
    var headers_i: u8 = 0;
    if (header.len != 0) {
        headers[headers_i] = .{ .base = header.ptr, .len = header.len };
        headers_i += 1;
    }
    if (reader_buffered.len != 0) {
        headers[headers_i] = .{ .base = reader_buffered.ptr, .len = reader_buffered.len };
        headers_i += 1;
    }
    const hdtr: ?*c.sf_hdtr = if (headers_i == 0) null else b: {
        hdtr_data = .{
            .headers = &headers,
            .hdr_cnt = headers_i,
            .trailers = null,
            .trl_cnt = 0,
        };
        break :b &hdtr_data;
    };
    const max_count = std.math.maxInt(i32); // Avoid EINVAL.
    var len: c.off_t = @min(file_limit, max_count);
    const flags = 0;
    while (true) switch (c.errno(c.sendfile(in_fd, out_fd, offset, &len, hdtr, flags))) {
        .SUCCESS => break,
        .OPNOTSUPP, .NOTSOCK, .NOSYS => {
            // Give calling code chance to observe before trying
            // something else.
            @atomicStore(UseSendfile, &ev.use_sendfile, .disabled, .monotonic);
            return 0;
        },
        .INTR => if (len > 0) break,
        .AGAIN => {
            if (len == 0) return error.WouldBlock;
            break;
        },
        else => |e| {
            assert(error.Unexpected == switch (e) {
                .NOTCONN => return error.BrokenPipe,
                .IO => return error.InputOutput,
                .PIPE => return error.BrokenPipe,
                .BADF => |err| errnoBug(err),
                .FAULT => |err| errnoBug(err),
                .INVAL => |err| errnoBug(err),
                else => |err| unexpectedErrno(err),
            });
            // Give calling code chance to observe the error before trying
            // something else.
            @atomicStore(UseSendfile, &ev.use_sendfile, .disabled, .monotonic);
            return 0;
        },
    };
    if (len == 0) {
        file_reader.size = file_reader.pos;
        return error.EndOfStream;
    }
    const u_len: usize = @bitCast(len);
    file_reader.interface.toss(u_len -| header.len);
    return u_len;
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
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @intFromEnum(limit)) {
        const n = try fileWritePositional(
            ev,
            file,
            header,
            &.{limit.slice(reader_buffered)},
            1,
            offset,
        );
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    const out_fd = file.handle;
    const in_fd = file_reader.file.handle;

    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWritePositional(
                    ev,
                    file,
                    header,
                    &.{limit.slice(reader_buffered)},
                    1,
                    offset,
                );
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }

    if (@atomicLoad(UseFcopyfile, &ev.use_fcopyfile, .monotonic) == .disabled)
        return error.Unimplemented;
    if (file_reader.pos != 0) return error.Unimplemented;
    if (offset != 0) return error.Unimplemented;
    if (limit != .unlimited) return error.Unimplemented;
    const size = file_reader.getSize() catch return error.Unimplemented;
    if (header.len != 0 or reader_buffered.len != 0) {
        const n = try fileWritePositional(
            ev,
            file,
            header,
            &.{limit.slice(reader_buffered)},
            1,
            offset,
        );
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    while (true) {
        const rc = c.fcopyfile(in_fd, out_fd, null, .{ .DATA = true });
        switch (c.errno(rc)) {
            .SUCCESS => break,
            .INTR => {},
            .OPNOTSUPP => {
                // Give calling code chance to observe before trying
                // something else.
                @atomicStore(UseFcopyfile, &ev.use_fcopyfile, .disabled, .monotonic);
                return 0;
            },
            else => |e| {
                assert(error.Unexpected == switch (e) {
                    .NOMEM => return error.SystemResources,
                    .INVAL => |err| errnoBug(err),
                    else => |err| unexpectedErrno(err),
                });
                return 0;
            },
        }
    }
    file_reader.pos = size;
    return size;
}

fn fileReadPositional(
    userdata: ?*anyopaque,
    file: File,
    data: []const []u8,
    offset: u64,
) File.ReadPositionalError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    var iovecs: [max_iovecs_len]iovec = undefined;
    var iovlen: iovlen_t = 0;
    var remaining: Io.Limit = .unlimited;
    for (data) |buf| addBuf(false, &iovecs, &iovlen, &remaining, buf);
    if (iovlen == 0) return 0;
    while (true) {
        const rc = c.preadv(file.handle, &iovecs, iovlen, @bitCast(offset));
        switch (c.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => {},
            .NXIO => return error.Unseekable,
            .SPIPE => return error.Unseekable,
            .OVERFLOW => return error.Unseekable,
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .AGAIN => return error.WouldBlock,
            .IO => return error.InputOutput,
            .ISDIR => return error.IsDir,
            .NOTCONN => |err| return errnoBug(err), // not a socket
            .CONNRESET => |err| return errnoBug(err), // not a socket
            .INVAL => |err| return errnoBug(err),
            .FAULT => |err| return errnoBug(err),
            .BADF => return error.NotOpenForReading,
            else => |err| return unexpectedErrno(err),
        }
    }
}

fn fileSeekBy(userdata: ?*anyopaque, file: File, offset: i64) File.SeekError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return ev.lseek(file.handle, @bitCast(offset), c.SEEK.CUR);
}

fn fileSeekTo(userdata: ?*anyopaque, file: File, offset: u64) File.SeekError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return ev.lseek(file.handle, offset, c.SEEK.SET);
}

fn lseek(ev: *Evented, fd: c.fd_t, offset: u64, whence: i32) File.SeekError!void {
    _ = ev;
    while (true) switch (c.errno(c.lseek(fd, @bitCast(offset), whence))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
        .INVAL => return error.Unseekable,
        .OVERFLOW => return error.Unseekable,
        .SPIPE => return error.Unseekable,
        .NXIO => return error.Unseekable,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileSync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    while (true) switch (c.errno(c.fsync(file.handle))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err),
        .ROFS => |err| return errnoBug(err),
        .IO => return error.InputOutput,
        .NOSPC => return error.NoSpaceLeft,
        .DQUOT => return error.DiskQuota,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileIsTty(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    while (true) {
        const rc = c.isatty(file.handle);
        switch (c.errno(rc - 1)) {
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
    _ = ev;

    const signed_len: i64 = @bitCast(length);
    if (signed_len < 0) return error.FileTooBig; // Avoid ambiguous EINVAL errors.

    while (true) switch (c.errno(c.ftruncate(file.handle, signed_len))) {
        .SUCCESS => return,
        .INTR => {},
        .FBIG => return error.FileTooBig,
        .IO => return error.InputOutput,
        .PERM => return error.PermissionDenied,
        .TXTBSY => return error.FileBusy,
        .BADF => |err| return errnoBug(err), // Handle not open for writing.
        .INVAL => return error.NonResizable, // This is returned for /dev/null for example.
        else => |err| return unexpectedErrno(err),
    };
}

fn fileSetOwner(
    userdata: ?*anyopaque,
    file: File,
    owner: ?File.Uid,
    group: ?File.Gid,
) File.SetOwnerError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    return fchown(file.handle, owner, group);
}

fn fileSetPermissions(
    userdata: ?*anyopaque,
    file: File,
    permissions: File.Permissions,
) File.SetPermissionsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    return ev.fchmod(file.handle, permissions.toMode());
}

fn fchmod(ev: *Evented, fd: c.fd_t, mode: c.mode_t) File.SetPermissionsError!void {
    _ = ev;
    while (true) switch (c.errno(c.fchmod(fd, mode))) {
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
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileSetTimestamps(
    userdata: ?*anyopaque,
    file: File,
    options: File.SetTimestampsOptions,
) File.SetTimestampsError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    var times_buffer: [2]c.timespec = undefined;
    const times = if (options.modify_timestamp == .now and options.access_timestamp == .now) null else p: {
        times_buffer = .{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        };
        break :p &times_buffer;
    };

    while (true) switch (c.errno(c.futimens(file.handle, times))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err), // always a race condition
        .FAULT => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err),
        .ACCES => return error.AccessDenied,
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const operation: i32 = switch (lock) {
        .none => c.LOCK.UN,
        .shared => c.LOCK.SH,
        .exclusive => c.LOCK.EX,
    };
    while (true) switch (c.errno(c.flock(file.handle, operation))) {
        .SUCCESS => return,
        .INTR => {},
        .BADF => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err), // invalid parameters
        .NOLCK => return error.SystemResources,
        .AGAIN => |err| return errnoBug(err),
        .OPNOTSUPP => return error.FileLocksUnsupported,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const operation: i32 = switch (lock) {
        .none => c.LOCK.UN,
        .shared => c.LOCK.SH | c.LOCK.NB,
        .exclusive => c.LOCK.EX | c.LOCK.NB,
    };
    while (true) switch (c.errno(c.flock(file.handle, operation))) {
        .SUCCESS => return true,
        .INTR => {},
        .AGAIN => return false,
        .BADF => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err), // invalid parameters
        .NOLCK => return error.SystemResources,
        .OPNOTSUPP => return error.FileLocksUnsupported,
        else => |err| return unexpectedErrno(err),
    };
}

fn fileUnlock(userdata: ?*anyopaque, file: File) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    while (true) switch (c.errno(c.flock(file.handle, c.LOCK.UN))) {
        .SUCCESS => return,
        .INTR => {},
        .AGAIN => return recoverableOsBugDetected(), // unlocking can't block
        .BADF => return recoverableOsBugDetected(), // File descriptor used after closed.
        .INVAL => return recoverableOsBugDetected(), // invalid parameters
        .NOLCK => return recoverableOsBugDetected(), // Resource deallocation.
        .OPNOTSUPP => return recoverableOsBugDetected(), // We already got the lock.
        else => return recoverableOsBugDetected(), // Resource deallocation must succeed.
    };
}

fn fileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const operation = c.LOCK.SH | c.LOCK.NB;
    while (true) switch (c.errno(c.flock(file.handle, operation))) {
        .SUCCESS => return,
        .INTR => {},
        .AGAIN => |err| return errnoBug(err), // File was not locked in exclusive mode.
        .BADF => |err| return errnoBug(err),
        .INVAL => |err| return errnoBug(err), // invalid parameters
        .NOLCK => |err| return errnoBug(err), // Lock already obtained.
        .OPNOTSUPP => |err| return errnoBug(err), // Lock already obtained.
        else => |err| return unexpectedErrno(err),
    };
}

fn fileRealPath(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    var buffer: [c.PATH_MAX]u8 = undefined;
    @memset(&buffer, 0);
    while (true) {
        switch (c.errno(c.fcntl(file.handle, c.F.GETPATH, &buffer))) {
            .SUCCESS => break,
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .BADF => return error.FileNotFound,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOSPC => return error.NameTooLong,
            .RANGE => return error.NameTooLong,
            else => |err| return unexpectedErrno(err),
        }
    }
    const n = std.mem.indexOfScalar(u8, &buffer, 0) orelse buffer.len;
    if (n > out_buffer.len) return error.NameTooLong;
    @memcpy(out_buffer[0..n], buffer[0..n]);
    return n;
}

fn fileHardLink(
    userdata: ?*anyopaque,
    file: File,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: File.HardLinkOptions,
) File.HardLinkError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = file;
    _ = new_dir;
    _ = new_sub_path;
    _ = options;
    return error.OperationUnsupported;
}

fn linkat(
    old_dir: c.fd_t,
    old_path: [*:0]const u8,
    new_dir: c.fd_t,
    new_path: [*:0]const u8,
    flags: u32,
) File.HardLinkError!void {
    while (true) switch (c.errno(c.linkat(old_dir, old_path, new_dir, new_path, flags))) {
        .SUCCESS => return,
        .INTR => {},
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
    };
}

fn fileMemoryMapCreate(
    userdata: ?*anyopaque,
    file: File,
    options: File.MemoryMap.CreateOptions,
) File.MemoryMap.CreateError!File.MemoryMap {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;

    const prot: c.PROT = .{
        .READ = options.protection.read,
        .WRITE = options.protection.write,
        .EXEC = options.protection.execute,
    };
    const flags: c.MAP = .{
        .TYPE = .SHARED,
    };

    const page_align = std.heap.page_size_min;

    const contents = while (true) {
        const casted_offset = std.math.cast(i64, options.offset) orelse return error.Unseekable;
        const rc = c.mmap(null, options.len, prot, flags, file.handle, casted_offset);
        const err: c.E = if (rc != c.MAP_FAILED) .SUCCESS else @enumFromInt(c._errno().*);
        switch (err) {
            .SUCCESS => break @as([*]align(page_align) u8, @ptrCast(@alignCast(rc)))[0..options.len],
            .INTR => {},
            .ACCES => return error.AccessDenied,
            .AGAIN => return error.LockedMemoryLimitExceeded,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NOMEM => return error.OutOfMemory,
            .PERM => return error.PermissionDenied,
            .OVERFLOW => return error.Unseekable,
            .BADF => return errnoBug(err), // Always a race condition.
            .INVAL => return errnoBug(err), // Invalid parameters to mmap()
            else => return unexpectedErrno(err),
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
    switch (c.errno(c.munmap(memory.ptr, memory.len))) {
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
    _ = ev;

    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const old_memory = mm.memory;

    if (alignment.forward(new_len) == alignment.forward(old_memory.len)) {
        mm.memory.len = new_len;
        return;
    }
    return error.OperationUnsupported;
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
    // _NSGetExecutablePath() returns a path that might be a symlink to
    // the executable. Here it does not matter since we open it.
    var symlink_path_buf: [c.PATH_MAX + 1]u8 = undefined;
    var n: u32 = symlink_path_buf.len;
    const rc = c._NSGetExecutablePath(&symlink_path_buf, &n);
    if (rc != 0) return error.NameTooLong;
    const symlink_path = std.mem.sliceTo(&symlink_path_buf, 0);
    return dirOpenFile(ev, .cwd(), symlink_path, flags);
}

fn processExecutablePath(userdata: ?*anyopaque, out_buffer: []u8) process.ExecutablePathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    // _NSGetExecutablePath() returns a path that might be a symlink to
    // the executable.
    var symlink_path_buf: [c.PATH_MAX + 1]u8 = undefined;
    var n: u32 = symlink_path_buf.len;
    const rc = c._NSGetExecutablePath(&symlink_path_buf, &n);
    if (rc != 0) return error.NameTooLong;
    const symlink_path = std.mem.sliceTo(&symlink_path_buf, 0);
    assert(Dir.path.isAbsolute(symlink_path));
    return dirRealPathFile(ev, .cwd(), symlink_path, out_buffer) catch |err| switch (err) {
        error.NetworkNotFound => unreachable, // Windows-only
        error.FileBusy => unreachable, // Windows-only
        else => |e| return e,
    };
}

fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    try ev.stderr_mutex.lock(ev);
    errdefer ev.stderr_mutex.unlock();
    return ev.initLockedStderr(terminal_mode);
}

fn tryLockStderr(
    userdata: ?*anyopaque,
    terminal_mode: ?Io.Terminal.Mode,
) Io.Cancelable!?Io.LockedStderr {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (!ev.stderr_mutex.tryLock()) return null;
    errdefer ev.stderr_mutex.unlock();
    return try ev.initLockedStderr(terminal_mode);
}

fn initLockedStderr(ev: *Evented, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    ev.init_stderr_writer.once(ev, &initStderrWriter);
    return .{
        .file_writer = &ev.stderr_writer,
        .terminal_mode = terminal_mode orelse ev.stderr_mode,
    };
}

fn initStderrWriter(context: ?*anyopaque) callconv(.c) void {
    const ev: *Evented = @ptrCast(@alignCast(context));
    const cancel_protection = swapCancelProtection(ev, .blocked);
    defer assert(swapCancelProtection(ev, cancel_protection) == .blocked);
    ev.scan_environ.once(ev, &scanEnviron);
    const NO_COLOR = ev.environ.exist.NO_COLOR;
    const CLICOLOR_FORCE = ev.environ.exist.CLICOLOR_FORCE;
    ev.stderr_mode = Io.Terminal.Mode.detect(
        ev.io(),
        ev.stderr_writer.file,
        NO_COLOR,
        CLICOLOR_FORCE,
    ) catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
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
    ev.stderr_writer.interface.buffer.len = 0;
    ev.stderr_mutex.unlock();
}

fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) process.CurrentPathError!usize {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const err: c.E = if (c.getcwd(buffer.ptr, buffer.len)) |_| .SUCCESS else @enumFromInt(c._errno().*);
    switch (err) {
        .SUCCESS => return std.mem.findScalar(u8, buffer, 0).?,
        .NOENT => return error.CurrentDirUnlinked,
        .RANGE => return error.NameTooLong,
        .FAULT => |e| return errnoBug(e),
        .INVAL => |e| return errnoBug(e),
        else => return unexpectedErrno(err),
    }
}

fn processSetCurrentDir(userdata: ?*anyopaque, dir: Dir) process.SetCurrentDirError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    if (dir.handle == c.AT.FDCWD) return;
    while (true) switch (c.errno(c.fchdir(dir.handle))) {
        .SUCCESS => return,
        .INTR => {},
        .ACCES => return error.AccessDenied,
        .NOTDIR => return error.NotDir,
        .IO => return error.FileSystem,
        .BADF => |err| return errnoBug(err),
        else => |err| return unexpectedErrno(err),
    };
}

fn processSetCurrentPath(userdata: ?*anyopaque, dir_path: []const u8) process.SetCurrentPathError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    var path_buffer: [c.PATH_MAX]u8 = undefined;
    const dir_path_posix = try pathToPosix(dir_path, &path_buffer);
    while (true) switch (c.errno(c.chdir(dir_path_posix))) {
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
    };
}

fn processReplace(userdata: ?*anyopaque, options: process.ReplaceOptions) process.ReplaceError {
    const ev: *Evented = @ptrCast(@alignCast(userdata));

    if (!process.can_replace) return error.OperationUnsupported;

    ev.scan_environ.once(ev, &scanEnviron); // for PATH
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

    return ev.execv(options.expand_arg0, argv_buf.ptr[0].?, argv_buf.ptr, env_block, PATH);
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
    defer fileClose(ev, &.{spawned.err_pipe});

    // Wait for the child to report any errors in or before `execvpe`.
    var child_err: ForkBailError = undefined;
    ev.readAll(spawned.err_pipe, @ptrCast(&child_err)) catch |read_err| {
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

const prog_fileno = @max(c.STDIN_FILENO, c.STDOUT_FILENO, c.STDERR_FILENO) + 1;

const Spawned = struct {
    pid: c.pid_t,
    err_pipe: File,
    stdin: ?File,
    stdout: ?File,
    stderr: ?File,
};
fn spawn(ev: *Evented, options: process.SpawnOptions) process.SpawnError!Spawned {
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
    const pipe_flags: c.O = .{ .CLOEXEC = true };

    const stdin_pipe = if (options.stdin == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stdin == .pipe) {
        destroyPipe(stdin_pipe);
    };

    const stdout_pipe = if (options.stdout == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stdout == .pipe) {
        destroyPipe(stdout_pipe);
    };

    const stderr_pipe = if (options.stderr == .pipe) try pipe2(pipe_flags) else undefined;
    errdefer if (options.stderr == .pipe) {
        destroyPipe(stderr_pipe);
    };

    const any_ignore =
        options.stdin == .ignore or options.stdout == .ignore or options.stderr == .ignore;
    const dev_null_file = if (any_ignore) dev_null_file: {
        ev.open_dev_null.once(ev, &openDevNullFile);
        break :dev_null_file try ev.dev_null_file;
    } else undefined;

    const prog_pipe: [2]c.fd_t = if (options.progress_node.index != .none)
        // We use CLOEXEC for the same reason as in `pipe_flags`.
        try pipe2(.{ .NONBLOCK = true, .CLOEXEC = true })
    else
        .{ -1, -1 };
    errdefer destroyPipe(prog_pipe);

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
    const err_pipe: [2]File = err_pipe: {
        const err_pipe = try pipe2(.{ .CLOEXEC = true });
        break :err_pipe .{
            .{ .handle = err_pipe[0], .flags = .{ .nonblocking = false } },
            .{ .handle = err_pipe[1], .flags = .{ .nonblocking = false } },
        };
    };
    errdefer fileClose(ev, &err_pipe);

    ev.scan_environ.once(ev, &scanEnviron); // for PATH
    const PATH = ev.environ.string.PATH orelse default_PATH;

    const pid_result: c.pid_t = fork: {
        const rc = c.fork();
        switch (c.errno(rc)) {
            .SUCCESS => break :fork @intCast(rc),
            .AGAIN => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOSYS => return error.OperationUnsupported,
            else => |err| return unexpectedErrno(err),
        }
    };

    if (pid_result == 0) {
        defer comptime unreachable; // We are the child.
        const err = ev.setUpChild(.{
            .stdin_pipe = stdin_pipe[0],
            .stdout_pipe = stdout_pipe[1],
            .stderr_pipe = stderr_pipe[1],
            .dev_null_fd = dev_null_file.handle,
            .prog_pipe = prog_pipe[1],
            .argv_buf = argv_buf,
            .env_block = env_block,
            .PATH = PATH,
            .spawn = options,
        });
        ev.writeAll(err_pipe[1], @ptrCast(&err)) catch {};
        c.exit(1);
    }

    const pid: c.pid_t = @intCast(pid_result); // We are the parent.
    errdefer comptime unreachable; // The child is forked; we must not error from now on

    fileClose(ev, err_pipe[1..2]); // make sure only the child holds the write end open

    if (options.stdin == .pipe) closeFd(stdin_pipe[0]);
    if (options.stdout == .pipe) closeFd(stdout_pipe[1]);
    if (options.stderr == .pipe) closeFd(stderr_pipe[1]);

    if (prog_pipe[1] != -1) closeFd(prog_pipe[1]);

    options.progress_node.setIpcFile(ev, .{ .handle = prog_pipe[0], .flags = .{ .nonblocking = true } });

    return .{
        .pid = pid,
        .err_pipe = err_pipe[0],
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

fn openDevNullFile(context: ?*anyopaque) callconv(.c) void {
    const ev: *Evented = @ptrCast(@alignCast(context));
    ev.dev_null_file = dirOpenFile(ev, .cwd(), "/dev/null", .{ .mode = .read_write });
}

/// Errors that can occur between fork() and execv()
const ForkBailError = process.SetCurrentDirError || ChdirError ||
    process.SpawnError || process.ReplaceError;
fn setUpChild(ev: *Evented, options: struct {
    stdin_pipe: c.fd_t,
    stdout_pipe: c.fd_t,
    stderr_pipe: c.fd_t,
    dev_null_fd: c.fd_t,
    prog_pipe: c.fd_t,
    argv_buf: [:null]?[*:0]const u8,
    env_block: process.Environ.Block,
    PATH: []const u8,
    spawn: process.SpawnOptions,
}) ForkBailError {
    try ev.setUpChildIo(
        options.spawn.stdin,
        options.stdin_pipe,
        c.STDIN_FILENO,
        options.dev_null_fd,
    );
    try ev.setUpChildIo(
        options.spawn.stdout,
        options.stdout_pipe,
        c.STDOUT_FILENO,
        options.dev_null_fd,
    );
    try ev.setUpChildIo(
        options.spawn.stderr,
        options.stderr_pipe,
        c.STDERR_FILENO,
        options.dev_null_fd,
    );

    switch (options.spawn.cwd) {
        .inherit => {},
        .dir => |cwd_dir| try processSetCurrentDir(ev, cwd_dir),
        .path => |cwd_path| try processSetCurrentPath(ev, cwd_path),
    }

    // Must happen after fchdir above, the cwd file descriptor might be
    // equal to prog_fileno and be clobbered by this dup2 call.
    if (options.prog_pipe != -1) try ev.dup2(options.prog_pipe, prog_fileno);

    if (options.spawn.gid) |gid| while (true) switch (c.errno(c.setregid(gid, gid))) {
        .SUCCESS => break,
        .INTR => {},
        .AGAIN => return error.ResourceLimitReached,
        .INVAL => return error.InvalidUserId,
        .PERM => return error.PermissionDenied,
        else => return error.Unexpected,
    };

    if (options.spawn.uid) |uid| while (true) switch (c.errno(c.setreuid(uid, uid))) {
        .SUCCESS => break,
        .INTR => {},
        .AGAIN => return error.ResourceLimitReached,
        .INVAL => return error.InvalidUserId,
        .PERM => return error.PermissionDenied,
        else => return error.Unexpected,
    };

    if (options.spawn.pgid) |pid| while (true) switch (c.errno(c.setpgid(0, pid))) {
        .SUCCESS => break,
        .INTR => {},
        .ACCES => return error.ProcessAlreadyExec,
        .INVAL => return error.InvalidProcessGroupId,
        .PERM => return error.PermissionDenied,
        else => return error.Unexpected,
    };

    if (options.spawn.start_suspended) while (true) switch (c.errno(c.kill(0, .STOP))) {
        .SUCCESS => break,
        .INTR => {},
        .PERM => return error.PermissionDenied,
        else => return error.Unexpected,
    };

    return ev.execv(
        options.spawn.expand_arg0,
        options.argv_buf.ptr[0].?,
        options.argv_buf.ptr,
        options.env_block,
        options.PATH,
    );
}

fn setUpChildIo(
    ev: *Evented,
    stdio: process.SpawnOptions.StdIo,
    pipe_fd: c.fd_t,
    std_fileno: i32,
    dev_null_fd: c.fd_t,
) !void {
    switch (stdio) {
        .pipe => try ev.dup2(pipe_fd, std_fileno),
        .close => closeFd(std_fileno),
        .inherit => {},
        .ignore => try ev.dup2(dev_null_fd, std_fileno),
        .file => |file| try ev.dup2(file.handle, std_fileno),
    }
}

const PipeError = error{
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
} || Io.UnexpectedError;

fn pipe2(flags: c.O) PipeError![2]c.fd_t {
    var fds: [2]c.fd_t = undefined;

    while (true) switch (c.errno(c.pipe(&fds))) {
        .SUCCESS => break,
        .INTR => {},
        .NFILE => return error.SystemFdQuotaExceeded,
        .MFILE => return error.ProcessFdQuotaExceeded,
        else => |err| return unexpectedErrno(err),
    };
    errdefer {
        closeFd(fds[0]);
        closeFd(fds[1]);
    }

    // https://github.com/ziglang/zig/issues/18882
    if (@as(u32, @bitCast(flags)) == 0) return fds;

    // CLOEXEC is special, it's a file descriptor flag and must be set using
    // F.SETFD.
    if (flags.CLOEXEC) for (fds) |fd| while (true) switch (c.errno(c.fcntl(fd, c.F.SETFD, @as(u32, c.FD_CLOEXEC)))) {
        .SUCCESS => break,
        .INTR => {},
        else => |err| return unexpectedErrno(err),
    };

    const new_flags: u32 = f: {
        var new_flags = flags;
        new_flags.CLOEXEC = false;
        break :f @bitCast(new_flags);
    };

    // Set every other flag affecting the file status using F.SETFL.
    if (new_flags != 0) for (fds) |fd| while (true) switch (c.errno(c.fcntl(fd, c.F.SETFL, new_flags))) {
        .SUCCESS => break,
        .INTR => {},
        .INVAL => |err| return errnoBug(err),
        else => |err| return unexpectedErrno(err),
    };

    return fds;
}

fn destroyPipe(pipe: [2]c.fd_t) void {
    if (pipe[0] != -1) closeFd(pipe[0]);
    if (pipe[0] != pipe[1]) closeFd(pipe[1]);
}

const DupError = error{
    ProcessFdQuotaExceeded,
    SystemResources,
} || Io.UnexpectedError || Io.Cancelable;
fn dup2(ev: *Evented, old_fd: c.fd_t, new_fd: c.fd_t) DupError!void {
    _ = ev;
    while (true) switch (c.errno(c.dup2(old_fd, new_fd))) {
        .SUCCESS => return,
        .BUSY, .INTR => {},
        .INVAL => |err| return errnoBug(err), // invalid parameters
        .BADF => |err| return errnoBug(err), // use after free
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NOMEM => return error.SystemResources,
        else => |err| return unexpectedErrno(err),
    };
}

fn execv(
    ev: *Evented,
    arg0_expand: process.ArgExpansion,
    file: [*:0]const u8,
    child_argv: [*:null]?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
    PATH: []const u8,
) process.ReplaceError {
    const file_slice = std.mem.sliceTo(file, 0);
    if (std.mem.findScalar(u8, file_slice, '/') != null) return ev.execvPath(file, child_argv, env_block);

    // Use of PATH_MAX here is valid as the path_buf will be passed
    // directly to the operating system in posixExecvPath.
    var path_buf: [c.PATH_MAX]u8 = undefined;
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
        err = ev.execvPath(full_path, child_argv, env_block);
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
fn execvPath(
    ev: *Evented,
    path: [*:0]const u8,
    child_argv: [*:null]const ?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
) process.ReplaceError {
    _ = ev;
    switch (c.errno(c.execve(path, child_argv, env_block.slice.ptr))) {
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
        .BADEXEC => return error.InvalidExe,
        .BADARCH => return error.InvalidExe,
        else => |err| return unexpectedErrno(err),
    }
}

fn childWait(userdata: ?*anyopaque, child: *process.Child) process.Child.WaitError!process.Child.Term {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    defer ev.childCleanup(child);
    const pid = child.id.?;
    const source = c.dispatch.source_create(
        .PROC,
        @bitCast(@as(isize, pid)),
        .{ .PROC = .{ .EXIT = true } },
        ev.queue,
    ) orelse return error.Unexpected;
    source.as_object().set_context(Thread.current().currentFiber());
    source.set_event_handler(&Fiber.@"resume");
    ev.yield(.{ .activate = source.as_object() });
    source.as_object().release();
    var status: c_int = undefined;
    var ru: c.rusage = undefined;
    const ru_ptr = if (child.request_resource_usage_statistics) &ru else null;
    while (true) switch (c.errno(c.wait4(pid, &status, 0, ru_ptr))) {
        .SUCCESS => {
            if (ru_ptr) |p| child.resource_usage_statistics.rusage = p.*;
            return statusToTerm(@bitCast(status));
        },
        .INTR => {},
        .CHILD => |err| return errnoBug(err), // Double-free.
        else => |err| return unexpectedErrno(err),
    };
}

fn childKill(userdata: ?*anyopaque, child: *process.Child) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    defer ev.childCleanup(child);
    const pid = child.id.?;
    while (true) switch (c.errno(c.kill(pid, .TERM))) {
        .SUCCESS => break,
        .INTR => {},
        .PERM => return,
        .INVAL => |err| errnoBug(err) catch return,
        .SRCH => |err| errnoBug(err) catch return,
        else => |err| unexpectedErrno(err) catch return,
    };
    var status: c_int = undefined;
    while (true) switch (c.errno(c.wait4(pid, &status, 0, null))) {
        .SUCCESS => return,
        .INTR => {},
        .CHILD => |err| errnoBug(err) catch return, // Double-free.
        else => |err| unexpectedErrno(err) catch return,
    };
}

fn childCleanup(ev: *Evented, child: *process.Child) void {
    if (child.stdin) |stdin| {
        fileClose(ev, &.{stdin});
        child.stdin = null;
    }
    if (child.stdout) |stdout| {
        fileClose(ev, &.{stdout});
        child.stdout = null;
    }
    if (child.stderr) |stderr| {
        fileClose(ev, &.{stderr});
        child.stderr = null;
    }
    child.id = null;
}

fn progressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    ev.scan_environ.once(ev, &scanEnviron);
    return ev.environ.zig_progress_file;
}

fn scanEnviron(context: ?*anyopaque) callconv(.c) void {
    const ev: *Evented = @ptrCast(@alignCast(context));
    ev.environ.scan(ev.allocator());
}

fn now(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const clock_id: c.clockid_t = clockToPosix(clock);
    var timespec: c.timespec = undefined;
    switch (c.errno(c.clock_gettime(clock_id, &timespec))) {
        .SUCCESS => return timestampFromPosix(&timespec),
        else => return .zero,
    }
}

fn clockResolution(userdata: ?*anyopaque, clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    const clock_id: c.clockid_t = clockToPosix(clock);
    var timespec: c.timespec = undefined;
    return switch (c.errno(c.clock_getres(clock_id, &timespec))) {
        .SUCCESS => .fromNanoseconds(nanosecondsFromPosix(&timespec)),
        .INVAL => return error.ClockUnavailable,
        else => |err| return unexpectedErrno(err),
    };
}

const SleepWaiter = struct {
    sleeper: Sleeper = undefined,
    cancelable: Cancelable,
    timer: c.dispatch.source_t,
    started: bool = false,

    fn start(context: ?*anyopaque) callconv(.c) void {
        const waiter: *SleepWaiter = @ptrCast(@alignCast(context));
        waiter.cancelable.enter(waiter.sleeper.fiber) catch |err| switch (err) {
            error.CancelRequested => waiter.timer.cancel(),
        };
        waiter.timer.as_object().activate();
    }

    fn timedOut(context: ?*anyopaque) callconv(.c) void {
        const waiter: *SleepWaiter = @ptrCast(@alignCast(context));
        waiter.cancelable.leave(waiter.sleeper.fiber) catch |err| switch (err) {
            error.CancelRequested => return,
        };
        waiter.timer.cancel();
    }

    fn canceled(context: ?*anyopaque) callconv(.c) void {
        const cancelable: *Cancelable = @ptrCast(@alignCast(context));
        const waiter: *SleepWaiter = @fieldParentPtr("cancelable", cancelable);
        cancelable.requested(waiter.sleeper.fiber);
        waiter.timer.cancel();
    }

    fn wake(context: ?*anyopaque) callconv(.c) void {
        const waiter: *SleepWaiter = @ptrCast(@alignCast(context));
        var sleeper = waiter.sleeper;
        waiter.* = undefined;
        Sleeper.wake(&sleeper);
    }
};

fn sleep(userdata: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    const queue = c.dispatch.queue_create_with_target(
        "org.ziglang.std.Io.Dispatch.sleep",
        .SERIAL(),
        ev.queue,
    ) orelse {
        log.warn("failed to create serial queue for sleep", .{});
        return ev.yield(.{ .after = ev.timeFromTimeout(timeout) });
    };
    defer queue.as_object().release();
    const timer = c.dispatch.source_create(.TIMER, 0, .none, queue) orelse {
        log.warn("failed to create timer for sleep", .{});
        return ev.yield(.{ .after = ev.timeFromTimeout(timeout) });
    };
    var waiter: SleepWaiter = .{
        .cancelable = .{ .queue = queue, .cancel = &Futex.Waiter.canceled },
        .timer = timer,
    };
    timer.as_object().set_context(&waiter);
    timer.set_event_handler(&SleepWaiter.timedOut);
    timer.set_cancel_handler(&SleepWaiter.wake);
    timer.set_timer(ev.timeFromTimeout(timeout), c.dispatch.TIME_FOREVER, ev.leeway);
    ev.yield(.{ .sleep_wait = &waiter });
    timer.as_object().release();
    try waiter.cancelable.acknowledge(waiter.sleeper.fiber);
}

fn timeFromTimeout(ev: *Evented, timeout: Io.Timeout) c.dispatch.time_t {
    return timeout: switch (timeout) {
        .none => .FOREVER,
        .duration => |duration| .time(switch (duration.clock) {
            .real => .WALL_NOW,
            else => .NOW,
        }, std.math.lossyCast(i64, duration.raw.toNanoseconds())),
        .deadline => |deadline| switch (deadline.clock) {
            .real => .walltime(&.{
                .sec = @intCast(@divFloor(deadline.raw.toNanoseconds(), std.time.ns_per_s)),
                .nsec = @intCast(@mod(deadline.raw.toNanoseconds(), std.time.ns_per_s)),
            }, 0),
            else => continue :timeout .{ .duration = deadline.durationFromNow(ev.io()) },
        },
    };
}

const Random = struct {
    evented: *Evented,
    thread: *Thread,
    buffer: []u8,

    fn seed(context: ?*anyopaque) callconv(.c) void {
        const rand: *Random = @ptrCast(@alignCast(context));
        const ev = rand.evented;
        ev.csprng_mutex.lockUncancelable(ev);
        defer ev.csprng_mutex.unlock();
        var buffer: [Csprng.seed_len]u8 = undefined;
        if (!ev.csprng.isInitialized()) {
            @branchHint(.unlikely);
            const cancel_protection = swapCancelProtection(ev, .blocked);
            defer assert(swapCancelProtection(ev, cancel_protection) == .blocked);
            randomSecure(ev, &buffer) catch |err| switch (err) {
                error.Canceled => unreachable, // blocked
                error.EntropyUnavailable => fallbackSeed(ev, &buffer),
            };
            ev.csprng.rng = .init(buffer);
        }
        ev.csprng.rng.fill(&buffer);
        rand.thread.csprng.rng = .init(buffer);
        rand.thread.csprng.rng.fill(rand.buffer);
        rand.buffer.len = 0;
    }
};

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    if (buffer.len == 0) return;
    const thread: *Thread = .current();
    var rand: Random = .{ .evented = ev, .thread = thread, .buffer = buffer };
    thread.seed_csprng.once(&rand, &Random.seed);
    if (rand.buffer.len > 0) thread.csprng.rng.fill(buffer);
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    if (buffer.len > 0) c.arc4random_buf(buffer.ptr, buffer.len);
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

fn netBindIpUnavailable(
    userdata: ?*anyopaque,
    address: *const net.IpAddress,
    options: net.IpAddress.BindOptions,
) net.IpAddress.BindError!net.Socket {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = address;
    _ = options;
    return error.NetworkDown;
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
    _ = ev;
    for (handles) |handle| closeFd(handle);
}

fn netShutdownUnavailable(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    how: net.ShutdownHow,
) net.ShutdownError!void {
    const ev: *Evented = @ptrCast(@alignCast(userdata));
    _ = ev;
    _ = handle;
    _ = how;
    unreachable; // How you gonna shutdown something that was impossible to open?
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

fn readAll(ev: *Evented, file: File, buffer: []u8) File.ReadStreamingError!void {
    var index: usize = 0;
    while (buffer.len - index != 0) {
        const len = try ev.fileReadStreaming(file, &.{buffer[index..]});
        if (len == 0) return error.EndOfStream;
        index += len;
    }
}

fn writeAll(ev: *Evented, file: File, buffer: []const u8) (File.Writer.Error || error{EndOfStream})!void {
    var index: usize = 0;
    while (buffer.len - index != 0) {
        const len = try ev.fileWriteStreaming(file, &.{}, &.{buffer[index..]}, 1);
        if (len == 0) return error.EndOfStream;
        index += len;
    }
}

/// This is either usize or u32. Since, either is fine, let's use the same
/// `addBuf` function for both writing to a file and sending network messages.
const iovlen_t = @FieldType(c.msghdr_const, "iovlen");

fn addConstBuf(v: []iovec_const, i: *iovlen_t, remaining: ?*usize, bytes: []const u8) void {
    if (v.len - i.* == 0) return;
    const len = @min(remaining.*, bytes.len);
    if (len == 0) return;
    v[i.*] = .{ .base = bytes.ptr, .len = len };
    i.* += 1;
    remaining.* -= len;
}
fn addBuf(
    comptime is_const: bool,
    vec: []if (is_const) iovec_const else iovec,
    vec_len: *iovlen_t,
    remaining: *Io.Limit,
    bytes: if (is_const) []const u8 else []u8,
) void {
    if (vec.len - vec_len.* == 0) return;
    const len = remaining.minInt(bytes.len);
    if (len == 0) return;
    vec[vec_len.*] = .{ .base = bytes.ptr, .len = len };
    vec_len.* += 1;
    remaining.* = remaining.subtract(len).?;
}

test {
    _ = Fiber.CancelProtection;
}
