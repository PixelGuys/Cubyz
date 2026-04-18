//! This struct represents a kernel thread.
const Thread = @This();

const builtin = @import("builtin");
const target = builtin.target;
const native_os = builtin.os.tag;

const std = @import("std.zig");
const Io = std.Io;
const math = std.math;
const assert = std.debug.assert;
const posix = std.posix;
const windows = std.os.windows;
const testing = std.testing;

pub const use_pthreads = native_os != .windows and native_os != .wasi and builtin.link_libc;

const Impl = if (native_os == .windows)
    WindowsThreadImpl
else if (use_pthreads)
    PosixThreadImpl
else if (native_os == .linux)
    LinuxThreadImpl
else if (native_os == .wasi)
    WasiThreadImpl
else
    UnsupportedImpl;

impl: Impl,

pub const max_name_len = switch (native_os) {
    .linux => 15,
    .windows => 31,
    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => 63,
    .netbsd => 31,
    .freebsd => 15,
    .openbsd => 23,
    .dragonfly => 1023,
    .illumos => 31,
    // https://github.com/SerenityOS/serenity/blob/6b4c300353da49d3508b5442cf61da70bd04d757/Kernel/Tasks/Thread.h#L102
    .serenity => 63,
    else => 0,
};

pub const SetNameError = error{
    NameTooLong,
    Unsupported,
    Unexpected,
    InvalidWtf8,
} || posix.PrctlError || Io.File.Writer.Error || Io.File.OpenError || std.fmt.BufPrintError;

pub fn setName(self: Thread, io: Io, name: []const u8) SetNameError!void {
    if (name.len > max_name_len) return error.NameTooLong;

    const name_with_terminator = blk: {
        var name_buf: [max_name_len:0]u8 = undefined;
        @memcpy(name_buf[0..name.len], name);
        name_buf[name.len] = 0;
        break :blk name_buf[0..name.len :0];
    };

    switch (native_os) {
        .linux => if (use_pthreads) {
            if (self.getHandle() == std.c.pthread_self()) {
                // Set the name of the calling thread (no thread id required).
                assert(try posix.prctl(.SET_NAME, .{@intFromPtr(name_with_terminator.ptr)}) == 0);
                return;
            } else {
                const err = std.c.pthread_setname_np(self.getHandle(), name_with_terminator.ptr);
                switch (@as(posix.E, @enumFromInt(err))) {
                    .SUCCESS => return,
                    .RANGE => unreachable,
                    else => |e| return posix.unexpectedErrno(e),
                }
            }
        } else {
            var buf: [32]u8 = undefined;
            const path = try std.fmt.bufPrint(&buf, "/proc/self/task/{d}/comm", .{self.getHandle()});

            const file = try Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
            defer file.close(io);

            try file.writeStreamingAll(io, name);
            return;
        },
        .windows => {
            var buf: [max_name_len]u16 = undefined;
            switch (windows.ntdll.NtSetInformationThread(
                self.getHandle(),
                .NameInformation,
                &windows.UNICODE_STRING.init(buf[0..try std.unicode.wtf8ToWtf16Le(&buf, name)]),
                @sizeOf(windows.UNICODE_STRING),
            )) {
                .SUCCESS => return,
                .NOT_IMPLEMENTED => return error.Unsupported,
                else => |err| return windows.unexpectedStatus(err),
            }
        },
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => if (use_pthreads) {
            // There doesn't seem to be a way to set the name for an arbitrary thread, only the current one.
            if (self.getHandle() != std.c.pthread_self()) return error.Unsupported;

            const err = std.c.pthread_setname_np(name_with_terminator.ptr);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .serenity => if (use_pthreads) {
            const err = std.c.pthread_setname_np(self.getHandle(), name_with_terminator.ptr);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return,
                .NAMETOOLONG => unreachable,
                .SRCH => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .netbsd, .illumos => if (use_pthreads) {
            const err = std.c.pthread_setname_np(self.getHandle(), name_with_terminator.ptr, null);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return,
                .INVAL => unreachable,
                .SRCH => unreachable,
                .NOMEM => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .freebsd, .openbsd => if (use_pthreads) {
            // Use pthread_set_name_np for FreeBSD because pthread_setname_np is FreeBSD 12.2+ only.
            // TODO maybe revisit this if depending on FreeBSD 12.2+ is acceptable because
            // pthread_setname_np can return an error.

            std.c.pthread_set_name_np(self.getHandle(), name_with_terminator.ptr);
            return;
        },
        .dragonfly => if (use_pthreads) {
            const err = std.c.pthread_setname_np(self.getHandle(), name_with_terminator.ptr);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return,
                .INVAL => unreachable,
                .FAULT => unreachable,
                .NAMETOOLONG => unreachable, // already checked
                .SRCH => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        else => {},
    }
    return error.Unsupported;
}

pub const GetNameError = error{
    Unsupported,
    Unexpected,
} || posix.PrctlError || posix.ReadError || Io.File.OpenError || std.fmt.BufPrintError;

/// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On other platforms, the result is an opaque sequence of bytes with no particular encoding.
pub fn getName(self: Thread, buffer_ptr: *[max_name_len:0]u8) GetNameError!?[]const u8 {
    buffer_ptr[max_name_len] = 0;
    var buffer: [:0]u8 = buffer_ptr;

    switch (native_os) {
        .linux => if (use_pthreads) {
            if (self.getHandle() == std.c.pthread_self()) {
                // Get the name of the calling thread (no thread id required).
                assert(try posix.prctl(.GET_NAME, .{@intFromPtr(buffer.ptr)}) == 0);
                return std.mem.sliceTo(buffer, 0);
            } else {
                const err = std.c.pthread_getname_np(self.getHandle(), buffer.ptr, max_name_len + 1);
                switch (@as(posix.E, @enumFromInt(err))) {
                    .SUCCESS => return std.mem.sliceTo(buffer, 0),
                    .RANGE => unreachable,
                    else => |e| return posix.unexpectedErrno(e),
                }
            }
        } else {
            var buf: [32]u8 = undefined;
            const path = try std.fmt.bufPrint(&buf, "/proc/self/task/{d}/comm", .{self.getHandle()});

            const io = std.Options.debug_io;

            const file = try Io.Dir.cwd().openFile(io, path, .{});
            defer file.close(io);

            var file_reader = file.readerStreaming(io, &.{});
            const data_len = file_reader.interface.readSliceShort(buffer_ptr[0 .. max_name_len + 1]) catch |err| switch (err) {
                error.ReadFailed => return file_reader.err.?,
            };
            return if (data_len >= 1) buffer[0 .. data_len - 1] else null;
        },
        .windows => {
            const buf_capacity = @sizeOf(windows.UNICODE_STRING) + (@sizeOf(u16) * max_name_len);
            var buf: [buf_capacity]u8 align(@alignOf(windows.UNICODE_STRING)) = undefined;

            switch (windows.ntdll.NtQueryInformationThread(
                self.getHandle(),
                .NameInformation,
                &buf,
                buf_capacity,
                null,
            )) {
                .SUCCESS => {
                    const string: *const windows.UNICODE_STRING = @ptrCast(&buf);
                    const len = std.unicode.wtf16LeToWtf8(buffer, string.slice());
                    return if (len > 0) buffer[0..len] else null;
                },
                .NOT_IMPLEMENTED => return error.Unsupported,
                else => |err| return windows.unexpectedStatus(err),
            }
        },
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => if (use_pthreads) {
            const err = std.c.pthread_getname_np(self.getHandle(), buffer.ptr, max_name_len + 1);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return std.mem.sliceTo(buffer, 0),
                .SRCH => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .serenity => if (use_pthreads) {
            const err = std.c.pthread_getname_np(self.getHandle(), buffer.ptr, max_name_len + 1);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return,
                .NAMETOOLONG => unreachable,
                .SRCH => unreachable,
                .FAULT => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .netbsd, .illumos => if (use_pthreads) {
            const err = std.c.pthread_getname_np(self.getHandle(), buffer.ptr, max_name_len + 1);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return std.mem.sliceTo(buffer, 0),
                .INVAL => unreachable,
                .SRCH => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        .freebsd, .openbsd => if (use_pthreads) {
            // Use pthread_get_name_np for FreeBSD because pthread_getname_np is FreeBSD 12.2+ only.
            // TODO maybe revisit this if depending on FreeBSD 12.2+ is acceptable because pthread_getname_np can return an error.

            std.c.pthread_get_name_np(self.getHandle(), buffer.ptr, max_name_len + 1);
            return std.mem.sliceTo(buffer, 0);
        },
        .dragonfly => if (use_pthreads) {
            const err = std.c.pthread_getname_np(self.getHandle(), buffer.ptr, max_name_len + 1);
            switch (@as(posix.E, @enumFromInt(err))) {
                .SUCCESS => return std.mem.sliceTo(buffer, 0),
                .INVAL => unreachable,
                .FAULT => unreachable,
                .SRCH => unreachable,
                else => |e| return posix.unexpectedErrno(e),
            }
        },
        else => {},
    }
    return error.Unsupported;
}

/// Represents an ID per thread guaranteed to be unique only within a process.
pub const Id = switch (native_os) {
    .linux,
    .dragonfly,
    .netbsd,
    .freebsd,
    .openbsd,
    .haiku,
    .wasi,
    .serenity,
    => u32,
    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => u64,
    .windows => windows.DWORD,
    else => usize,
};

/// Returns the platform ID of the callers thread.
/// Attempts to use thread locals and avoid syscalls when possible.
pub fn getCurrentId() Id {
    return Impl.getCurrentId();
}

pub const CpuCountError = error{
    PermissionDenied,
    SystemResources,
    Unsupported,
    Unexpected,
};

/// Returns the platforms view on the number of logical CPU cores available.
///
/// Returned value guaranteed to be >= 1.
pub fn getCpuCount() CpuCountError!usize {
    return try Impl.getCpuCount();
}

/// Configuration options for hints on how to spawn threads.
pub const SpawnConfig = struct {
    // TODO compile-time call graph analysis to determine stack upper bound
    // https://github.com/ziglang/zig/issues/157

    /// Size in bytes of the Thread's stack
    stack_size: usize = default_stack_size,
    /// The allocator to be used to allocate memory for the to-be-spawned thread
    allocator: ?std.mem.Allocator = null,

    pub const default_stack_size = 16 * 1024 * 1024;
};

pub const SpawnError = error{
    /// A system-imposed limit on the number of threads was encountered.
    /// There are a number of limits that may trigger this error:
    /// *  the  RLIMIT_NPROC soft resource limit (set via setrlimit(2)),
    ///    which limits the number of processes and threads for  a  real
    ///    user ID, was reached;
    /// *  the kernel's system-wide limit on the number of processes and
    ///    threads,  /proc/sys/kernel/threads-max,  was   reached   (see
    ///    proc(5));
    /// *  the  maximum  number  of  PIDs, /proc/sys/kernel/pid_max, was
    ///    reached (see proc(5)); or
    /// *  the PID limit (pids.max) imposed by the cgroup "process  num‐
    ///    ber" (PIDs) controller was reached.
    ThreadQuotaExceeded,

    /// The kernel cannot allocate sufficient memory to allocate a task structure
    /// for the child, or to copy those parts of the caller's context that need to
    /// be copied.
    SystemResources,

    /// Not enough userland memory to spawn the thread.
    OutOfMemory,

    /// `mlockall` is enabled, and the memory needed to spawn the thread
    /// would exceed the limit.
    LockedMemoryLimitExceeded,

    Unexpected,
};

/// Spawns a new thread which executes `function` using `args` and returns a handle to the spawned thread.
/// `config` can be used as hints to the platform for how to spawn and execute the `function`.
/// The caller must eventually either call `join()` to wait for the thread to finish and free its resources
/// or call `detach()` to excuse the caller from calling `join()` and have the thread clean up its resources on completion.
pub fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread {
    if (builtin.single_threaded) {
        @compileError("Cannot spawn thread when building in single-threaded mode");
    }

    const impl = try Impl.spawn(config, function, args);
    return Thread{ .impl = impl };
}

/// Represents a kernel thread handle.
/// May be an integer or a pointer depending on the platform.
pub const Handle = Impl.ThreadHandle;

/// Returns the handle of this thread
pub fn getHandle(self: Thread) Handle {
    return self.impl.getHandle();
}

/// Release the obligation of the caller to call `join()` and have the thread clean up its own resources on completion.
/// Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.
pub fn detach(self: Thread) void {
    return self.impl.detach();
}

/// Waits for the thread to complete, then deallocates any resources created on `spawn()`.
/// Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.
pub fn join(self: Thread) void {
    return self.impl.join();
}

pub const YieldError = error{
    /// The system is not configured to allow yielding
    SystemCannotYield,
};

/// Yields the current thread potentially allowing other threads to run.
pub fn yield() YieldError!void {
    if (native_os == .windows) switch (windows.ntdll.NtYieldExecution()) {
        .SUCCESS, .NO_YIELD_PERFORMED => return,
        else => return error.SystemCannotYield,
    };
    switch (posix.errno(posix.system.sched_yield())) {
        .SUCCESS => return,
        .NOSYS => return error.SystemCannotYield,
        else => return error.SystemCannotYield,
    }
}

/// State to synchronize detachment of spawner thread to spawned thread
const Completion = std.atomic.Value(enum(if (builtin.zig_backend == .stage2_riscv64) u32 else u8) {
    running,
    detached,
    completed,
});

/// Performs implementation-agnostic thread setup (`maybeAttachSignalStack`), then calls the given
/// thread entry point `f` with `args` and handles the result.
fn callFn(comptime f: anytype, args: anytype) switch (Impl) {
    WindowsThreadImpl => windows.NTSTATUS,
    LinuxThreadImpl => u8,
    PosixThreadImpl => ?*anyopaque,
    else => unreachable,
} {
    maybeAttachSignalStack();

    const default_value = switch (Impl) {
        WindowsThreadImpl => .SUCCESS,
        LinuxThreadImpl => 0,
        PosixThreadImpl => null,
        else => unreachable,
    };
    const bad_fn_ret = "expected return type of startFn to be 'u8', 'noreturn', '!noreturn', 'void', or '!void'";

    switch (@typeInfo(@typeInfo(@TypeOf(f)).@"fn".return_type.?)) {
        .noreturn => {
            @call(.auto, f, args);
        },
        .void => {
            @call(.auto, f, args);
            return default_value;
        },
        .int => |info| {
            if (info.bits != 8) {
                @compileError(bad_fn_ret);
            }

            const status = @call(.auto, f, args);
            switch (Impl) {
                WindowsThreadImpl => return @enumFromInt(status),
                LinuxThreadImpl => return status,
                // pthreads don't support exit status, ignore value
                PosixThreadImpl => return default_value,
                else => unreachable,
            }
        },
        .error_union => |info| {
            switch (info.payload) {
                void, noreturn => {
                    @call(.auto, f, args) catch |err| {
                        std.debug.print("error: {s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpErrorReturnTrace(trace);
                        }
                    };

                    return default_value;
                },
                else => {
                    @compileError(bad_fn_ret);
                },
            }
        },
        else => {
            @compileError(bad_fn_ret);
        },
    }
}

/// We can't compile error in the `Impl` switch statement as its eagerly evaluated.
/// So instead, we compile-error on the methods themselves for platforms which don't support threads.
const UnsupportedImpl = struct {
    pub const ThreadHandle = void;

    fn getCurrentId() usize {
        return unsupported({});
    }

    fn getCpuCount() !usize {
        return unsupported({});
    }

    fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) !Impl {
        return unsupported(.{ config, f, args });
    }

    fn getHandle(self: Impl) ThreadHandle {
        return unsupported(self);
    }

    fn detach(self: Impl) void {
        return unsupported(self);
    }

    fn join(self: Impl) void {
        return unsupported(self);
    }

    fn unsupported(unused: anytype) noreturn {
        _ = unused;
        @compileError("Unsupported operating system " ++ @tagName(native_os));
    }
};

const WindowsThreadImpl = struct {
    pub const ThreadHandle = windows.HANDLE;

    fn getCurrentId() windows.DWORD {
        return windows.GetCurrentThreadId();
    }

    fn getCpuCount() !usize {
        // Faster than calling into GetSystemInfo(), even if amortized.
        return windows.peb().NumberOfProcessors;
    }

    thread: *ThreadCompletion,

    const ThreadCompletion = struct {
        completion: Completion,
        heap_ptr: windows.PVOID,
        heap_handle: *windows.HEAP,
        thread_handle: windows.HANDLE = undefined,

        fn free(self: ThreadCompletion) void {
            const status = windows.ntdll.RtlFreeHeap(self.heap_handle, .{}, self.heap_ptr);
            assert(status != 0);
        }
    };

    fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) !Impl {
        const Args = @TypeOf(args);
        const Instance = struct {
            fn_args: Args,
            thread: ThreadCompletion,

            fn entryFn(raw_ptr: windows.PVOID) callconv(.winapi) windows.NTSTATUS {
                const self: *@This() = @ptrCast(@alignCast(raw_ptr));
                defer switch (self.thread.completion.swap(.completed, .seq_cst)) {
                    .running => {},
                    .completed => unreachable,
                    .detached => self.thread.free(),
                };
                return callFn(f, self.fn_args);
            }
        };

        const heap_handle = windows.GetProcessHeap() orelse return error.OutOfMemory;
        const alloc_bytes = @alignOf(Instance) + @sizeOf(Instance);
        const alloc_ptr = windows.ntdll.RtlAllocateHeap(heap_handle, .{}, alloc_bytes) orelse return error.OutOfMemory;
        errdefer assert(windows.ntdll.RtlFreeHeap(heap_handle, .{}, alloc_ptr) != 0);

        const instance_bytes = @as([*]u8, @ptrCast(alloc_ptr))[0..alloc_bytes];
        var fba = std.heap.FixedBufferAllocator.init(instance_bytes);
        const instance = fba.allocator().create(Instance) catch unreachable;
        instance.* = .{
            .fn_args = args,
            .thread = .{
                .completion = Completion.init(.running),
                .heap_ptr = alloc_ptr,
                .heap_handle = heap_handle,
            },
        };

        // Windows appears to only support SYSTEM.BASIC_INFORMATION.AllocationGranularity
        // minimum stack size. Going lower makes it default to that specified in the executable
        // (~1mb). Its also fine if the limit here is incorrect as stack size is only a hint.
        const stack_size = @max(64 * 1024, std.math.lossyCast(u32, config.stack_size));

        // Intended to be equivalent to a kernel32.CreateThread call with no flags set.
        // However, CreateThread is just a wrapper around CreateRemoteThreadEx,
        // so that's the more relevant function in this context.
        //
        // https://github.com/wine-mirror/wine/blob/3d128be6400b3869119d293d0c8fa9e7702978f8/dlls/kernelbase/thread.c#L85
        instance.thread.thread_handle = blk: {
            var active_ctx: ?windows.HANDLE = undefined;
            // Note: Can return null on SUCCESS
            switch (windows.ntdll.RtlGetActiveActivationContext(&active_ctx)) {
                .SUCCESS => {},
                else => |status| return windows.unexpectedStatus(status),
            }
            defer if (active_ctx) |ctx| windows.ntdll.RtlReleaseActivationContext(ctx);

            var teb: *windows.TEB = undefined;
            var attr_list = windows.PS.ATTRIBUTE.LIST{
                .TotalLength = @sizeOf(windows.PS.ATTRIBUTE.LIST),
                .Attributes = .{
                    .{
                        .Attribute = .TEB_ADDRESS,
                        .Size = @sizeOf(*windows.TEB),
                        .u = .{
                            .ValuePtr = @ptrCast(&teb),
                        },
                        .ReturnLength = null,
                    },
                },
            };

            var thread_handle: windows.HANDLE = undefined;
            switch (windows.ntdll.NtCreateThreadEx(
                &thread_handle,
                .{ .MAXIMUM_ALLOWED = true },
                &.{},
                windows.GetCurrentProcess(),
                Instance.entryFn,
                instance,
                .{ .CREATE_SUSPENDED = true },
                0,
                @enumFromInt(stack_size),
                .default,
                &attr_list,
            )) {
                .SUCCESS => {},
                else => |status| return windows.unexpectedStatus(status),
            }

            if (active_ctx) |ctx| {
                var cookie: windows.ULONG = 0;
                switch (windows.ntdll.RtlActivateActivationContextEx(0, teb, ctx, &cookie)) {
                    .SUCCESS => {},
                    else => |status| return windows.unexpectedStatus(status),
                }
            }

            switch (windows.ntdll.NtResumeThread(thread_handle, null)) {
                .SUCCESS => {},
                else => |status| return windows.unexpectedStatus(status),
            }

            break :blk thread_handle;
        };

        return Impl{ .thread = &instance.thread };
    }

    fn getHandle(self: Impl) ThreadHandle {
        return self.thread.thread_handle;
    }

    fn detach(self: Impl) void {
        windows.CloseHandle(self.thread.thread_handle);
        switch (self.thread.completion.swap(.detached, .seq_cst)) {
            .running => {},
            .completed => self.thread.free(),
            .detached => unreachable,
        }
    }

    fn join(self: Impl) void {
        const infinite_timeout: windows.LARGE_INTEGER = std.math.minInt(windows.LARGE_INTEGER);
        switch (windows.ntdll.NtWaitForSingleObject(self.thread.thread_handle, .FALSE, &infinite_timeout)) {
            windows.NTSTATUS.WAIT_0 => {},
            else => |status| windows.unexpectedStatus(status) catch unreachable,
        }
        windows.CloseHandle(self.thread.thread_handle);
        assert(self.thread.completion.load(.seq_cst) == .completed);
        self.thread.free();
    }
};

const PosixThreadImpl = struct {
    const c = std.c;

    pub const ThreadHandle = c.pthread_t;

    fn getCurrentId() Id {
        switch (native_os) {
            .linux => {
                return LinuxThreadImpl.getCurrentId();
            },
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
                var thread_id: u64 = undefined;
                // Pass thread=null to get the current thread ID.
                assert(c.pthread_threadid_np(null, &thread_id) == 0);
                return thread_id;
            },
            .dragonfly => {
                return @as(u32, @bitCast(c.lwp_gettid()));
            },
            .netbsd => {
                return @as(u32, @bitCast(c._lwp_self()));
            },
            .freebsd => {
                return @as(u32, @bitCast(c.pthread_getthreadid_np()));
            },
            .openbsd => {
                return @as(u32, @bitCast(c.getthrid()));
            },
            .haiku => {
                return @as(u32, @bitCast(c.find_thread(null)));
            },
            .serenity => {
                return @as(u32, @bitCast(c.pthread_self()));
            },
            else => {
                return @intFromPtr(c.pthread_self());
            },
        }
    }

    fn getCpuCount() !usize {
        switch (native_os) {
            .linux => {
                return LinuxThreadImpl.getCpuCount();
            },
            .openbsd => {
                var count: c_int = undefined;
                var count_size: usize = @sizeOf(c_int);
                const mib = [_]c_int{ std.c.CTL.HW, std.c.HW.NCPUONLINE };
                posix.sysctl(&mib, &count, &count_size, null, 0) catch |err| switch (err) {
                    error.NameTooLong, error.UnknownName => unreachable,
                    else => |e| return e,
                };
                return @as(usize, @intCast(count));
            },
            .illumos, .serenity => {
                // The "proper" way to get the cpu count would be to query
                // /dev/kstat via ioctls, and traverse a linked list for each
                // cpu. (illumos)
                const rc = c.sysconf(@intFromEnum(std.c._SC.NPROCESSORS_ONLN));
                return switch (posix.errno(rc)) {
                    .SUCCESS => @as(usize, @intCast(rc)),
                    else => |err| posix.unexpectedErrno(err),
                };
            },
            .haiku => {
                var system_info: std.c.system_info = undefined;
                const rc = std.c.get_system_info(&system_info); // always returns B_OK
                return switch (posix.errno(rc)) {
                    .SUCCESS => @as(usize, @intCast(system_info.cpu_count)),
                    else => |err| posix.unexpectedErrno(err),
                };
            },
            else => {
                var count: c_int = undefined;
                var count_len: usize = @sizeOf(c_int);
                const name = comptime if (target.os.tag.isDarwin()) "hw.logicalcpu" else "hw.ncpu";
                switch (posix.errno(posix.system.sysctlbyname(name, &count, &count_len, null, 0))) {
                    .SUCCESS => return @intCast(count),
                    .FAULT => unreachable,
                    .PERM => return error.PermissionDenied,
                    .NOMEM => return error.SystemResources,
                    .NOENT => unreachable,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }

    handle: ThreadHandle,

    fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) !Impl {
        const Args = @TypeOf(args);
        const allocator = std.heap.c_allocator;

        const Instance = struct {
            fn entryFn(raw_arg: ?*anyopaque) callconv(.c) ?*anyopaque {
                const args_ptr: *Args = @ptrCast(@alignCast(raw_arg));
                defer allocator.destroy(args_ptr);
                return callFn(f, args_ptr.*);
            }
        };

        const args_ptr = try allocator.create(Args);
        args_ptr.* = args;
        errdefer allocator.destroy(args_ptr);

        var attr: c.pthread_attr_t = undefined;
        if (c.pthread_attr_init(&attr) != .SUCCESS) return error.SystemResources;
        defer assert(c.pthread_attr_destroy(&attr) == .SUCCESS);

        // Use the same set of parameters used by the libc-less impl.
        const stack_size = @max(config.stack_size, 16 * 1024);
        assert(c.pthread_attr_setstacksize(&attr, stack_size) == .SUCCESS);
        assert(c.pthread_attr_setguardsize(&attr, std.heap.pageSize()) == .SUCCESS);

        var handle: c.pthread_t = undefined;
        switch (c.pthread_create(
            &handle,
            &attr,
            Instance.entryFn,
            @ptrCast(args_ptr),
        )) {
            .SUCCESS => return Impl{ .handle = handle },
            .AGAIN => return error.SystemResources,
            .PERM => unreachable,
            .INVAL => unreachable,
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    fn getHandle(self: Impl) ThreadHandle {
        return self.handle;
    }

    fn detach(self: Impl) void {
        switch (c.pthread_detach(self.handle)) {
            .SUCCESS => {},
            .INVAL => unreachable, // thread handle is not joinable
            .SRCH => unreachable, // thread handle is invalid
            else => unreachable,
        }
    }

    fn join(self: Impl) void {
        switch (c.pthread_join(self.handle, null)) {
            .SUCCESS => {},
            .INVAL => unreachable, // thread handle is not joinable (or another thread is already joining in)
            .SRCH => unreachable, // thread handle is invalid
            .DEADLK => unreachable, // two threads tried to join each other
            else => unreachable,
        }
    }
};

const WasiThreadImpl = struct {
    thread: *WasiThread,

    pub const ThreadHandle = i32;
    threadlocal var tls_thread_id: Id = 0;

    const WasiThread = struct {
        /// Thread ID
        tid: std.atomic.Value(i32) = std.atomic.Value(i32).init(0),
        /// Contains all memory which was allocated to bootstrap this thread, including:
        /// - Guard page
        /// - Stack
        /// - TLS segment
        /// - `Instance`
        /// All memory is freed upon call to `join`
        memory: []u8,
        /// The allocator used to allocate the thread's memory,
        /// which is also used during `join` to ensure clean-up.
        allocator: std.mem.Allocator,
        /// The current state of the thread.
        state: State = State.init(.running),
    };

    /// A meta-data structure used to bootstrap a thread
    const Instance = struct {
        thread: WasiThread,
        /// Contains the offset to the new __tls_base.
        /// The offset starting from the memory's base.
        tls_offset: usize,
        /// Contains the offset to the stack for the newly spawned thread.
        /// The offset is calculated starting from the memory's base.
        stack_offset: usize,
        /// Contains the raw pointer value to the wrapper which holds all arguments
        /// for the callback.
        raw_ptr: usize,
        /// Function pointer to a wrapping function which will call the user's
        /// function upon thread spawn. The above mentioned pointer will be passed
        /// to this function pointer as its argument.
        call_back: *const fn (usize) void,
        /// When a thread is in `detached` state, we must free all of its memory
        /// upon thread completion. However, as this is done while still within
        /// the thread, we must first jump back to the main thread's stack or else
        /// we end up freeing the stack that we're currently using.
        original_stack_pointer: [*]u8,
    };

    const State = std.atomic.Value(enum(u8) { running, completed, detached });

    fn getCurrentId() Id {
        return tls_thread_id;
    }

    fn getCpuCount() error{Unsupported}!noreturn {
        return error.Unsupported;
    }

    fn getHandle(self: Impl) ThreadHandle {
        return self.thread.tid.load(.seq_cst);
    }

    fn detach(self: Impl) void {
        switch (self.thread.state.swap(.detached, .seq_cst)) {
            .running => {},
            .completed => self.join(),
            .detached => unreachable,
        }
    }

    fn join(self: Impl) void {
        defer {
            // Create a copy of the allocator so we do not free the reference to the
            // original allocator while freeing the memory.
            var allocator = self.thread.allocator;
            allocator.free(self.thread.memory);
        }

        while (true) {
            const tid = self.thread.tid.load(.seq_cst);
            if (tid == 0) break;

            const result = asm (
                \\ local.get %[ptr]
                \\ local.get %[expected]
                \\ i64.const -1 # infinite
                \\ memory.atomic.wait32 0
                \\ local.set %[ret]
                : [ret] "=r" (-> u32),
                : [ptr] "r" (&self.thread.tid.raw),
                  [expected] "r" (tid),
            );
            switch (result) {
                0 => continue, // ok
                1 => continue, // expected =! loaded
                2 => unreachable, // timeout (infinite)
                else => unreachable,
            }
        }
    }

    fn spawn(config: std.Thread.SpawnConfig, comptime f: anytype, args: anytype) SpawnError!WasiThreadImpl {
        if (config.allocator == null) {
            @panic("an allocator is required to spawn a WASI thread");
        }

        // Wrapping struct required to hold the user-provided function arguments.
        const Wrapper = struct {
            args: @TypeOf(args),
            fn entry(ptr: usize) void {
                const w: *@This() = @ptrFromInt(ptr);
                const bad_fn_ret = "expected return type of startFn to be 'u8', 'noreturn', 'void', or '!void'";
                switch (@typeInfo(@typeInfo(@TypeOf(f)).@"fn".return_type.?)) {
                    .noreturn, .void => {
                        @call(.auto, f, w.args);
                    },
                    .int => |info| {
                        if (info.bits != 8) {
                            @compileError(bad_fn_ret);
                        }
                        _ = @call(.auto, f, w.args); // WASI threads don't support exit status, ignore value
                    },
                    .error_union => |info| {
                        if (info.payload != void) {
                            @compileError(bad_fn_ret);
                        }
                        @call(.auto, f, w.args) catch |err| {
                            std.debug.print("error: {s}\n", .{@errorName(err)});
                            if (@errorReturnTrace()) |trace| {
                                std.debug.dumpErrorReturnTrace(trace);
                            }
                        };
                    },
                    else => {
                        @compileError(bad_fn_ret);
                    },
                }
            }
        };

        var stack_offset: usize = undefined;
        var tls_offset: usize = undefined;
        var wrapper_offset: usize = undefined;
        var instance_offset: usize = undefined;

        // Calculate the bytes we have to allocate to store all thread information, including:
        // - The actual stack for the thread
        // - The TLS segment
        // - `Instance` - containing information about how to call the user's function.
        const map_bytes = blk: {
            // start with atleast a single page, which is used as a guard to prevent
            // other threads clobbering our new thread.
            // Unfortunately, WebAssembly has no notion of read-only segments, so this
            // is only a best effort.
            var bytes: usize = std.wasm.page_size;

            bytes = std.mem.alignForward(usize, bytes, 16); // align stack to 16 bytes
            stack_offset = bytes;
            bytes += @max(std.wasm.page_size, config.stack_size);

            bytes = std.mem.alignForward(usize, bytes, __tls_align());
            tls_offset = bytes;
            bytes += __tls_size();

            bytes = std.mem.alignForward(usize, bytes, @alignOf(Wrapper));
            wrapper_offset = bytes;
            bytes += @sizeOf(Wrapper);

            bytes = std.mem.alignForward(usize, bytes, @alignOf(Instance));
            instance_offset = bytes;
            bytes += @sizeOf(Instance);

            bytes = std.mem.alignForward(usize, bytes, std.wasm.page_size);
            break :blk bytes;
        };

        // Allocate the amount of memory required for all meta data.
        const allocated_memory = try config.allocator.?.alloc(u8, map_bytes);

        const wrapper: *Wrapper = @ptrCast(@alignCast(&allocated_memory[wrapper_offset]));
        wrapper.* = .{ .args = args };

        const instance: *Instance = @ptrCast(@alignCast(&allocated_memory[instance_offset]));
        instance.* = .{
            .thread = .{ .memory = allocated_memory, .allocator = config.allocator.? },
            .tls_offset = tls_offset,
            .stack_offset = stack_offset,
            .raw_ptr = @intFromPtr(wrapper),
            .call_back = &Wrapper.entry,
            .original_stack_pointer = __get_stack_pointer(),
        };

        const tid = spawnWasiThread(instance);
        // The specification says any value lower than 0 indicates an error.
        // The values of such error are unspecified. WASI-Libc treats it as EAGAIN.
        if (tid < 0) {
            return error.SystemResources;
        }
        instance.thread.tid.store(tid, .seq_cst);

        return .{ .thread = &instance.thread };
    }

    comptime {
        if (!builtin.single_threaded) {
            @export(&wasi_thread_start, .{ .name = "wasi_thread_start" });
        }
    }

    /// Called by the host environment after thread creation.
    fn wasi_thread_start(tid: i32, arg: *Instance) callconv(.c) void {
        comptime assert(!builtin.single_threaded);
        __set_stack_pointer(arg.thread.memory.ptr + arg.stack_offset);
        __wasm_init_tls(arg.thread.memory.ptr + arg.tls_offset);
        @atomicStore(u32, &WasiThreadImpl.tls_thread_id, @intCast(tid), .seq_cst);

        // Finished bootstrapping, call user's procedure.
        arg.call_back(arg.raw_ptr);

        switch (arg.thread.state.swap(.completed, .seq_cst)) {
            .running => {
                // reset the Thread ID
                asm volatile (
                    \\ local.get %[ptr]
                    \\ i32.const 0
                    \\ i32.atomic.store 0
                    :
                    : [ptr] "r" (&arg.thread.tid.raw),
                );

                // Wake the main thread listening to this thread
                asm volatile (
                    \\ local.get %[ptr]
                    \\ i32.const 1 # waiters
                    \\ memory.atomic.notify 0
                    \\ drop # no need to know the waiters
                    :
                    : [ptr] "r" (&arg.thread.tid.raw),
                );
            },
            .completed => unreachable,
            .detached => {
                // restore the original stack pointer so we can free the memory
                // without having to worry about freeing the stack
                __set_stack_pointer(arg.original_stack_pointer);
                // Ensure a copy so we don't free the allocator reference itself
                var allocator = arg.thread.allocator;
                allocator.free(arg.thread.memory);
            },
        }
    }

    /// Asks the host to create a new thread for us.
    /// Newly created thread will call `wasi_tread_start` with the thread ID as well
    /// as the input `arg` that was provided to `spawnWasiThread`
    const spawnWasiThread = @"thread-spawn";
    extern "wasi" fn @"thread-spawn"(arg: *Instance) i32;

    /// Initializes the TLS data segment starting at `memory`.
    /// This is a synthetic function, generated by the linker.
    extern fn __wasm_init_tls(memory: [*]u8) void;

    /// Returns a pointer to the base of the TLS data segment for the current thread
    inline fn __tls_base() [*]u8 {
        return asm (
            \\ .globaltype __tls_base, i32
            \\ global.get __tls_base
            \\ local.set %[ret]
            : [ret] "=r" (-> [*]u8),
        );
    }

    /// Returns the size of the TLS segment
    inline fn __tls_size() u32 {
        return asm volatile (
            \\ .globaltype __tls_size, i32, immutable
            \\ global.get __tls_size
            \\ local.set %[ret]
            : [ret] "=r" (-> u32),
        );
    }

    /// Returns the alignment of the TLS segment
    inline fn __tls_align() u32 {
        return asm (
            \\ .globaltype __tls_align, i32, immutable
            \\ global.get __tls_align
            \\ local.set %[ret]
            : [ret] "=r" (-> u32),
        );
    }

    /// Allows for setting the stack pointer in the WebAssembly module.
    inline fn __set_stack_pointer(addr: [*]u8) void {
        asm volatile (
            \\ local.get %[ptr]
            \\ global.set __stack_pointer
            :
            : [ptr] "r" (addr),
        );
    }

    /// Returns the current value of the stack pointer
    inline fn __get_stack_pointer() [*]u8 {
        return asm (
            \\ global.get __stack_pointer
            \\ local.set %[stack_ptr]
            : [stack_ptr] "=r" (-> [*]u8),
        );
    }
};

const LinuxThreadImpl = struct {
    const linux = std.os.linux;

    pub const ThreadHandle = i32;

    threadlocal var tls_thread_id: ?Id = null;

    fn getCurrentId() Id {
        return tls_thread_id orelse {
            const tid: u32 = @bitCast(linux.gettid());
            tls_thread_id = tid;
            return tid;
        };
    }

    fn getCpuCount() !usize {
        const cpu_set = try posix.sched_getaffinity(0);
        return posix.CPU_COUNT(cpu_set);
    }

    thread: *ThreadCompletion,

    const ThreadCompletion = struct {
        completion: Completion = Completion.init(.running),
        child_tid: std.atomic.Value(i32) = std.atomic.Value(i32).init(1),
        parent_tid: i32 = undefined,
        mapped: []align(std.heap.page_size_min) u8,

        /// Calls `munmap(mapped.ptr, mapped.len)` then `exit(1)` without touching the stack (which lives in `mapped.ptr`).
        /// Ported over from musl libc's pthread detached implementation:
        /// https://github.com/ifduyue/musl/search?q=__unmapself
        fn freeAndExit(self: *ThreadCompletion) noreturn {
            // If we do not reset the child_tidptr to null here, the kernel would later write the
            // value zero to that address, which is inside the block we're unmapping below, after
            // our thread exits.  This can sometimes corrupt memory in other mmap blocks from
            // unrelated concurrent threads.
            _ = linux.set_tid_address(null);
            // If a signal were delivered between SYS_munmap and SYS_exit, any installed signal
            // handler would immediately segfault due to the stack being unmapped. To avoid this,
            // we need to mask all signals before entering the inline asm.
            posix.sigprocmask(std.posix.SIG.BLOCK, &std.os.linux.sigfillset(), null);
            switch (target.cpu.arch) {
                .x86 => asm volatile (
                    \\  movl $91, %%eax # SYS_munmap
                    \\  int $128
                    \\  movl $1, %%eax # SYS_exit
                    \\  movl $0, %%ebx
                    \\  int $128
                    :
                    : [ptr] "{ebx}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{ecx}" (self.mapped.len),
                ),
                .x86_64 => asm volatile (switch (target.abi) {
                        .gnux32, .muslx32 =>
                        \\  movl $0x4000000b, %%eax # SYS_munmap
                        \\  syscall
                        \\  movl $0x4000003c, %%eax # SYS_exit
                        \\  xor %%rdi, %%rdi
                        \\  syscall
                        ,
                        else =>
                        \\  movl $11, %%eax # SYS_munmap
                        \\  syscall
                        \\  movl $60, %%eax # SYS_exit
                        \\  xor %%rdi, %%rdi
                        \\  syscall
                        ,
                    }
                    :
                    : [ptr] "{rdi}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{rsi}" (self.mapped.len),
                ),
                .arm, .armeb, .thumb, .thumbeb => asm volatile (
                    \\  mov r7, #91 // SYS_munmap
                    \\  svc 0
                    \\  mov r7, #1 // SYS_exit
                    \\  mov r0, #0
                    \\  svc 0
                    :
                    : [ptr] "{r0}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r1}" (self.mapped.len),
                ),
                .aarch64, .aarch64_be => asm volatile (
                    \\  mov x8, #215 // SYS_munmap
                    \\  svc 0
                    \\  mov x8, #93 // SYS_exit
                    \\  mov x0, #0
                    \\  svc 0
                    :
                    : [ptr] "{x0}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{x1}" (self.mapped.len),
                ),
                .alpha => asm volatile (
                    \\ ldi $0, 73 # SYS_munmap
                    \\ callsys
                    \\ ldi $0, 1 # SYS_exit
                    \\ ldi $16, 0
                    \\ callsys
                    :
                    : [ptr] "{r16}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r17}" (self.mapped.len),
                ),
                .hexagon => asm volatile (
                    \\  r6 = #215 // SYS_munmap
                    \\  trap0(#1)
                    \\  r6 = #93 // SYS_exit
                    \\  r0 = #0
                    \\  trap0(#1)
                    :
                    : [ptr] "{r0}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r1}" (self.mapped.len),
                ),
                .hppa => asm volatile (
                    \\ ldi 91, %%r20 /* SYS_munmap */
                    \\ ble 0x100(%%sr2, %%r0)
                    \\ ldi 1, %%r20 /* SYS_exit */
                    \\ ldi 0, %%r26
                    \\ ble 0x100(%%sr2, %%r0)
                    :
                    : [ptr] "{r26}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r25}" (self.mapped.len),
                ),
                .m68k => asm volatile (
                    \\ move.l #91, %%d0 // SYS_munmap
                    \\ trap #0
                    \\ move.l #1, %%d0 // SYS_exit
                    \\ move.l #0, %%d1
                    \\ trap #0
                    :
                    : [ptr] "{d1}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{d2}" (self.mapped.len),
                ),
                .microblaze, .microblazeel => asm volatile (
                    \\ ori r12, r0, 91 # SYS_munmap
                    \\ brki r14, 0x8
                    \\ ori r12, r0, 1 # SYS_exit
                    \\ or r5, r0, r0
                    \\ brki r14, 0x8
                    :
                    : [ptr] "{r5}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r6}" (self.mapped.len),
                ),
                // We set `sp` to the address of the current function as a workaround for a Linux
                // kernel bug that caused syscalls to return EFAULT if the stack pointer is invalid.
                // The bug was introduced in 46e12c07b3b9603c60fc1d421ff18618241cb081 and fixed in
                // 7928eb0370d1133d0d8cd2f5ddfca19c309079d5.
                .mips, .mipsel => asm volatile (
                    \\ move $sp, $t9
                    \\ li $v0, 4091 # SYS_munmap
                    \\ syscall
                    \\ li $v0, 4001 # SYS_exit
                    \\ li $a0, 0
                    \\ syscall
                    :
                    : [ptr] "{$4}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{$5}" (self.mapped.len),
                ),
                .mips64, .mips64el => asm volatile (switch (target.abi) {
                        .gnuabin32, .muslabin32 =>
                        \\ li $v0, 6011 # SYS_munmap
                        \\ syscall
                        \\ li $v0, 6058 # SYS_exit
                        \\ li $a0, 0
                        \\ syscall
                        ,
                        else =>
                        \\ li $v0, 5011 # SYS_munmap
                        \\ syscall
                        \\ li $v0, 5058 # SYS_exit
                        \\ li $a0, 0
                        \\ syscall
                        ,
                    }
                    :
                    : [ptr] "{$4}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{$5}" (self.mapped.len),
                ),
                .or1k => asm volatile (
                    \\ l.ori r11, r0, 215 # SYS_munmap
                    \\ l.sys 1
                    \\ l.ori r11, r0, 93 # SYS_exit
                    \\ l.ori r3, r0, r0
                    \\ l.sys 1
                    :
                    : [ptr] "{r3}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r4}" (self.mapped.len),
                ),
                .powerpc, .powerpcle, .powerpc64, .powerpc64le => asm volatile (
                    \\  li 0, 91 # SYS_munmap
                    \\  sc
                    \\  li 0, 1 # SYS_exit
                    \\  li 3, 0
                    \\  sc
                    \\  blr
                    :
                    : [ptr] "{r3}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r4}" (self.mapped.len),
                ),
                .riscv32, .riscv64 => asm volatile (
                    \\  li a7, 215 # SYS_munmap
                    \\  ecall
                    \\  li a7, 93 # SYS_exit
                    \\  mv a0, zero
                    \\  ecall
                    :
                    : [ptr] "{a0}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{a1}" (self.mapped.len),
                ),
                .s390x => asm volatile (
                    \\  svc 91 # SYS_munmap
                    \\  lghi %%r2, 0
                    \\  svc 1 # SYS_exit
                    :
                    : [ptr] "{r2}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r3}" (self.mapped.len),
                ),
                .sh, .sheb => asm volatile (
                    \\ mov #91, r3 ! SYS_munmap
                    \\ trapa #31
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ mov #1, r3 ! SYS_exit
                    \\ mov #0, r4
                    \\ trapa #31
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    \\ or r0, r0
                    :
                    : [ptr] "{r4}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r5}" (self.mapped.len),
                ),
                .sparc => asm volatile (
                    \\ # See sparc64 comments below.
                    \\ 1:
                    \\  cmp %%fp, 0
                    \\  beq 2f
                    \\  nop
                    \\  ba 1b
                    \\  restore
                    \\ 2:
                    \\  mov %%g1, %%o0 // ptr
                    \\  mov %%g2, %%o1 // len
                    \\  mov 73, %%g1 // SYS_munmap
                    \\  t 0x3 # ST_FLUSH_WINDOWS
                    \\  t 0x10
                    \\  mov 1, %%g1 // SYS_exit
                    \\  mov 0, %%o0
                    \\  t 0x10
                    :
                    : [ptr] "{g1}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{g2}" (self.mapped.len),
                    : .{ .memory = true }),
                .sparc64 => asm volatile (
                    \\ # SPARCs really don't like it when active stack frames
                    \\ # is unmapped (it will result in a segfault), so we
                    \\ # force-deactivate it by running `restore` until
                    \\ # all frames are cleared.
                    \\ 1:
                    \\  cmp %%fp, 0
                    \\  beq 2f
                    \\  nop
                    \\  ba 1b
                    \\  restore
                    \\ 2:
                    \\  mov %%g1, %%o0 // ptr
                    \\  mov %%g2, %%o1 // len
                    \\  mov 73, %%g1 // SYS_munmap
                    \\  # Flush register window contents to prevent background
                    \\  # memory access before unmapping the stack.
                    \\  flushw
                    \\  t 0x6d
                    \\  mov 1, %%g1 // SYS_exit
                    \\  mov 0, %%o0
                    \\  t 0x6d
                    :
                    : [ptr] "{g1}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{g2}" (self.mapped.len),
                    : .{ .memory = true }),
                .loongarch32, .loongarch64 => asm volatile (
                    \\ ori     $a7, $zero, 215     # SYS_munmap
                    \\ syscall 0                   # call munmap
                    \\ ori     $a0, $zero, 0
                    \\ ori     $a7, $zero, 93      # SYS_exit
                    \\ syscall 0                   # call exit
                    :
                    : [ptr] "{r4}" (@intFromPtr(self.mapped.ptr)),
                      [len] "{r5}" (self.mapped.len),
                    : .{ .memory = true }),
                else => |cpu_arch| @compileError("Unsupported linux arch: " ++ @tagName(cpu_arch)),
            }
            unreachable;
        }
    };

    fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) !Impl {
        const page_size = std.heap.pageSize();
        const Args = @TypeOf(args);
        const Instance = struct {
            fn_args: Args,
            thread: ThreadCompletion,

            fn entryFn(raw_arg: usize) callconv(.c) u8 {
                const self = @as(*@This(), @ptrFromInt(raw_arg));
                defer switch (self.thread.completion.swap(.completed, .seq_cst)) {
                    .running => {},
                    .completed => unreachable,
                    .detached => self.thread.freeAndExit(),
                };
                return callFn(f, self.fn_args);
            }
        };

        var guard_offset: usize = undefined;
        var stack_offset: usize = undefined;
        var tls_offset: usize = undefined;
        var instance_offset: usize = undefined;

        const map_bytes = blk: {
            var bytes: usize = page_size;
            guard_offset = bytes;

            bytes += @max(page_size, config.stack_size);
            bytes = std.mem.alignForward(usize, bytes, page_size);
            stack_offset = bytes;

            bytes = std.mem.alignForward(usize, bytes, linux.tls.area_desc.alignment);
            tls_offset = bytes;
            bytes += linux.tls.area_desc.size;

            bytes = std.mem.alignForward(usize, bytes, @alignOf(Instance));
            instance_offset = bytes;
            bytes += @sizeOf(Instance);

            bytes = std.mem.alignForward(usize, bytes, page_size);
            break :blk bytes;
        };

        // map all memory needed without read/write permissions
        // to avoid committing the whole region right away
        // anonymous mapping ensures file descriptor limits are not exceeded
        const mapped = posix.mmap(
            null,
            map_bytes,
            .{},
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        ) catch |err| switch (err) {
            error.MemoryMappingNotSupported => unreachable,
            error.AccessDenied => unreachable,
            error.PermissionDenied => unreachable,
            error.ProcessFdQuotaExceeded => unreachable,
            error.SystemFdQuotaExceeded => unreachable,
            error.MappingAlreadyExists => unreachable,
            else => |e| return e,
        };
        assert(mapped.len >= map_bytes);
        errdefer posix.munmap(mapped);

        // Map everything but the guard page as read/write.
        const guarded: []align(std.heap.page_size_min) u8 = @alignCast(mapped[guard_offset..]);
        const protection: posix.PROT = .{ .READ = true, .WRITE = true };
        switch (posix.errno(posix.system.mprotect(guarded.ptr, guarded.len, protection))) {
            .SUCCESS => {},
            .NOMEM => return error.OutOfMemory,
            else => |err| return posix.unexpectedErrno(err),
        }

        // Prepare the TLS segment and prepare a user_desc struct when needed on x86
        var tls_ptr = linux.tls.prepareArea(mapped[tls_offset..][0..linux.tls.area_desc.size]);
        var user_desc: if (target.cpu.arch == .x86) linux.user_desc else void = undefined;
        if (target.cpu.arch == .x86) {
            defer tls_ptr = @intFromPtr(&user_desc);
            user_desc = .{
                .entry_number = linux.tls.area_desc.gdt_entry_number,
                .base_addr = tls_ptr,
                .limit = 0xfffff,
                .flags = .{
                    .seg_32bit = 1,
                    .contents = 0, // Data
                    .read_exec_only = 0,
                    .limit_in_pages = 1,
                    .seg_not_present = 0,
                    .useable = 1,
                },
            };
        }

        const instance: *Instance = @ptrCast(@alignCast(&mapped[instance_offset]));
        instance.* = .{
            .fn_args = args,
            .thread = .{ .mapped = mapped },
        };

        const flags: u32 = linux.CLONE.THREAD | linux.CLONE.DETACHED |
            linux.CLONE.VM | linux.CLONE.FS | linux.CLONE.FILES |
            linux.CLONE.PARENT_SETTID | linux.CLONE.CHILD_CLEARTID |
            linux.CLONE.SIGHAND | linux.CLONE.SYSVSEM | linux.CLONE.SETTLS;

        switch (linux.errno(linux.clone(
            Instance.entryFn,
            @intFromPtr(&mapped[stack_offset]),
            flags,
            @intFromPtr(instance),
            &instance.thread.parent_tid,
            tls_ptr,
            &instance.thread.child_tid.raw,
        ))) {
            .SUCCESS => return Impl{ .thread = &instance.thread },
            .AGAIN => return error.ThreadQuotaExceeded,
            .INVAL => unreachable,
            .NOMEM => return error.SystemResources,
            .NOSPC => unreachable,
            .PERM => unreachable,
            .USERS => unreachable,
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    fn getHandle(self: Impl) ThreadHandle {
        return self.thread.parent_tid;
    }

    fn detach(self: Impl) void {
        switch (self.thread.completion.swap(.detached, .seq_cst)) {
            .running => {},
            .completed => self.join(),
            .detached => unreachable,
        }
    }

    fn join(self: Impl) void {
        defer posix.munmap(self.thread.mapped);

        while (true) {
            const tid = self.thread.child_tid.load(.seq_cst);
            if (tid == 0) break;

            switch (linux.errno(linux.futex_4arg(
                &self.thread.child_tid.raw,
                .{ .cmd = .WAIT, .private = false },
                @bitCast(tid),
                null,
            ))) {
                .SUCCESS => continue,
                .INTR => continue,
                .AGAIN => continue,
                else => unreachable,
            }
        }
    }
};

fn testThreadName(io: Io, thread: *Thread) !void {
    const testCases = &[_][]const u8{
        "mythread",
        "b" ** max_name_len,
    };

    inline for (testCases) |tc| {
        try thread.setName(io, tc);

        var name_buffer: [max_name_len:0]u8 = undefined;

        const name = try thread.getName(&name_buffer);
        if (name) |value| {
            try std.testing.expectEqual(tc.len, value.len);
            try std.testing.expectEqualStrings(tc, value);
        }
    }
}

test "setName, getName" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = testing.io;

    const Context = struct {
        start_wait_event: Io.Event = .unset,
        test_done_event: Io.Event = .unset,
        thread_done_event: Io.Event = .unset,

        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        thread: Thread = undefined,

        pub fn run(ctx: *@This()) !void {
            // Wait for the main thread to have set the thread field in the context.
            try ctx.start_wait_event.wait(io);

            switch (native_os) {
                .windows => testThreadName(io, &ctx.thread) catch |err| switch (err) {
                    error.Unsupported => return error.SkipZigTest,
                    else => return err,
                },
                else => try testThreadName(io, &ctx.thread),
            }

            // Signal our test is done
            ctx.test_done_event.set(io);

            // wait for the thread to property exit
            try ctx.thread_done_event.wait(io);
        }
    };

    var context = Context{};
    var thread = try spawn(.{}, Context.run, .{&context});

    context.thread = thread;
    context.start_wait_event.set(io);
    try context.test_done_event.wait(io);

    switch (native_os) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
            const res = thread.setName(io, "foobar");
            try std.testing.expectError(error.Unsupported, res);
        },
        .windows => testThreadName(io, &thread) catch |err| switch (err) {
            error.Unsupported => return error.SkipZigTest,
            else => return err,
        },
        else => try testThreadName(io, &thread),
    }

    context.thread_done_event.set(io);
    thread.join();
}

fn testIncrementNotify(io: Io, value: *usize, event: *Io.Event) void {
    value.* += 1;
    event.set(io);
}

test join {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = testing.io;

    var value: usize = 0;
    var event: Io.Event = .unset;

    const thread = try Thread.spawn(.{}, testIncrementNotify, .{ io, &value, &event });
    thread.join();

    try std.testing.expectEqual(value, 1);
}

test detach {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = testing.io;

    var value: usize = 0;
    var event: Io.Event = .unset;

    const thread = try Thread.spawn(.{}, testIncrementNotify, .{ io, &value, &event });
    thread.detach();

    try event.wait(io);
    try std.testing.expectEqual(value, 1);
}

test "Thread.getCpuCount" {
    if (native_os == .wasi) return error.SkipZigTest;

    const cpu_count = try Thread.getCpuCount();
    try std.testing.expect(cpu_count >= 1);
}

fn testThreadIdFn(thread_id: *Thread.Id) void {
    thread_id.* = Thread.getCurrentId();
}

test "Thread.getCurrentId" {
    if (builtin.single_threaded) return error.SkipZigTest;

    var thread_current_id: Thread.Id = undefined;
    const thread = try Thread.spawn(.{}, testThreadIdFn, .{&thread_current_id});
    thread.join();
    try std.testing.expect(Thread.getCurrentId() != thread_current_id);
}

test "thread local storage" {
    if (builtin.single_threaded) return error.SkipZigTest;
    if (@sizeOf(usize) == 4) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/25498

    const thread1 = try Thread.spawn(.{}, testTls, .{});
    const thread2 = try Thread.spawn(.{}, testTls, .{});
    try testTls();
    thread1.join();
    thread2.join();
}

threadlocal var x: i32 = 1234;
fn testTls() !void {
    if (x != 1234) return error.TlsBadStartValue;
    x += 1;
    if (x != 1235) return error.TlsBadEndValue;
}

/// Configures the per-thread alternative signal stack requested by `std.options.signal_stack_size`.
pub fn maybeAttachSignalStack() void {
    const size = std.options.signal_stack_size orelse return;
    switch (builtin.target.os.tag) {
        // TODO: Windows vectored exception handlers always run on the main stack, but we could use
        // some target-specific inline assembly to swap the stack pointer.
        .windows => return,
        .wasi => return,
        else => {},
    }
    const global = struct {
        threadlocal var signal_stack: [size]u8 = undefined;
    };
    std.posix.sigaltstack(&.{
        .sp = &global.signal_stack,
        .flags = 0,
        .size = size,
    }, null) catch |err| switch (err) {
        error.SizeTooSmall => unreachable, // `std.options.signal_stack_size` must be sufficient for the target
        error.PermissionDenied => unreachable, // called `maybeAttachSignalStack` from a signal handler
        error.Unexpected => unreachable,
    };
}
