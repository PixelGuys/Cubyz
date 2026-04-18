const Threaded = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;
const is_windows = native_os == .windows;
const is_darwin = native_os.isDarwin();
const is_debug = builtin.mode == .Debug;

const std = @import("../std.zig");
const Io = std.Io;
const net = std.Io.net;
const File = std.Io.File;
const Dir = std.Io.Dir;
const HostName = net.HostName;
const IpAddress = net.IpAddress;
const process = std.process;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const assert = std.debug.assert;
const posix = std.posix;
const windows = std.os.windows;
const ws2_32 = windows.ws2_32;

/// Thread-safe.
///
/// Used for:
/// * allocating `Io.Future` and `Io.Group` closures.
/// * formatting spawning child processes
/// * scanning environment variables on some targets
/// * memory-mapping when mmap or equivalent is not available
allocator: Allocator,
mutex: Io.Mutex = .init,
cond: Io.Condition = .init,
run_queue: std.SinglyLinkedList = .{},
join_requested: bool = false,
stack_size: usize,
/// All threads are spawned detached; this is how we wait until they all exit.
wait_group: WaitGroup = .init,
async_limit: Io.Limit,
concurrent_limit: Io.Limit = .unlimited,
/// Error from calling `std.Thread.getCpuCount` in `init`.
cpu_count_error: ?std.Thread.CpuCountError,
/// Number of threads that are unavailable to take tasks. To calculate
/// available count, subtract this from either `async_limit` or
/// `concurrent_limit`.
busy_count: usize = 0,
worker_threads: std.atomic.Value(?*Thread),
pid: Pid = .unknown,

have_signal_handler: bool,
old_sig_io: if (have_sig_io) posix.Sigaction else void,
old_sig_pipe: if (have_sig_pipe) posix.Sigaction else void,

use_sendfile: UseSendfile = .default,
use_copy_file_range: UseCopyFileRange = .default,
use_fcopyfile: UseFcopyfile = .default,
use_fchmodat2: UseFchmodat2 = .default,
disable_memory_mapping: bool,

stderr_writer: File.Writer = .{
    .io = undefined,
    .interface = File.Writer.initInterface(&.{}),
    .file = if (is_windows) undefined else .stderr(),
    .mode = .streaming,
},
stderr_mode: Io.Terminal.Mode = .no_color,
stderr_writer_initialized: bool = false,
stderr_mutex: Io.Mutex = .init,
stderr_mutex_locker: std.Thread.Id = Thread.invalid_id,
stderr_mutex_lock_count: usize = 0,

argv0: Argv0,
/// Protected by `mutex`. Determines whether `environ` has been
/// memoized based on `process_environ`.
environ_initialized: bool,
environ: Environ,

dl: Dl = .init,

null_file: NullFile = .{},
random_file: RandomFile = .{},
pipe_file: PipeFile = .{},

csprng: Csprng = .uninitialized,

system_basic_information: SystemBasicInformation = .{},

const SystemBasicInformation = if (!is_windows) struct {} else struct {
    buffer: windows.SYSTEM.BASIC_INFORMATION = undefined,
    initialized: std.atomic.Value(bool) = .{ .raw = false },
};

const Dl = switch (native_os) {
    .windows => struct {
        iphlpapi_dll: std.atomic.Value(?*anyopaque),
        ConvertInterfaceNameToLuidW: std.atomic.Value(?*const fn (
            InterfaceName: [*:0]const windows.WCHAR,
            InterfaceLuid: *windows.NET.LUID,
        ) callconv(.winapi) windows.Win32Error),
        ConvertInterfaceLuidToIndex: std.atomic.Value(?*const fn (
            InterfaceLuid: *const windows.NET.LUID,
            InterfaceIndex: *windows.NET.IFINDEX,
        ) callconv(.winapi) windows.Win32Error),
        ConvertInterfaceIndexToLuid: std.atomic.Value(?*const fn (
            InterfaceIndex: std.os.windows.NET.IFINDEX,
            InterfaceLuid: *std.os.windows.NET.LUID,
        ) callconv(.winapi) windows.Win32Error),
        ConvertInterfaceLuidToNameW: std.atomic.Value(?*const fn (
            InterfaceLuid: *const std.os.windows.NET.LUID,
            InterfaceName: std.os.windows.PWSTR,
            Length: std.os.windows.SIZE_T,
        ) callconv(.winapi) std.os.windows.Win32Error),

        dnsapi_dll: std.atomic.Value(?*anyopaque),
        DnsQueryEx: std.atomic.Value(?*const fn (
            pQueryRequest: *const windows.DNS.QUERY.REQUEST,
            pQueryResults: *windows.DNS.QUERY.RESULT,
            pCancelHandle: ?*windows.DNS.QUERY.CANCEL,
        ) callconv(.winapi) windows.DNS.STATUS),
        //DnsCancelQuery: std.atomic.Value(?*const fn (
        //    pCancelHandle: *const windows.DNS.QUERY.CANCEL,
        //) callconv(.winapi) windows.DNS.STATUS),
        DnsFree: std.atomic.Value(?*const fn (
            pRecordList: ?*anyopaque,
            FreeType: windows.DNS.FREE_TYPE,
        ) callconv(.winapi) void),

        const init: Dl = .{
            .iphlpapi_dll = .init(null),
            .ConvertInterfaceNameToLuidW = .init(null),
            .ConvertInterfaceLuidToIndex = .init(null),
            .ConvertInterfaceIndexToLuid = .init(null),
            .ConvertInterfaceLuidToNameW = .init(null),

            .dnsapi_dll = .init(null),
            .DnsQueryEx = .init(null),
            //.DnsCancelQuery = .init(null),
            .DnsFree = .init(null),
        };
        fn deinit(dl: *Dl) void {
            if (dl.iphlpapi_dll.raw) |iphlpapi_dll| switch (windows.ntdll.LdrUnloadDll(iphlpapi_dll)) {
                .SUCCESS => {},
                else => |status| windows.unexpectedStatus(status) catch {},
            };
            dl.* = .init;
        }
    },
    else => struct {
        const init: Dl = .{};
        fn deinit(_: Dl) void {}
    },
};

pub const Csprng = struct {
    rng: std.Random.DefaultCsprng,

    pub const uninitialized: Csprng = .{ .rng = .{
        .state = undefined,
        .offset = std.math.maxInt(usize),
    } };

    pub const seed_len = std.Random.DefaultCsprng.secret_seed_length;

    pub fn isInitialized(c: *const Csprng) bool {
        return c.rng.offset != std.math.maxInt(usize);
    }
};

pub const Argv0 = switch (native_os) {
    .openbsd, .haiku => struct {
        value: ?[*:0]const u8,

        pub const empty: Argv0 = .{ .value = null };

        pub fn init(args: process.Args) Argv0 {
            return .{ .value = args.vector[0] };
        }
    },
    else => struct {
        pub const empty: Argv0 = .{};

        pub fn init(args: process.Args) Argv0 {
            _ = args;
            return .{};
        }
    },
};

pub const Environ = struct {
    /// Unmodified data directly from the OS.
    process_environ: process.Environ,
    /// Protected by `mutex`. Memoized based on `process_environ`. Tracks whether the
    /// environment variables are present, ignoring their value.
    exist: Exist = .{},
    /// Protected by `mutex`. Memoized based on `process_environ`.
    string: String = .{},
    /// ZIG_PROGRESS
    zig_progress_file: std.Progress.ParentFileError!File = error.EnvironmentVariableMissing,
    /// Protected by `mutex`. Tracks the problem, if any, that occurred when
    /// trying to scan environment variables.
    ///
    /// Errors are only possible on WASI.
    err: ?Error = null,

    pub const empty: Environ = .{ .process_environ = .empty };

    pub const Error = Allocator.Error || Io.UnexpectedError;

    pub const Exist = struct {
        NO_COLOR: bool = false,
        CLICOLOR_FORCE: bool = false,
    };

    pub const String = switch (native_os) {
        .windows, .wasi => struct {},
        else => struct {
            PATH: ?[:0]const u8 = null,
            DEBUGINFOD_CACHE_PATH: ?[:0]const u8 = null,
            XDG_CACHE_HOME: ?[:0]const u8 = null,
            HOME: ?[:0]const u8 = null,
        },
    };

    pub fn scan(environ: *Environ, allocator: Allocator) void {
        if (is_windows) {
            // This value expires with any call that modifies the environment,
            // which is outside of this Io implementation's control, so references
            // must be short-lived.
            const peb = windows.peb();
            assert(windows.ntdll.RtlEnterCriticalSection(peb.FastPebLock) == .SUCCESS);
            defer assert(windows.ntdll.RtlLeaveCriticalSection(peb.FastPebLock) == .SUCCESS);
            const ptr = peb.ProcessParameters.Environment;

            var i: usize = 0;
            while (ptr[i] != 0) {
                // There are some special environment variables that start with =,
                // so we need a special case to not treat = as a key/value separator
                // if it's the first character.
                // https://devblogs.microsoft.com/oldnewthing/20100506-00/?p=14133
                const key_start = i;
                if (ptr[i] == '=') i += 1;
                while (ptr[i] != 0 and ptr[i] != '=') : (i += 1) {}
                const key_w = ptr[key_start..i];

                const value_start = i + 1;
                while (ptr[i] != 0) : (i += 1) {} // skip over '=' and value
                const value_w = ptr[value_start..i];
                i += 1; // skip over null byte

                if (windows.eqlIgnoreCaseWtf16(key_w, &.{ 'N', 'O', '_', 'C', 'O', 'L', 'O', 'R' })) {
                    environ.exist.NO_COLOR = true;
                } else if (windows.eqlIgnoreCaseWtf16(key_w, &.{ 'C', 'L', 'I', 'C', 'O', 'L', 'O', 'R', '_', 'F', 'O', 'R', 'C', 'E' })) {
                    environ.exist.CLICOLOR_FORCE = true;
                } else if (windows.eqlIgnoreCaseWtf16(key_w, &.{ 'Z', 'I', 'G', '_', 'P', 'R', 'O', 'G', 'R', 'E', 'S', 'S' })) {
                    environ.zig_progress_file = file: {
                        var value_buf: [std.fmt.count("{d}", .{std.math.maxInt(usize)})]u8 = undefined;
                        const len = std.unicode.calcWtf8Len(value_w);
                        if (len > value_buf.len) break :file error.UnrecognizedFormat;
                        assert(std.unicode.wtf16LeToWtf8(&value_buf, value_w) == len);
                        break :file .{
                            .handle = @ptrFromInt(std.fmt.parseInt(usize, value_buf[0..len], 10) catch
                                break :file error.UnrecognizedFormat),
                            .flags = .{ .nonblocking = true },
                        };
                    };
                }
                comptime assert(@sizeOf(String) == 0);
            }
        } else if (native_os == .wasi and !builtin.link_libc) {
            var environ_size: usize = undefined;
            var environ_buf_size: usize = undefined;

            switch (std.os.wasi.environ_sizes_get(&environ_size, &environ_buf_size)) {
                .SUCCESS => {},
                else => |err| {
                    environ.err = posix.unexpectedErrno(err);
                    return;
                },
            }
            if (environ_size == 0) return;

            const wasi_environ = allocator.alloc([*:0]u8, environ_size) catch |err| {
                environ.err = err;
                return;
            };
            defer allocator.free(wasi_environ);
            const wasi_environ_buf = allocator.alloc(u8, environ_buf_size) catch |err| {
                environ.err = err;
                return;
            };
            defer allocator.free(wasi_environ_buf);

            switch (std.os.wasi.environ_get(wasi_environ.ptr, wasi_environ_buf.ptr)) {
                .SUCCESS => {},
                else => |err| {
                    environ.err = posix.unexpectedErrno(err);
                    return;
                },
            }

            for (wasi_environ) |env| {
                const pair = std.mem.sliceTo(env, 0);
                var parts = std.mem.splitScalar(u8, pair, '=');
                const key = parts.first();
                if (std.mem.eql(u8, key, "NO_COLOR")) {
                    environ.exist.NO_COLOR = true;
                } else if (std.mem.eql(u8, key, "CLICOLOR_FORCE")) {
                    environ.exist.CLICOLOR_FORCE = true;
                }
                comptime assert(@sizeOf(String) == 0);
            }
        } else {
            for (environ.process_environ.block.slice) |opt_entry| {
                const entry = opt_entry.?;
                var entry_i: usize = 0;
                while (entry[entry_i] != 0 and entry[entry_i] != '=') : (entry_i += 1) {}
                const key = entry[0..entry_i];

                var end_i: usize = entry_i;
                while (entry[end_i] != 0) : (end_i += 1) {}
                const value = entry[entry_i + 1 .. end_i :0];

                if (std.mem.eql(u8, key, "NO_COLOR")) {
                    environ.exist.NO_COLOR = true;
                } else if (std.mem.eql(u8, key, "CLICOLOR_FORCE")) {
                    environ.exist.CLICOLOR_FORCE = true;
                } else if (std.mem.eql(u8, key, "ZIG_PROGRESS")) {
                    environ.zig_progress_file = file: {
                        break :file .{
                            .handle = std.fmt.parseInt(u31, value, 10) catch
                                break :file error.UnrecognizedFormat,
                            .flags = .{ .nonblocking = true },
                        };
                    };
                } else inline for (@typeInfo(String).@"struct".fields) |field| {
                    if (std.mem.eql(u8, key, field.name)) @field(environ.string, field.name) = value;
                }
            }
        }
    }
};

pub const NullFile = switch (native_os) {
    .windows => struct {
        handle: ?windows.HANDLE = null,

        fn deinit(this: *@This()) void {
            if (this.handle) |handle| {
                windows.CloseHandle(handle);
                this.handle = null;
            }
        }
    },
    .wasi, .ios, .tvos, .visionos, .watchos => struct {
        fn deinit(this: @This()) void {
            _ = this;
        }
    },
    else => struct {
        fd: posix.fd_t = -1,

        fn deinit(this: *@This()) void {
            if (this.fd >= 0) {
                closeFd(this.fd);
                this.fd = -1;
            }
        }
    },
};

pub const RandomFile = switch (native_os) {
    .windows => NullFile,
    else => if (use_dev_urandom) NullFile else struct {
        fn deinit(this: @This()) void {
            _ = this;
        }
    },
};

pub const PipeFile = switch (native_os) {
    .windows => struct {
        handle: ?windows.HANDLE = null,

        fn deinit(this: *@This()) void {
            if (this.handle) |handle| {
                windows.CloseHandle(handle);
                this.handle = null;
            }
        }
    },
    else => struct {
        fn deinit(this: @This()) void {
            _ = this;
        }
    },
};

pub const Pid = if (native_os == .linux) enum(posix.pid_t) {
    unknown = 0,
    _,
} else enum(u0) { unknown = 0 };

pub const UseSendfile = if (have_sendfile) enum {
    enabled,
    disabled,
    pub const default: UseSendfile = .enabled;
} else enum {
    disabled,
    pub const default: UseSendfile = .disabled;
};

pub const UseCopyFileRange = if (have_copy_file_range) enum {
    enabled,
    disabled,
    pub const default: UseCopyFileRange = .enabled;
} else enum {
    disabled,
    pub const default: UseCopyFileRange = .disabled;
};

pub const UseFcopyfile = if (have_fcopyfile) enum {
    enabled,
    disabled,
    pub const default: UseFcopyfile = .enabled;
} else enum {
    disabled,
    pub const default: UseFcopyfile = .disabled;
};

pub const UseFchmodat2 = if (have_fchmodat2 and !have_fchmodat_flags) enum {
    enabled,
    disabled,
    pub const default: UseFchmodat2 = .enabled;
} else enum {
    disabled,
    pub const default: UseFchmodat2 = .disabled;
};

pub const apc_align = @max(default_fn_align, 2);

const default_fn_align = switch (builtin.mode) {
    .Debug, .ReleaseSafe, .ReleaseFast => switch (builtin.cpu.arch) {
        else => |arch| @compileError("Unsupported architecture: " ++ @tagName(arch)),
        .arm, .thumb => 4,
        .aarch64, .x86, .x86_64 => 16,
    },
    .ReleaseSmall => 1,
};

const Runnable = struct {
    node: std.SinglyLinkedList.Node,
    startFn: *const fn (*Runnable, *Thread, *Threaded) void,
};

const Group = struct {
    ptr: *Io.Group,

    /// Returns a correctly-typed pointer to the `Io.Group.token` field.
    ///
    /// The status indicates how many pending tasks are in the group, whether the group has been
    /// canceled, and whether the group has been awaited.
    ///
    /// Note that the zero value of `Status` intentionally represents the initial group state (empty
    /// with no awaiters). This is a requirement of `Io.Group`.
    fn status(g: Group) *std.atomic.Value(Status) {
        return @ptrCast(&g.ptr.token);
    }
    /// Returns a correctly-typed pointer to the `Io.Group.state` field. The double-pointer here is
    /// intentional, because the `state` field itself stores a pointer, and this function returns a
    /// pointer to that field.
    ///
    /// On completion of the whole group, if `status` indicates that there is an awaiter, the last
    /// task must increment this `u32` and do a futex wake on it to signal that awaiter.
    fn awaiter(g: Group) **std.atomic.Value(u32) {
        return @ptrCast(&g.ptr.state);
    }

    const Status = packed struct(usize) {
        num_running: @Int(.unsigned, @bitSizeOf(usize) - 2),
        have_awaiter: bool,
        canceled: bool,
    };

    const Task = struct {
        runnable: Runnable,
        group: *Io.Group,
        func: *const fn (context: *const anyopaque) void,
        context_alignment: Alignment,
        alloc_len: usize,

        /// `Task.runnable.node` is `undefined` in the created `Task`.
        fn create(
            gpa: Allocator,
            group: Group,
            context: []const u8,
            context_alignment: Alignment,
            func: *const fn (context: *const anyopaque) void,
        ) Allocator.Error!*Task {
            const max_context_misalignment = context_alignment.toByteUnits() -| @alignOf(Task);
            const worst_case_context_offset = context_alignment.forward(@sizeOf(Task) + max_context_misalignment);
            const alloc_len = worst_case_context_offset + context.len;

            const task: *Task = @ptrCast(@alignCast(try gpa.alignedAlloc(u8, .of(Task), alloc_len)));
            errdefer comptime unreachable;

            task.* = .{
                .runnable = .{
                    .node = undefined,
                    .startFn = &start,
                },
                .group = group.ptr,
                .func = func,
                .context_alignment = context_alignment,
                .alloc_len = alloc_len,
            };
            @memcpy(task.contextPointer()[0..context.len], context);
            return task;
        }

        fn destroy(task: *Task, gpa: Allocator) void {
            const base: [*]align(@alignOf(Task)) u8 = @ptrCast(task);
            gpa.free(base[0..task.alloc_len]);
        }

        fn contextPointer(task: *Task) [*]u8 {
            const base: [*]u8 = @ptrCast(task);
            const offset = task.context_alignment.forward(@intFromPtr(base) + @sizeOf(Task)) - @intFromPtr(base);
            return base + offset;
        }

        fn start(r: *Runnable, thread: *Thread, t: *Threaded) void {
            const task: *Task = @fieldParentPtr("runnable", r);
            const group: Group = .{ .ptr = task.group };

            // This would be a simple store, but it's upgraded to an RMW so we can use `.acquire` to
            // enforce the ordering between this and the `group.status().load` below. Paired with
            // the `.release` rmw on `Thread.status` in `cancelThreads`, this creates a StoreLoad
            // barrier which guarantees that when a group is canceled, either we see the cancelation
            // in the group status, or the canceler sees our thread status so can directly notify us
            // of the cancelation.
            _ = thread.status.swap(.{
                .cancelation = .none,
                .awaitable = .fromGroup(group.ptr),
            }, .acquire);
            if (group.status().load(.monotonic).canceled) {
                thread.status.store(.{
                    .cancelation = .canceling,
                    .awaitable = .fromGroup(group.ptr),
                }, .monotonic);
            }

            task.func(task.contextPointer());

            thread.status.store(.{ .cancelation = .none, .awaitable = .null }, .monotonic);
            const old_status = group.status().fetchSub(.{
                .num_running = 1,
                .have_awaiter = false,
                .canceled = false,
            }, .acq_rel); // acquire `group.awaiter()`, release task results
            assert(old_status.num_running > 0);
            if (old_status.have_awaiter and old_status.num_running == 1) {
                const to_signal = group.awaiter().*;
                // `awaiter` should only be modified by us. For another thread to see `num_running`
                // drop to 0 after this point would indicate that another task started up, meaning
                // `async`/`cancel` was racing with awaited group completion.
                group.awaiter().* = undefined;
                _ = to_signal.fetchAdd(1, .release); // release results
                Thread.futexWake(&to_signal.raw, 1);
            }

            // Task completed. Self-destruct sequence initiated.
            task.destroy(t.allocator);
        }
    };

    /// Assumes the caller has already atomically updated the group status to indicate cancelation,
    /// and notifies any already-running threads of this cancelation.
    fn cancelThreads(g: Group, t: *Threaded) bool {
        var any_blocked = false;
        var it = t.worker_threads.load(.acquire); // acquire `Thread` values
        while (it) |thread| : (it = thread.next) {
            // This non-mutating RMW exists for ordering reasons: see comment in `Group.Task.start` for reasons.
            _ = thread.status.fetchOr(.{ .cancelation = @enumFromInt(0), .awaitable = .null }, .release);
            if (thread.cancelAwaitable(.fromGroup(g.ptr))) any_blocked = true;
        }
        return any_blocked;
    }

    /// Uses `Thread.signalCanceledSyscall` to signal any threads which are still blocked in a
    /// syscall for this group and have not observed a cancelation request yet. Returns `true` if
    /// more signals may be necessary, in which case the caller must call this again after a delay.
    fn signalAllCanceledSyscalls(g: Group, t: *Threaded) bool {
        var any_signaled = false;
        var it = t.worker_threads.load(.acquire); // acquire `Thread` values
        while (it) |thread| : (it = thread.next) {
            if (thread.signalCanceledSyscall(t, .fromGroup(g.ptr))) any_signaled = true;
        }
        return any_signaled;
    }

    /// The caller has canceled `g`. Inform any threads working on that group of the cancelation if
    /// necessary, and wait for `g` to finish (indicated by `num_completed` being incremented from 0
    /// to 1), while sending regular signals to threads if necessary for them to unblock from any
    /// cancelable syscalls.
    ///
    /// `skip_signals` means it is already known that no threads are currently working on the group
    /// so no notifications or signals are necessary.
    fn waitForCancelWithSignaling(
        g: Group,
        t: *Threaded,
        num_completed: *std.atomic.Value(u32),
        skip_signals: bool,
    ) void {
        var need_signal: bool = !skip_signals and g.cancelThreads(t);
        var timeout_ns: u64 = 1 << 10;
        while (true) {
            need_signal = need_signal and g.signalAllCanceledSyscalls(t);
            Thread.futexWaitUncancelable(&num_completed.raw, 0, if (need_signal) timeout_ns else null);
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => {},
                1 => break,
                else => unreachable,
            }
            timeout_ns <<|= 1;
        }
    }
};

/// Trailing data:
/// 1. context
/// 2. result
const Future = struct {
    runnable: Runnable,
    func: *const fn (context: *const anyopaque, result: *anyopaque) void,
    status: std.atomic.Value(Status),
    /// On completion, increment this `u32` and do a futex wake on it.
    awaiter: *std.atomic.Value(u32),
    context_alignment: Alignment,
    result_offset: usize,
    alloc_len: usize,

    const Status = packed struct(usize) {
        /// The values of this enum are chosen so that await/cancel can just OR with 0b01 and 0b11
        /// respectively. That *does* clobber `.done`, but that's actually fine, because if the tag
        /// is `.done` then only the awaiter is referencing this `Future` anyway.
        tag: enum(u2) {
            /// The future is queued or running (depending on whether `thread` is set).
            pending = 0b00,
            /// Like `pending`, but the future is being awaited. `Future.awaiter` is populated.
            pending_awaited = 0b01,
            /// Like `pending`, but the future is being canceled. `Future.awaiter` is populated.
            pending_canceled = 0b11,
            /// The future has already completed. `thread` is `.null`, unless the future terminated
            /// with an acknowledged cancel request, in which case `thread` is `.all_ones`.
            done = 0b10,
        },
        /// When the future begins execution, this is atomically updated from `null` to the thread running the
        /// `Future`, so that cancelation knows which thread to cancel.
        thread: Thread.PackedPtr,
    };

    /// `Future.runnable.node` is `undefined` in the created `Future`.
    fn create(
        gpa: Allocator,
        result_len: usize,
        result_alignment: Alignment,
        context: []const u8,
        context_alignment: Alignment,
        func: *const fn (context: *const anyopaque, result: *anyopaque) void,
    ) Allocator.Error!*Future {
        const max_context_misalignment = context_alignment.toByteUnits() -| @alignOf(Future);
        const worst_case_context_offset = context_alignment.forward(@sizeOf(Future) + max_context_misalignment);
        const worst_case_result_offset = result_alignment.forward(worst_case_context_offset + context.len);
        const alloc_len = worst_case_result_offset + result_len;

        const future: *Future = @ptrCast(@alignCast(try gpa.alignedAlloc(u8, .of(Future), alloc_len)));
        errdefer comptime unreachable;

        const actual_context_addr = context_alignment.forward(@intFromPtr(future) + @sizeOf(Future));
        const actual_result_addr = result_alignment.forward(actual_context_addr + context.len);
        const actual_result_offset = actual_result_addr - @intFromPtr(future);
        future.* = .{
            .runnable = .{
                .node = undefined,
                .startFn = &start,
            },
            .func = func,
            .status = .init(.{
                .tag = .pending,
                .thread = .null,
            }),
            .awaiter = undefined,
            .context_alignment = context_alignment,
            .result_offset = actual_result_offset,
            .alloc_len = alloc_len,
        };
        @memcpy(future.contextPointer()[0..context.len], context);
        return future;
    }

    fn destroy(future: *Future, gpa: Allocator) void {
        const base: [*]align(@alignOf(Future)) u8 = @ptrCast(future);
        gpa.free(base[0..future.alloc_len]);
    }

    fn resultPointer(future: *Future) [*]u8 {
        const base: [*]u8 = @ptrCast(future);
        return base + future.result_offset;
    }

    fn contextPointer(future: *Future) [*]u8 {
        const base: [*]u8 = @ptrCast(future);
        const context_offset = future.context_alignment.forward(@intFromPtr(future) + @sizeOf(Future)) - @intFromPtr(future);
        return base + context_offset;
    }

    fn start(r: *Runnable, thread: *Thread, t: *Threaded) void {
        _ = t;
        const future: *Future = @fieldParentPtr("runnable", r);

        thread.status.store(.{
            .cancelation = .none,
            .awaitable = .fromFuture(future),
        }, .monotonic);
        {
            const old_status = future.status.fetchOr(.{
                .tag = .pending,
                .thread = .pack(thread),
            }, .release);
            assert(old_status.thread == .null);
            switch (old_status.tag) {
                .pending, .pending_awaited => {},
                .pending_canceled => thread.status.store(.{
                    .cancelation = .canceling,
                    .awaitable = .fromFuture(future),
                }, .monotonic),
                .done => unreachable,
            }
        }

        future.func(future.contextPointer(), future.resultPointer());

        const had_acknowledged_cancel = switch (thread.status.load(.monotonic).cancelation) {
            .none, .canceling => false,
            .canceled => true,
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
        };
        thread.status.store(.{ .cancelation = .none, .awaitable = .null }, .monotonic);
        const old_status = future.status.swap(.{
            .tag = .done,
            .thread = if (had_acknowledged_cancel) .all_ones else .null,
        }, .acq_rel); // acquire `future.awaiter`, release results
        switch (old_status.tag) {
            .pending => {},
            .pending_awaited, .pending_canceled => {
                const to_signal = future.awaiter;
                _ = to_signal.fetchAdd(1, .release); // release results
                Thread.futexWake(&to_signal.raw, 1);
            },
            .done => unreachable,
        }
    }

    /// The caller has canceled `future`. `thread` is the thread currently running that future.
    /// Inform `thread` of the cancelation if necessary, and wait for `future` to finish (indicated
    /// by `num_completed` being incremented from 0 to 1), while sending regular signals to `thread`
    /// if necessary for it to unblock from a cancelable syscall.
    fn waitForCancelWithSignaling(
        future: *Future,
        t: *Threaded,
        num_completed: *std.atomic.Value(u32),
        thread: ?*Thread,
    ) void {
        var need_signal: bool = if (thread) |th| th.cancelAwaitable(.fromFuture(future)) else false;
        var timeout_ns: u64 = 1 << 10;
        while (true) {
            need_signal = need_signal and thread.?.signalCanceledSyscall(t, .fromFuture(future));
            Thread.futexWaitUncancelable(&num_completed.raw, 0, if (need_signal) timeout_ns else null);
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => {},
                1 => break,
                else => unreachable,
            }
            timeout_ns <<|= 1;
        }
    }
};

/// A sequence of (ptr_bit_width - 3) bits which uniquely identifies a group or future. The bits are
/// the MSBs of the `*Io.Group` or `*Future`. These things do not necessarily have 3 zero bits at
/// the end (they are pointer-aligned, so on 32-bit targets only have 2), but because they both have
/// a *size* of at least 8 bytes, no two groups/futures in memory at the same time will have the
/// same value for all of these bits. In other words, given a group/future pointer, the next group
/// or future must be at least 8 bytes later, so its address will have a different value for one of
/// the top (ptr_bit_width - 3) bits.
const AwaitableId = enum(@Int(.unsigned, @bitSizeOf(usize) - 3)) {
    comptime {
        assert(@sizeOf(Future) >= 8);
        assert(@sizeOf(Io.Group) >= 8);
    }
    null = 0,
    all_ones = std.math.maxInt(@Int(.unsigned, @bitSizeOf(usize) - 3)),
    _,
    const Split = packed struct(usize) { low: u3, high: AwaitableId };
    fn fromGroup(g: *Io.Group) AwaitableId {
        const split: Split = @bitCast(@intFromPtr(g));
        return split.high;
    }
    fn fromFuture(f: *Future) AwaitableId {
        const split: Split = @bitCast(@intFromPtr(f));
        return split.high;
    }
};

const Thread = struct {
    next: ?*Thread,

    id: std.Thread.Id,
    handle: Handle,

    status: std.atomic.Value(Status),

    cancel_protection: Io.CancelProtection,
    /// Always released when `Status.cancelation` is set to `.parked`.
    futex_waiter: if (use_parking_futex) ?*parking_futex.Waiter else ?noreturn,
    unpark_flag: UnparkFlag,

    csprng: Csprng,

    const Handle = Handle: {
        if (std.Thread.use_pthreads) break :Handle std.c.pthread_t;
        if (is_windows) break :Handle windows.HANDLE;
        break :Handle void;
    };

    const Status = packed struct(usize) {
        /// The specific values of these enum fields are chosen to simplify the implementation of
        /// the transformations we need to apply to this state.
        cancelation: enum(u3) {
            /// The thread has not yet been canceled, and is not in a cancelable operation.
            /// To request cancelation, just set the status to `.canceling`.
            none = 0b000,

            /// The thread is parked in a cancelable futex wait or sleep.
            /// Only applicable if `use_parking_futex` or `use_parking_sleep`.
            /// To request cancelation, set the status to `.canceling` and unpark the thread.
            /// To unpark for another reason (futex wake), set the status to `.none` and unpark the thread.
            parked = 0b001,

            /// The thread is blocked in a cancelable system call.
            /// To request cancelation, set the status to `.blocked_canceling` and repeatedly interrupt the system call until the status changes.
            blocked = 0b011,

            /// Windows-only: the thread is blocked in an alertable wait via
            /// `NtDelayExecution`. To request cancelation, set the status to
            /// `blocked_alertable_canceling` and repeatedly alert the thread
            /// until the status changes.
            blocked_alertable = 0b010,

            /// The thread has an outstanding cancelation request but is not in a cancelable operation.
            /// When it acknowledges the cancelation, it will set the status to `.canceled`.
            canceling = 0b110,

            /// The thread has received and acknowledged a cancelation request.
            /// If `recancel` is called, the status will revert to `.canceling`, but otherwise, the status
            /// will not change for the remainder of this task's execution.
            canceled = 0b111,

            /// The thread is blocked in a cancelable system call, and is being
            /// canceled. The thread which triggered the cancelation will send
            /// signals to this thread until its status changes.
            blocked_canceling = 0b101,

            /// Windows-only: the thread is blocked in an alertable wait via
            /// `NtDelayExecution`, and is being canceled. The thread which
            /// triggered the cancelation will send signals to this thread
            /// until its status changes.
            blocked_alertable_canceling = 0b100,
        },

        /// We cannot turn this value back into a pointer. Instead, it exists so that a task can be
        /// canceled by a cmpxchg on thread status: if it is running the task we want to cancel,
        /// then update the `cancelation` field.
        awaitable: AwaitableId,
    };

    const SignaleeId = if (std.Thread.use_pthreads) std.c.pthread_t else std.Thread.Id;

    threadlocal var current: ?*Thread = null;

    /// A value that does not alias any other thread id.
    const invalid_id: std.Thread.Id = std.math.maxInt(std.Thread.Id);

    fn currentId() std.Thread.Id {
        return if (current) |t| t.id else std.Thread.getCurrentId();
    }

    /// The thread is neither in a syscall nor entering one, but we want to check for cancelation
    /// anyway. If there is a pending cancel request, acknowledge it and return `error.Canceled`.
    fn checkCancel() Io.Cancelable!void {
        const thread = Thread.current orelse return;
        switch (thread.cancel_protection) {
            .blocked => return,
            .unblocked => {},
        }
        // Here, unlike `Syscall.checkCancel`, it's not particularly likely that we're canceled, so
        // it seems preferable to do a cheap atomic load and, in the unlikely case, a separate store
        // to acknowledge. Besides, the state transitions we need here can't be done with one atomic
        // OR/AND/XOR on `Status.cancelation`, so we don't actually have any other option.
        const status = thread.status.load(.monotonic);
        switch (status.cancelation) {
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
            .none, .canceled => {},
            .canceling => {
                thread.status.store(.{
                    .cancelation = .canceled,
                    .awaitable = status.awaitable,
                }, .monotonic);
                return error.Canceled;
            },
        }
    }

    fn futexWaitUncancelable(ptr: *const u32, expect: u32, timeout_ns: ?u64) void {
        return Thread.futexWaitInner(ptr, expect, true, timeout_ns) catch unreachable;
    }

    fn futexWait(ptr: *const u32, expect: u32, timeout_ns: ?u64) Io.Cancelable!void {
        return Thread.futexWaitInner(ptr, expect, false, timeout_ns);
    }

    fn futexWaitInner(ptr: *const u32, expect: u32, uncancelable: bool, timeout_ns: ?u64) Io.Cancelable!void {
        @branchHint(.cold);

        if (builtin.single_threaded) unreachable; // nobody would ever wake us

        if (use_parking_futex) {
            return parking_futex.wait(
                ptr,
                expect,
                uncancelable,
                if (timeout_ns) |ns| .{ .duration = .{
                    .raw = .fromNanoseconds(ns),
                    .clock = .boot,
                } } else .none,
            );
        } else if (builtin.cpu.arch.isWasm()) {
            comptime assert(builtin.cpu.has(.wasm, .atomics));
            // TODO implement cancelation for WASM futex waits by signaling the futex
            if (!uncancelable) try Thread.checkCancel();
            const to: i64 = if (timeout_ns) |ns| ns else -1;
            const signed_expect: i32 = @bitCast(expect);
            const result = asm volatile (
                \\local.get %[ptr]
                \\local.get %[expected]
                \\local.get %[timeout]
                \\memory.atomic.wait32 0
                \\local.set %[ret]
                : [ret] "=r" (-> u32),
                : [ptr] "r" (ptr),
                  [expected] "r" (signed_expect),
                  [timeout] "r" (to),
            );
            switch (result) {
                0 => {}, // ok
                1 => {}, // expected != loaded
                2 => {}, // timeout
                else => assert(!is_debug),
            }
        } else switch (native_os) {
            .linux => {
                const linux = std.os.linux;
                var ts_buffer: linux.timespec = undefined;
                const ts: ?*linux.timespec = if (timeout_ns) |ns| ts: {
                    ts_buffer = timestampToPosix(ns);
                    break :ts &ts_buffer;
                } else null;
                const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
                const rc = linux.futex_4arg(ptr, .{ .cmd = .WAIT, .private = true }, expect, ts);
                syscall.finish();
                switch (linux.errno(rc)) {
                    .SUCCESS => {}, // notified by `wake()`
                    .INTR => {}, // caller's responsibility to retry
                    .AGAIN => {}, // ptr.* != expect
                    .INVAL => {}, // possibly timeout overflow
                    .TIMEDOUT => {},
                    .FAULT => recoverableOsBugDetected(), // ptr was invalid
                    else => recoverableOsBugDetected(),
                }
            },
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
                const c = std.c;
                const flags: c.UL = .{
                    .op = .COMPARE_AND_WAIT,
                    .NO_ERRNO = true,
                };
                const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
                const status = switch (darwin_supports_ulock_wait2) {
                    true => c.__ulock_wait2(flags, ptr, expect, ns: {
                        const ns = timeout_ns orelse break :ns 0;
                        if (ns == 0) break :ns 1;
                        break :ns ns;
                    }, 0),
                    false => c.__ulock_wait(flags, ptr, expect, us: {
                        const ns = timeout_ns orelse break :us 0;
                        const us = std.math.lossyCast(u32, ns / std.time.ns_per_us);
                        if (us == 0) break :us 1;
                        break :us us;
                    }),
                };
                syscall.finish();
                if (status >= 0) return;
                switch (@as(c.E, @enumFromInt(-status))) {
                    .INTR => {}, // spurious wake
                    // Address of the futex was paged out. This is unlikely, but possible in theory, and
                    // pthread/libdispatch on darwin bother to handle it. In this case we'll return
                    // without waiting, but the caller should retry anyway.
                    .FAULT => {},
                    .TIMEDOUT => {}, // timeout
                    else => recoverableOsBugDetected(),
                }
            },
            .freebsd => {
                const flags = @intFromEnum(std.c.UMTX_OP.WAIT_UINT_PRIVATE);
                var tm_size: usize = 0;
                var tm: std.c._umtx_time = undefined;
                var tm_ptr: ?*const std.c._umtx_time = null;
                if (timeout_ns) |ns| {
                    tm_ptr = &tm;
                    tm_size = @sizeOf(@TypeOf(tm));
                    tm.flags = 0; // use relative time not UMTX_ABSTIME
                    tm.clockid = .MONOTONIC;
                    tm.timeout = timestampToPosix(ns);
                }
                const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
                const rc = std.c._umtx_op(@intFromPtr(ptr), flags, @as(c_ulong, expect), tm_size, @intFromPtr(tm_ptr));
                syscall.finish();
                if (is_debug) switch (posix.errno(rc)) {
                    .SUCCESS => {},
                    .FAULT => unreachable, // one of the args points to invalid memory
                    .INVAL => unreachable, // arguments should be correct
                    .TIMEDOUT => {}, // timeout
                    .INTR => {}, // spurious wake
                    else => unreachable,
                };
            },
            .openbsd => {
                var tm: std.c.timespec = undefined;
                var tm_ptr: ?*const std.c.timespec = null;
                if (timeout_ns) |ns| {
                    tm_ptr = &tm;
                    tm = timestampToPosix(ns);
                }
                const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
                const rc = std.c.futex(
                    ptr,
                    std.c.FUTEX.WAIT | std.c.FUTEX.PRIVATE_FLAG,
                    @as(c_int, @bitCast(expect)),
                    tm_ptr,
                    null, // uaddr2 is ignored
                );
                syscall.finish();
                if (is_debug) switch (posix.errno(rc)) {
                    .SUCCESS => {},
                    .NOSYS => unreachable, // constant op known good value
                    .AGAIN => {}, // contents of uaddr != val
                    .INVAL => unreachable, // invalid timeout
                    .TIMEDOUT => {}, // timeout
                    .INTR => {}, // a signal arrived
                    .CANCELED => {}, // a signal arrived and SA_RESTART was set
                    else => unreachable,
                };
            },
            .dragonfly => {
                var timeout_us: c_int = undefined;
                if (timeout_ns) |ns| {
                    timeout_us = std.math.cast(c_int, ns / std.time.ns_per_us) orelse std.math.maxInt(c_int);
                } else {
                    timeout_us = 0;
                }
                const syscall: Syscall = if (uncancelable) .{ .thread = null } else try .start();
                const rc = std.c.umtx_sleep(@ptrCast(ptr), @bitCast(expect), timeout_us);
                syscall.finish();
                if (is_debug) switch (std.posix.errno(rc)) {
                    .SUCCESS => {},
                    .BUSY => {}, // ptr != expect
                    .AGAIN => {}, // maybe timed out, or paged out, or hit 2s kernel refresh
                    .INTR => {}, // spurious wake
                    .INVAL => unreachable, // invalid timeout
                    else => unreachable,
                };
            },
            else => @compileError("unimplemented: futexWait"),
        }
    }

    fn futexWake(ptr: *const u32, max_waiters: u32) void {
        @branchHint(.cold);
        assert(max_waiters != 0);

        if (builtin.single_threaded) return; // nothing to wake up

        if (use_parking_futex) {
            return parking_futex.wake(ptr, max_waiters);
        } else if (builtin.cpu.arch.isWasm()) {
            comptime assert(builtin.cpu.has(.wasm, .atomics));
            const woken_count = asm volatile (
                \\local.get %[ptr]
                \\local.get %[waiters]
                \\memory.atomic.notify 0
                \\local.set %[ret]
                : [ret] "=r" (-> u32),
                : [ptr] "r" (ptr),
                  [waiters] "r" (max_waiters),
            );
            _ = woken_count; // can be 0 when linker flag 'shared-memory' is not enabled
        } else switch (native_os) {
            .linux => {
                const linux = std.os.linux;
                switch (linux.errno(linux.futex_3arg(
                    ptr,
                    .{ .cmd = .WAKE, .private = true },
                    @min(max_waiters, std.math.maxInt(i32)),
                ))) {
                    .SUCCESS => return, // successful wake up
                    .INVAL => return, // invalid futex_wait() on ptr done elsewhere
                    .FAULT => return, // pointer became invalid while doing the wake
                    else => return recoverableOsBugDetected(), // deadlock due to operating system bug
                }
            },
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
                const c = std.c;
                const flags: c.UL = .{
                    .op = .COMPARE_AND_WAIT,
                    .NO_ERRNO = true,
                    .WAKE_ALL = max_waiters > 1,
                };
                while (true) {
                    const status = c.__ulock_wake(flags, ptr, 0);
                    if (status >= 0) return;
                    switch (@as(c.E, @enumFromInt(-status))) {
                        .INTR, .CANCELED => continue, // spurious wake()
                        .FAULT => unreachable, // __ulock_wake doesn't generate EFAULT according to darwin pthread_cond_t
                        .NOENT => return, // nothing was woken up
                        .ALREADY => unreachable, // only for UL.Op.WAKE_THREAD
                        else => unreachable, // deadlock due to operating system bug
                    }
                }
            },
            .freebsd => {
                const rc = std.c._umtx_op(
                    @intFromPtr(ptr),
                    @intFromEnum(std.c.UMTX_OP.WAKE_PRIVATE),
                    @as(c_ulong, @min(max_waiters, std.math.maxInt(c_int))),
                    0, // there is no timeout struct
                    0, // there is no timeout struct pointer
                );
                switch (posix.errno(rc)) {
                    .SUCCESS => {},
                    .FAULT => {}, // it's ok if the ptr doesn't point to valid memory
                    .INVAL => unreachable, // arguments should be correct
                    else => unreachable, // deadlock due to operating system bug
                }
            },
            .openbsd => {
                const rc = std.c.futex(
                    ptr,
                    std.c.FUTEX.WAKE | std.c.FUTEX.PRIVATE_FLAG,
                    @min(max_waiters, std.math.maxInt(c_int)),
                    null, // timeout is ignored
                    null, // uaddr2 is ignored
                );
                assert(rc >= 0);
            },
            .dragonfly => {
                // will generally return 0 unless the address is bad
                _ = std.c.umtx_wakeup(
                    @ptrCast(ptr),
                    @min(max_waiters, std.math.maxInt(c_int)),
                );
            },
            else => @compileError("unimplemented: futexWake"),
        }
    }

    /// Cancels `thread` if it is working on `awaitable`.
    ///
    /// It is possible that `thread` gets canceled by this function, but is blocked in a syscall. In
    /// that case, the thread may need to be sent a signal to interrupt the call. This function will
    /// return `true` to indicate this, in which case the caller must call `signalCanceledSyscall`.
    fn cancelAwaitable(thread: *Thread, awaitable: AwaitableId) bool {
        var status = thread.status.load(.monotonic);
        while (true) {
            if (status.awaitable != awaitable) return false; // thread is working on something else
            status = switch (status.cancelation) {
                .none => thread.status.cmpxchgWeak(
                    .{ .cancelation = .none, .awaitable = awaitable },
                    .{ .cancelation = .canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse return false,

                .parked => thread.status.cmpxchgWeak(
                    .{ .cancelation = .parked, .awaitable = awaitable },
                    .{ .cancelation = .canceling, .awaitable = awaitable },
                    .acquire, // acquire `thread.futex_waiter`
                    .monotonic,
                ) orelse {
                    if (!use_parking_futex and !use_parking_sleep) unreachable;
                    if (thread.futex_waiter) |futex_waiter| {
                        parking_futex.removeCanceledWaiter(futex_waiter);
                    }
                    if (need_unpark_flag) setUnparkFlag(&thread.unpark_flag);
                    unpark(&.{thread.id}, null);
                    return false;
                },

                .blocked => thread.status.cmpxchgWeak(
                    .{ .cancelation = .blocked, .awaitable = awaitable },
                    .{ .cancelation = .blocked_canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse return true,

                .blocked_alertable => thread.status.cmpxchgWeak(
                    .{ .cancelation = .blocked_alertable, .awaitable = awaitable },
                    .{ .cancelation = .blocked_alertable_canceling, .awaitable = awaitable },
                    .monotonic,
                    .monotonic,
                ) orelse {
                    if (!is_windows) unreachable;
                    return true;
                },

                .canceling, .canceled => {
                    // This can happen when the task start raced with the cancelation, so the thread
                    // saw the cancelation on the future/group *and* we are trying to signal the
                    // thread here.
                    return false;
                },

                .blocked_canceling => unreachable, // `awaitable` has not been canceled before now
                .blocked_alertable_canceling => unreachable, // `awaitable` has not been canceled before now
            };
        }
    }

    /// Sends a signal to `thread` if it is still blocked in a syscall (i.e. has not yet observed
    /// the cancelation request from `cancelAwaitable`).
    ///
    /// Unfortunately, the signal could arrive before the syscall actually starts, so the interrupt
    /// is missed. To handle this, we may need to send multiple signals. As such, if this function
    /// returns `true`, then it should be called again after a short delay to send another signal if
    /// the thread is still blocked. For the implementation, `Future.waitForCancelWithSignaling` and
    /// `Group.waitForCancelWithSignaling`: they use exponential backoff starting at a 1us delay and
    /// doubling each call. In practice, it is rare to send more than one signal.
    fn signalCanceledSyscall(thread: *Thread, t: *Threaded, awaitable: AwaitableId) bool {
        const status = thread.status.load(.monotonic);
        if (status.awaitable != awaitable) {
            // The thread has moved on and is working on something totally different.
            return false;
        }

        // The thread ID and/or handle can be read non-atomically because they never change and were
        // released by the store that made `thread` available to us.

        switch (status.cancelation) {
            .blocked_canceling => if (std.Thread.use_pthreads) {
                return switch (std.c.pthread_kill(thread.handle, .IO)) {
                    0 => true,
                    else => false,
                };
            } else switch (native_os) {
                .linux => {
                    const pid: posix.pid_t = pid: {
                        const cached_pid = @atomicLoad(Pid, &t.pid, .monotonic);
                        if (cached_pid != .unknown) break :pid @intFromEnum(cached_pid);
                        const pid = std.os.linux.getpid();
                        @atomicStore(Pid, &t.pid, @enumFromInt(pid), .monotonic);
                        break :pid pid;
                    };
                    return switch (std.os.linux.tgkill(pid, @bitCast(thread.id), .IO)) {
                        0 => true,
                        else => false,
                    };
                },
                .windows => {
                    var iosb: windows.IO_STATUS_BLOCK = undefined;
                    return switch (windows.ntdll.NtCancelSynchronousIoFile(thread.handle, null, &iosb)) {
                        .NOT_FOUND => true, // this might mean the operation hasn't started yet
                        .SUCCESS => false, // the OS confirmed that our cancelation worked
                        else => false,
                    };
                },
                else => return false,
            },

            .blocked_alertable_canceling => {
                if (!is_windows) unreachable;
                return switch (windows.ntdll.NtAlertThread(thread.handle)) {
                    .SUCCESS => true,
                    else => false,
                };
            },

            else => {
                // The thread is working on `awaitable`, but no longer needs signaling (they already
                // woke up and saw the cancelation).
                return false;
            },
        }
    }

    /// Like a `*Thread`, but 2 bits smaller than a pointer (because the LSBs are always 0 due to
    /// alignment) so that those two bits can be used in a `packed struct`.
    const PackedPtr = enum(@Int(.unsigned, @bitSizeOf(usize) - 2)) {
        null = 0,
        all_ones = std.math.maxInt(@Int(.unsigned, @bitSizeOf(usize) - 2)),
        _,

        const Split = packed struct(usize) { low: u2, high: PackedPtr };
        fn pack(ptr: *Thread) PackedPtr {
            const split: Split = @bitCast(@intFromPtr(ptr));
            assert(split.low == 0);
            return split.high;
        }
        fn unpack(ptr: PackedPtr) ?*Thread {
            const split: Split = .{ .low = 0, .high = ptr };
            return @ptrFromInt(@as(usize, @bitCast(split)));
        }
    };
};

const Syscall = struct {
    thread: ?*Thread,
    /// Marks entry to a syscall region. This should be tightly scoped around the actual syscall
    /// to minimize races. The syscall must be marked as "finished" by `checkCancel`, `finish`,
    /// or one of the wrappers of `finish`.
    fn start() Io.Cancelable!Syscall {
        const thread = Thread.current orelse return .{ .thread = null };
        switch (thread.cancel_protection) {
            .blocked => return .{ .thread = null },
            .unblocked => {},
        }
        switch (thread.status.fetchOr(.{
            .cancelation = @enumFromInt(0b011),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .blocked_canceling => unreachable,
            .none => return .{ .thread = thread }, // new status is `.blocked`
            .canceling => return error.Canceled, // new status is `.canceled`
            .canceled => return .{ .thread = null }, // new status is `.canceled` (unchanged)
        }
    }
    /// Checks whether this syscall has been canceled. This should be called when a syscall is
    /// interrupted through a mechanism which may indicate cancelation, or may be spurious. If
    /// the syscall was canceled, it is finished and `error.Canceled` is returned. Otherwise,
    /// the syscall is not marked finished, and the caller should retry.
    fn checkCancel(s: Syscall) Io.Cancelable!void {
        const thread = s.thread orelse return;
        switch (thread.status.fetchOr(.{
            .cancelation = @enumFromInt(0b010),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .parked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked => {}, // new status is `.blocked` (unchanged)
            .blocked_canceling => return error.Canceled, // new status is `.canceled`
        }
    }
    /// Marks this syscall as finished.
    fn finish(s: Syscall) void {
        const thread = s.thread orelse return;
        switch (thread.status.fetchXor(.{
            .cancelation = @enumFromInt(0b011),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .parked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked => {}, // new status is `.none`
            .blocked_canceling => {}, // new status is `.canceling`
        }
    }
    /// Indicates instead of `NtCancelSynchronousIoFile` we need to use
    /// `NtAlertThread` to interrupt the wait.
    ///
    /// Windows only, called from blocked state only.
    fn toAlertable(s: Syscall) Io.Cancelable!AlertableSyscall {
        comptime assert(is_windows);
        const thread = s.thread orelse return .{ .thread = null };
        var prev = thread.status.load(.monotonic);
        while (true) prev = switch (prev.cancelation) {
            .none => unreachable,
            .parked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_alertable_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,

            .blocked => thread.status.cmpxchgWeak(prev, .{
                .cancelation = .blocked_alertable,
                .awaitable = prev.awaitable,
            }, .monotonic, .monotonic) orelse return .{ .thread = thread },

            .blocked_canceling => thread.status.cmpxchgWeak(prev, .{
                .cancelation = .canceled,
                .awaitable = prev.awaitable,
            }, .monotonic, .monotonic) orelse return error.Canceled,
        };
    }
    /// Convenience wrapper which calls `finish`, then returns `err`.
    fn fail(s: Syscall, err: anytype) @TypeOf(err) {
        s.finish();
        return err;
    }
    /// Convenience wrapper which calls `finish`, then calls `Threaded.errnoBug`.
    fn errnoBug(s: Syscall, err: posix.E) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return Threaded.errnoBug(err);
    }
    /// Convenience wrapper which calls `finish`, then calls `posix.unexpectedErrno`.
    fn unexpectedErrno(s: Syscall, err: posix.E) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return posix.unexpectedErrno(err);
    }
    /// Convenience wrapper which calls `finish`, then calls `windows.statusBug`.
    fn ntstatusBug(s: Syscall, status: windows.NTSTATUS) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return windows.statusBug(status);
    }
    /// Convenience wrapper which calls `finish`, then calls `windows.unexpectedStatus`.
    fn unexpectedNtstatus(s: Syscall, status: windows.NTSTATUS) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return windows.unexpectedStatus(status);
    }
};

const AlertableSyscall = struct {
    thread: ?*Thread,

    comptime {
        assert(is_windows);
    }

    fn start() Io.Cancelable!AlertableSyscall {
        const thread = Thread.current orelse return .{ .thread = null };
        switch (thread.cancel_protection) {
            .blocked => return .{ .thread = null },
            .unblocked => {},
        }
        const old_status = thread.status.fetchOr(.{
            .cancelation = @enumFromInt(0b010),
            .awaitable = .null,
        }, .monotonic);
        switch (old_status.cancelation) {
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_alertable => unreachable,
            .blocked_canceling => unreachable,
            .blocked_alertable_canceling => unreachable,
            .none => return .{ .thread = thread }, // new status is `.blocked_alertable`
            .canceling => {
                // Status is unchanged (still `.canceling`)---change to `.canceled` before return.
                thread.status.store(.{ .cancelation = .canceled, .awaitable = old_status.awaitable }, .monotonic);
                return error.Canceled;
            },
            .canceled => return .{ .thread = null }, // new status is `.canceled` (unchanged)
        }
    }

    fn checkCancel(s: AlertableSyscall) Io.Cancelable!void {
        comptime assert(is_windows);
        const thread = s.thread orelse return;
        const old_status = thread.status.fetchOr(.{
            .cancelation = @enumFromInt(0b010),
            .awaitable = .null,
        }, .monotonic);
        switch (old_status.cancelation) {
            .none => unreachable,
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked_alertable => {}, // new status is `.blocked_alertable` (unchanged)
            .blocked_alertable_canceling => {
                // New status is `.canceling`---change to `.canceled` before return.
                thread.status.store(.{ .cancelation = .canceled, .awaitable = old_status.awaitable }, .monotonic);
                return error.Canceled;
            },
        }
    }

    fn finish(s: AlertableSyscall) void {
        comptime assert(is_windows);
        const thread = s.thread orelse return;
        switch (thread.status.fetchXor(.{
            .cancelation = @enumFromInt(0b010),
            .awaitable = .null,
        }, .monotonic).cancelation) {
            .none => unreachable,
            .parked => unreachable,
            .blocked => unreachable,
            .blocked_canceling => unreachable,
            .canceling => unreachable,
            .canceled => unreachable,
            .blocked_alertable => {}, // new status is `.none`
            .blocked_alertable_canceling => {}, // new status is `.canceling`
        }
    }

    fn fail(s: AlertableSyscall, err: anytype) @TypeOf(err) {
        s.finish();
        return err;
    }

    fn ntstatusBug(s: AlertableSyscall, status: windows.NTSTATUS) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return windows.statusBug(status);
    }

    fn unexpectedNtstatus(s: AlertableSyscall, status: windows.NTSTATUS) Io.UnexpectedError {
        @branchHint(.cold);
        s.finish();
        return windows.unexpectedStatus(status);
    }
};

pub fn waitForApcOrAlert() void {
    const infinite_timeout: windows.LARGE_INTEGER = std.math.minInt(windows.LARGE_INTEGER);
    _ = windows.ntdll.NtDelayExecution(.TRUE, &infinite_timeout);
}

pub const max_iovecs_len = 8;
pub const splat_buffer_size = 64;
/// Happens to be the same number that matches maximum number of handles that
/// NtWaitForMultipleObjects accepts. We use this value also for poll() on
/// posix systems.
const poll_buffer_len = 64;
pub const default_PATH = "/usr/local/bin:/bin/:/usr/bin";
/// There are multiple kernel bugs being worked around with retries.
const max_windows_kernel_bug_retries = 13;

comptime {
    if (@TypeOf(posix.IOV_MAX) != void) assert(max_iovecs_len <= posix.IOV_MAX);
}

pub const InitOptions = struct {
    /// Affects how many bytes are memory-mapped for threads.
    stack_size: usize = std.Thread.SpawnConfig.default_stack_size,
    /// Maximum thread pool size (excluding main thread) when dispatching async
    /// tasks. Until this limit, calls to `Io.async` when all threads are busy will
    /// cause a new thread to be spawned and permanently added to the pool. After
    /// this limit, calls to `Io.async` when all threads are busy run the task
    /// immediately.
    ///
    /// Defaults to one less than the number of logical CPU cores.
    ///
    /// Protected by `Threaded.mutex` once the I/O instance is already in use. See
    /// `setAsyncLimit`.
    async_limit: ?Io.Limit = null,
    /// Maximum thread pool size (excluding main thread) for dispatching concurrent
    /// tasks. Until this limit, calls to `Io.concurrent` will increase the thread
    /// pool size.
    ///
    /// After this number, calls to `Io.concurrent` return `error.ConcurrencyUnavailable`.
    concurrent_limit: Io.Limit = .unlimited,
    /// Affects the following operations:
    /// * `processExecutablePath` on OpenBSD and Haiku.
    argv0: Argv0 = .empty,
    /// Affects the following operations:
    /// * `fileIsTty`
    /// * `processExecutablePath` on OpenBSD and Haiku (observes "PATH").
    /// * `processSpawn`, `processSpawnPath`, `processReplace`, `processReplacePath`
    environ: process.Environ = .empty,
    /// If set to `true`, `File.MemoryMap` APIs will always take the fallback path.
    disable_memory_mapping: bool = false,
};

/// Related:
/// * `init_single_threaded`
pub fn init(
    /// Must be threadsafe. Only used for the following functions:
    /// * `Io.VTable.async`
    /// * `Io.VTable.concurrent`
    /// * `Io.VTable.groupAsync`
    /// * `Io.VTable.groupConcurrent`
    /// If these functions are avoided, then `Allocator.failing` may be passed
    /// here.
    gpa: Allocator,
    options: InitOptions,
) Threaded {
    if (builtin.single_threaded) return .{
        .allocator = gpa,
        .stack_size = options.stack_size,
        .async_limit = options.async_limit orelse init_single_threaded.async_limit,
        .cpu_count_error = init_single_threaded.cpu_count_error,
        .concurrent_limit = options.concurrent_limit,
        .old_sig_io = undefined,
        .old_sig_pipe = undefined,
        .have_signal_handler = init_single_threaded.have_signal_handler,
        .argv0 = options.argv0,
        .environ_initialized = options.environ.block.isEmpty(),
        .environ = .{ .process_environ = options.environ },
        .worker_threads = init_single_threaded.worker_threads,
        .disable_memory_mapping = options.disable_memory_mapping,
    };

    const cpu_count = std.Thread.getCpuCount();

    var t: Threaded = .{
        .allocator = gpa,
        .stack_size = options.stack_size,
        .async_limit = options.async_limit orelse if (cpu_count) |n| .limited(n - 1) else |_| .nothing,
        .concurrent_limit = options.concurrent_limit,
        .cpu_count_error = if (cpu_count) |_| null else |e| e,
        .old_sig_io = undefined,
        .old_sig_pipe = undefined,
        .have_signal_handler = false,
        .argv0 = options.argv0,
        .environ_initialized = options.environ.block.isEmpty(),
        .environ = .{ .process_environ = options.environ },
        .worker_threads = .init(null),
        .disable_memory_mapping = options.disable_memory_mapping,
    };

    if (posix.Sigaction != void) {
        // This causes sending `posix.SIG.IO` to thread to interrupt blocking
        // syscalls, returning `posix.E.INTR`.
        const act: posix.Sigaction = .{
            .handler = .{ .handler = doNothingSignalHandler },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        if (have_sig_io) posix.sigaction(.IO, &act, &t.old_sig_io);
        if (have_sig_pipe) posix.sigaction(.PIPE, &act, &t.old_sig_pipe);
        t.have_signal_handler = true;
    }

    return t;
}

/// Statically initialize such that calls to `Io.VTable.concurrent` will fail
/// with `error.ConcurrencyUnavailable`.
///
/// When initialized this way:
/// * cancel requests have no effect.
/// * `deinit` is safe, but unnecessary to call.
pub const init_single_threaded: Threaded = init: {
    const env_block: process.Environ.Block = if (is_windows) .global else .empty;
    break :init .{
        .allocator = .failing,
        .stack_size = std.Thread.SpawnConfig.default_stack_size,
        .async_limit = .nothing,
        .cpu_count_error = null,
        .concurrent_limit = .nothing,
        .old_sig_io = undefined,
        .old_sig_pipe = undefined,
        .have_signal_handler = false,
        .argv0 = .empty,
        .environ_initialized = env_block.isEmpty(),
        .environ = .{ .process_environ = .{ .block = env_block } },
        .worker_threads = .init(null),
        .disable_memory_mapping = false,
    };
};

var global_single_threaded_instance: Threaded = .init_single_threaded;

/// In general, the application is responsible for choosing the `Io`
/// implementation and library code should accept an `Io` parameter rather than
/// accessing this declaration. Most code should avoid referencing this
/// declaration entirely.
///
/// However, in some cases such as debugging, it is desirable to hardcode a
/// reference to this `Io` implementation.
///
/// This instance does not support concurrency or cancelation.
pub const global_single_threaded: *Threaded = &global_single_threaded_instance;

pub fn setAsyncLimit(t: *Threaded, new_limit: Io.Limit) void {
    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);
    t.async_limit = new_limit;
}

pub fn deinit(t: *Threaded) void {
    t.join();
    if (posix.Sigaction != void and t.have_signal_handler) {
        if (have_sig_io) posix.sigaction(.IO, &t.old_sig_io, null);
        if (have_sig_pipe) posix.sigaction(.PIPE, &t.old_sig_pipe, null);
    }
    t.dl.deinit();
    t.null_file.deinit();
    t.random_file.deinit();
    t.pipe_file.deinit();
    t.* = undefined;
}

fn join(t: *Threaded) void {
    if (builtin.single_threaded) return;
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);
        t.join_requested = true;
    }
    condBroadcast(&t.cond);
    t.wait_group.wait();
}

fn worker(t: *Threaded) void {
    var thread: Thread = .{
        .next = undefined,
        .id = std.Thread.getCurrentId(),
        .handle = handle: {
            if (std.Thread.use_pthreads) break :handle std.c.pthread_self();
            if (is_windows) break :handle undefined; // populated below
        },
        .status = .init(.{
            .cancelation = .none,
            .awaitable = .null,
        }),
        .cancel_protection = .unblocked,
        .futex_waiter = undefined,
        .unpark_flag = unpark_flag_init,
        .csprng = .uninitialized,
    };
    Thread.current = &thread;

    if (is_windows) {
        assert(windows.ntdll.NtOpenThread(
            &thread.handle,
            .{
                .SPECIFIC = .{
                    .THREAD = .{
                        .TERMINATE = true, // for `NtCancelSynchronousIoFile`
                        .ALERT = true, // for `NtAlertThread`
                    },
                },
            },
            &.{ .ObjectName = null },
            &windows.teb().ClientId,
        ) == .SUCCESS);
    }
    defer if (is_windows) {
        windows.CloseHandle(thread.handle);
    };

    {
        var head = t.worker_threads.load(.monotonic);
        while (true) {
            thread.next = head;
            head = t.worker_threads.cmpxchgWeak(
                head,
                &thread,
                .release,
                .monotonic,
            ) orelse break;
        }
    }

    defer t.wait_group.finish();

    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);

    while (true) {
        while (t.run_queue.popFirst()) |runnable_node| {
            mutexUnlock(&t.mutex);
            thread.cancel_protection = .unblocked;
            const runnable: *Runnable = @fieldParentPtr("node", runnable_node);
            runnable.startFn(runnable, &thread, t);
            mutexLock(&t.mutex);
            t.busy_count -= 1;
        }
        if (t.join_requested) break;
        condWait(&t.cond, &t.mutex);
    }
}

pub fn io(t: *Threaded) Io {
    return .{
        .userdata = t,
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
            .dirStat = dirStat,
            .dirStatFile = dirStatFile,
            .dirAccess = dirAccess,
            .dirCreateFile = dirCreateFile,
            .dirCreateFileAtomic = dirCreateFileAtomic,
            .dirOpenFile = dirOpenFile,
            .dirOpenDir = dirOpenDir,
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
            .fileSupportsAnsiEscapeCodes = fileSupportsAnsiEscapeCodes,
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

            .netListenIp = switch (native_os) {
                .windows => netListenIpWindows,
                else => netListenIpPosix,
            },
            .netListenUnix = switch (native_os) {
                .windows => netListenUnixWindows,
                else => netListenUnixPosix,
            },
            .netAccept = switch (native_os) {
                .windows => netAcceptWindows,
                else => netAcceptPosix,
            },
            .netBindIp = switch (native_os) {
                .windows => netBindIpWindows,
                else => netBindIpPosix,
            },
            .netConnectIp = switch (native_os) {
                .windows => netConnectIpWindows,
                else => netConnectIpPosix,
            },
            .netConnectUnix = switch (native_os) {
                .windows => netConnectUnixWindows,
                else => netConnectUnixPosix,
            },
            .netSocketCreatePair = netSocketCreatePair,
            .netClose = netClose,
            .netShutdown = switch (native_os) {
                .windows => netShutdownWindows,
                else => netShutdownPosix,
            },
            .netRead = switch (native_os) {
                .windows => netReadWindows,
                else => netReadPosix,
            },
            .netWrite = switch (native_os) {
                .windows => netWriteWindows,
                else => netWritePosix,
            },
            .netWriteFile = netWriteFile,
            .netSend = switch (native_os) {
                .windows => netSendWindows,
                else => netSendPosix,
            },
            .netInterfaceNameResolve = netInterfaceNameResolve,
            .netInterfaceName = netInterfaceName,
            .netLookup = netLookup,
        },
    };
}

pub const socket_flags_unsupported = is_darwin or native_os == .haiku;
const have_accept4 = !socket_flags_unsupported;
const have_flock_open_flags = @hasField(posix.O, "EXLOCK");
const have_networking = std.options.networking and native_os != .wasi;
const have_flock = @TypeOf(posix.system.flock) != void;
const have_sendmmsg = native_os == .linux;
const have_futex = switch (builtin.cpu.arch) {
    .wasm32, .wasm64 => builtin.cpu.has(.wasm, .atomics),
    else => true,
};
const have_preadv = switch (native_os) {
    .windows, .haiku => false,
    else => true,
};
const have_sig_io = posix.SIG != void and @hasField(posix.SIG, "IO");
const have_sig_pipe = posix.SIG != void and @hasField(posix.SIG, "PIPE");
const have_sendfile = if (builtin.link_libc) @TypeOf(std.c.sendfile) != void else native_os == .linux;
const have_copy_file_range = switch (native_os) {
    .linux, .freebsd => true,
    else => false,
};
const have_fcopyfile = is_darwin;
const have_fchmodat2 = native_os == .linux and
    (builtin.os.isAtLeast(.linux, .{ .major = 6, .minor = 6, .patch = 0 }) orelse true) and
    (builtin.abi.isAndroid() or !std.c.versionCheck(.{ .major = 2, .minor = 32, .patch = 0 }));
const have_fchmodat_flags = native_os != .linux or
    (!builtin.abi.isAndroid() and std.c.versionCheck(.{ .major = 2, .minor = 32, .patch = 0 }));

const have_fchown = switch (native_os) {
    .wasi, .windows => false,
    else => true,
};

const have_fchmod = switch (native_os) {
    .windows => false,
    .wasi => builtin.link_libc,
    else => true,
};

const have_waitid = switch (native_os) {
    .linux => @hasField(std.os.linux.SYS, "waitid"),
    else => false,
};

const have_wait4 = switch (native_os) {
    .linux => @hasField(std.os.linux.SYS, "wait4"),
    .dragonfly, .freebsd, .netbsd, .openbsd, .illumos, .serenity, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => true,
    else => false,
};

const have_mmap = switch (native_os) {
    .wasi, .windows => false,
    else => true,
};
const have_poll = switch (native_os) {
    .wasi, .windows => false,
    else => true,
};

const open_sym = if (posix.lfs64_abi) posix.system.open64 else posix.system.open;
const openat_sym = if (posix.lfs64_abi) posix.system.openat64 else posix.system.openat;
const fstat_sym = if (posix.lfs64_abi) posix.system.fstat64 else posix.system.fstat;
const fstatat_sym = if (posix.lfs64_abi) posix.system.fstatat64 else posix.system.fstatat;
const lseek_sym = if (posix.lfs64_abi) posix.system.lseek64 else posix.system.lseek;
const preadv_sym = if (posix.lfs64_abi) posix.system.preadv64 else posix.system.preadv;
const pread_sym = if (posix.lfs64_abi) posix.system.pread64 else posix.system.pread;
const ftruncate_sym = if (posix.lfs64_abi) posix.system.ftruncate64 else posix.system.ftruncate;
const pwritev_sym = if (posix.lfs64_abi) posix.system.pwritev64 else posix.system.pwritev;
const pwrite_sym = if (posix.lfs64_abi) posix.system.pwrite64 else posix.system.pwrite;
const sendfile_sym = if (posix.lfs64_abi) posix.system.sendfile64 else posix.system.sendfile;
const mmap_sym = if (posix.lfs64_abi) posix.system.mmap64 else posix.system.mmap;

const linux_copy_file_range_use_c = std.c.versionCheck(if (builtin.abi.isAndroid()) .{
    .major = 34,
    .minor = 0,
    .patch = 0,
} else .{
    .major = 2,
    .minor = 27,
    .patch = 0,
});
const linux_copy_file_range_sys = if (linux_copy_file_range_use_c) std.c else std.os.linux;

const statx_use_c = std.c.versionCheck(if (builtin.abi.isAndroid())
    .{ .major = 30, .minor = 0, .patch = 0 }
else
    .{ .major = 2, .minor = 28, .patch = 0 });

const use_libc_getrandom = std.c.versionCheck(if (builtin.abi.isAndroid()) .{
    .major = 28,
    .minor = 0,
    .patch = 0,
} else .{
    .major = 2,
    .minor = 25,
    .patch = 0,
});

const use_dev_urandom = @TypeOf(posix.system.getrandom) == void and native_os == .linux;

fn crashHandler(userdata: ?*anyopaque) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const thread = Thread.current orelse return;
    thread.status.store(.{ .cancelation = .canceled, .awaitable = .null }, .monotonic);
    thread.cancel_protection = .blocked;
}

fn async(
    userdata: ?*anyopaque,
    result: []u8,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*Io.AnyFuture {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (builtin.single_threaded) {
        start(context.ptr, result.ptr);
        return null;
    }

    const gpa = t.allocator;
    const future = Future.create(gpa, result.len, result_alignment, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => {
            start(context.ptr, result.ptr);
            return null;
        },
    };

    mutexLock(&t.mutex);

    const busy_count = t.busy_count;

    if (busy_count >= @intFromEnum(t.async_limit)) {
        mutexUnlock(&t.mutex);
        future.destroy(gpa);
        start(context.ptr, result.ptr);
        return null;
    }

    t.busy_count = busy_count + 1;

    const pool_size = t.wait_group.value();
    if (pool_size - busy_count == 0) {
        t.wait_group.start();
        const thread = std.Thread.spawn(.{ .stack_size = t.stack_size }, worker, .{t}) catch {
            t.wait_group.finish();
            t.busy_count = busy_count;
            mutexUnlock(&t.mutex);
            future.destroy(gpa);
            start(context.ptr, result.ptr);
            return null;
        };
        thread.detach();
    }

    t.run_queue.prepend(&future.runnable.node);

    mutexUnlock(&t.mutex);
    condSignal(&t.cond);
    return @ptrCast(future);
}

fn concurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: Alignment,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) Io.ConcurrentError!*Io.AnyFuture {
    if (builtin.single_threaded) return error.ConcurrencyUnavailable;

    const t: *Threaded = @ptrCast(@alignCast(userdata));

    const gpa = t.allocator;
    const future = Future.create(gpa, result_len, result_alignment, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };
    errdefer future.destroy(gpa);

    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);

    const busy_count = t.busy_count;

    if (busy_count >= @intFromEnum(t.concurrent_limit))
        return error.ConcurrencyUnavailable;

    t.busy_count = busy_count + 1;
    errdefer t.busy_count = busy_count;

    const pool_size = t.wait_group.value();
    if (pool_size - busy_count == 0) {
        t.wait_group.start();
        errdefer t.wait_group.finish();

        const thread = std.Thread.spawn(.{ .stack_size = t.stack_size }, worker, .{t}) catch
            return error.ConcurrencyUnavailable;

        thread.detach();
    }

    t.run_queue.prepend(&future.runnable.node);

    condSignal(&t.cond);
    return @ptrCast(future);
}

fn groupAsync(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const g: Group = .{ .ptr = type_erased };

    if (builtin.single_threaded) return groupAsyncEager(start, context.ptr);

    const gpa = t.allocator;
    const task = Group.Task.create(gpa, g, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return groupAsyncEager(start, context.ptr),
    };

    mutexLock(&t.mutex);

    const busy_count = t.busy_count;

    if (busy_count >= @intFromEnum(t.async_limit)) {
        mutexUnlock(&t.mutex);
        task.destroy(gpa);
        return groupAsyncEager(start, context.ptr);
    }

    t.busy_count = busy_count + 1;

    const pool_size = t.wait_group.value();
    if (pool_size - busy_count == 0) {
        t.wait_group.start();
        const thread = std.Thread.spawn(.{ .stack_size = t.stack_size }, worker, .{t}) catch {
            t.wait_group.finish();
            t.busy_count = busy_count;
            mutexUnlock(&t.mutex);
            task.destroy(gpa);
            return groupAsyncEager(start, context.ptr);
        };
        thread.detach();
    }

    // TODO: if this logic is changed to be lock-free, this `fetchAdd` must be released by the queue
    // prepend so that the task doesn't finish without observing this and try to decrement the count
    // below zero.
    _ = g.status().fetchAdd(.{
        .num_running = 1,
        .have_awaiter = false,
        .canceled = false,
    }, .monotonic);
    t.run_queue.prepend(&task.runnable.node);

    mutexUnlock(&t.mutex);
    condSignal(&t.cond);
}
fn groupAsyncEager(
    start: *const fn (context: *const anyopaque) void,
    context: *const anyopaque,
) void {
    start(context);
}

fn groupConcurrent(
    userdata: ?*anyopaque,
    type_erased: *Io.Group,
    context: []const u8,
    context_alignment: Alignment,
    start: *const fn (context: *const anyopaque) void,
) Io.ConcurrentError!void {
    if (builtin.single_threaded) return error.ConcurrencyUnavailable;

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const g: Group = .{ .ptr = type_erased };

    const gpa = t.allocator;
    const task = Group.Task.create(gpa, g, context, context_alignment, start) catch |err| switch (err) {
        error.OutOfMemory => return error.ConcurrencyUnavailable,
    };
    errdefer task.destroy(gpa);

    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);

    const busy_count = t.busy_count;

    if (busy_count >= @intFromEnum(t.concurrent_limit))
        return error.ConcurrencyUnavailable;

    t.busy_count = busy_count + 1;
    errdefer t.busy_count = busy_count;

    const pool_size = t.wait_group.value();
    if (pool_size - busy_count == 0) {
        t.wait_group.start();
        errdefer t.wait_group.finish();

        const thread = std.Thread.spawn(.{ .stack_size = t.stack_size }, worker, .{t}) catch
            return error.ConcurrencyUnavailable;

        thread.detach();
    }

    // TODO: if this logic is changed to be lock-free, this `fetchAdd` must be released by the queue
    // prepend so that the task doesn't finish without observing this and try to decrement the count
    // below zero.
    _ = g.status().fetchAdd(.{
        .num_running = 1,
        .have_awaiter = false,
        .canceled = false,
    }, .monotonic);
    t.run_queue.prepend(&task.runnable.node);

    condSignal(&t.cond);
}

fn groupAwait(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) Io.Cancelable!void {
    _ = initial_token; // we need to load `token` *after* the group finishes
    if (builtin.single_threaded) unreachable; // nothing to await
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const g: Group = .{ .ptr = type_erased };

    var num_completed: std.atomic.Value(u32) = .init(0);
    g.awaiter().* = &num_completed;

    const pre_await_status = g.status().fetchOr(.{
        .num_running = 0,
        .have_awaiter = true,
        .canceled = false,
    }, .acq_rel); // acquire results if complete; release `g.awaiter()`

    assert(!pre_await_status.have_awaiter);
    assert(!pre_await_status.canceled);
    if (pre_await_status.num_running == 0) {
        // Already done. Since the group is finished, it's illegal to spawn more tasks in it
        // until we return, so we can access `g.status()` non-atomically.
        g.status().raw.have_awaiter = false;
        return;
    }

    while (Thread.futexWait(&num_completed.raw, 0, null)) {
        switch (num_completed.load(.acquire)) { // acquire task results
            0 => continue,
            1 => break,
            else => unreachable, // group was reused before `await` returned
        }
    } else |err| switch (err) {
        error.Canceled => {
            const pre_cancel_status = g.status().fetchOr(.{
                .num_running = 0,
                .have_awaiter = false,
                .canceled = true,
            }, .acq_rel); // acquire results if complete; release `g.awaiter()`
            assert(pre_cancel_status.have_awaiter);
            assert(!pre_cancel_status.canceled);

            // Even if `pre_cancel_status.num_running == 0`, we still need to wait for the signal,
            // because in that case the last member of the group is already trying to modify it.
            // However, if we know everything is done, we *can* skip signaling blocked threads.
            const skip_signals = pre_cancel_status.num_running == 0;
            g.waitForCancelWithSignaling(t, &num_completed, skip_signals);

            // The group is finished, so it's illegal to spawn more tasks in it until we return, so
            // we can access `g.status()` non-atomically.
            g.status().raw.canceled = false;
            g.status().raw.have_awaiter = false;
            return error.Canceled;
        },
    }

    // The group is finished, so it's illegal to spawn more tasks in it until we return, so
    // we can access `g.status()` non-atomically.
    g.status().raw.have_awaiter = false;
}

fn groupCancel(userdata: ?*anyopaque, type_erased: *Io.Group, initial_token: *anyopaque) void {
    _ = initial_token;
    if (builtin.single_threaded) unreachable; // nothing to cancel
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const g: Group = .{ .ptr = type_erased };

    var num_completed: std.atomic.Value(u32) = .init(0);
    g.awaiter().* = &num_completed;

    const pre_cancel_status = g.status().fetchOr(.{
        .num_running = 0,
        .have_awaiter = true,
        .canceled = true,
    }, .acq_rel); // acquire results if complete; release `g.awaiter()`

    assert(!pre_cancel_status.have_awaiter);
    assert(!pre_cancel_status.canceled);
    if (pre_cancel_status.num_running == 0) {
        // Already done. Since the group is finished, it's illegal to spawn more tasks in it
        // until we return, so we can access `g.status()` non-atomically.
        g.status().raw.have_awaiter = false;
        g.status().raw.canceled = false;
        return;
    }

    g.waitForCancelWithSignaling(t, &num_completed, false);

    g.status().raw = .{ .num_running = 0, .have_awaiter = false, .canceled = false };
}

fn recancel(userdata: ?*anyopaque) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    recancelInner();
}
fn recancelInner() void {
    const thread = Thread.current.?; // called `recancel` but was not canceled
    switch (thread.status.fetchXor(.{
        .cancelation = @enumFromInt(0b001),
        .awaitable = .null,
    }, .monotonic).cancelation) {
        .canceled => {},
        .none => unreachable, // called `recancel` but was not canceled
        .canceling => unreachable, // called `recancel` but cancelation was already pending
        .parked => unreachable,
        .blocked => unreachable,
        .blocked_alertable => unreachable,
        .blocked_alertable_canceling => unreachable,
        .blocked_canceling => unreachable,
    }
}

fn swapCancelProtection(userdata: ?*anyopaque, new: Io.CancelProtection) Io.CancelProtection {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const thread = Thread.current orelse return .unblocked;
    const old = thread.cancel_protection;
    thread.cancel_protection = new;
    return old;
}

fn checkCancel(userdata: ?*anyopaque) Io.Cancelable!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return Thread.checkCancel();
}

fn await(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    _ = result_alignment;
    if (builtin.single_threaded) unreachable; // nothing to await
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const future: *Future = @ptrCast(@alignCast(any_future));

    var num_completed: std.atomic.Value(u32) = .init(0);
    future.awaiter = &num_completed;

    const pre_await_status = future.status.fetchOr(.{
        .tag = .pending_awaited,
        .thread = .null,
    }, .acq_rel); // acquire results if complete; release `future.awaiter`
    switch (pre_await_status.tag) {
        .pending => while (Thread.futexWait(&num_completed.raw, 0, null)) {
            switch (num_completed.load(.acquire)) { // acquire task results
                0 => continue,
                1 => break,
                else => unreachable, // group was reused before `await` returned
            }
        } else |err| switch (err) {
            error.Canceled => {
                const pre_cancel_status = future.status.fetchOr(.{
                    .tag = .pending_canceled,
                    .thread = .null,
                }, .acq_rel); // acquire results if complete; release `future.awaiter`
                const done_status = switch (pre_cancel_status.tag) {
                    .pending => unreachable, // invalid state: we already awaited
                    .pending_awaited => done_status: {
                        const working_thread = pre_cancel_status.thread.unpack();
                        future.waitForCancelWithSignaling(t, &num_completed, @alignCast(working_thread));
                        break :done_status future.status.load(.monotonic);
                    },
                    .pending_canceled => unreachable, // `await` raced with `cancel`
                    .done => done_status: {
                        // The task just finished, but we still need to wait for the signal, because the
                        // task thread already figured out that they need to update `future.awaiter`.
                        future.waitForCancelWithSignaling(t, &num_completed, null);
                        // Also, we have clobbered `future.status.tag` to `.pending_canceled`, but that's
                        // not actually a problem for the logic below.
                        break :done_status pre_cancel_status;
                    },
                };
                // If the future did not acknowledge the cancelation, we need to mark it outstanding
                // for us. Because `done_status.tag == .done`, the information about whether there
                // was an acknowledged cancelation is encoded in `done_status.thread`.
                assert(done_status.tag == .done);
                switch (done_status.thread) {
                    .null => recancelInner(), // cancelation was not acknowledged, so it's ours
                    .all_ones => {}, // cancelation was acknowledged, so it was this task's job to propagate it
                    _ => unreachable,
                }
            },
        },
        .pending_awaited => unreachable, // `await` raced with `await`
        .pending_canceled => unreachable, // `await` raced with `cancel`
        .done => {},
    }
    @memcpy(result, future.resultPointer());
    future.destroy(t.allocator);
}

fn cancel(
    userdata: ?*anyopaque,
    any_future: *Io.AnyFuture,
    result: []u8,
    result_alignment: Alignment,
) void {
    _ = result_alignment;
    if (builtin.single_threaded) unreachable; // nothing to cancel
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const future: *Future = @ptrCast(@alignCast(any_future));

    var num_completed: std.atomic.Value(u32) = .init(0);
    future.awaiter = &num_completed;

    const pre_cancel_status = future.status.fetchOr(.{
        .tag = .pending_canceled,
        .thread = .null,
    }, .acq_rel); // acquire results if complete; release `future.awaiter`
    switch (pre_cancel_status.tag) {
        .pending => {
            const working_thread = pre_cancel_status.thread.unpack();
            future.waitForCancelWithSignaling(t, &num_completed, @alignCast(working_thread));
        },
        .pending_awaited => unreachable, // `await` raced with `await`
        .pending_canceled => unreachable, // `await` raced with `cancel`
        .done => {},
    }
    @memcpy(result, future.resultPointer());
    future.destroy(t.allocator);
}

fn futexWait(userdata: ?*anyopaque, ptr: *const u32, expected: u32, timeout: Io.Timeout) Io.Cancelable!void {
    if (builtin.single_threaded) {
        assert(timeout != .none); // Deadlock.
        return;
    }
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const t_io = io(t);
    const timeout_ns: ?u64 = ns: {
        const d = timeout.toDurationFromNow(t_io) orelse break :ns null;
        break :ns std.math.lossyCast(u64, d.raw.toNanoseconds());
    };
    return Thread.futexWait(ptr, expected, timeout_ns);
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    if (builtin.single_threaded) unreachable; // Deadlock.
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    Thread.futexWaitUncancelable(ptr, expected, null);
}

fn futexWake(userdata: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
    if (builtin.single_threaded) return; // Nothing to wake up.
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    Thread.futexWake(ptr, max_waiters);
}

fn operate(userdata: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    switch (operation) {
        .file_read_streaming => |o| return .{
            .file_read_streaming = fileReadStreaming(t, o.file, o.data) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .file_write_streaming => |o| return .{
            .file_write_streaming = fileWriteStreaming(t, o.file, o.header, o.data, o.splat) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .device_io_control => |*o| return .{ .device_io_control = try deviceIoControl(o) },
        .net_receive => |*o| return .{ .net_receive = o: {
            if (!have_networking) break :o .{ error.NetworkDown, 0 };
            if (is_windows) break :o netReceiveWindows(t, o.socket_handle, o.message_buffer, o.data_buffer, o.flags);
            netReceivePosix(o.socket_handle, &o.message_buffer[0], o.data_buffer, o.flags, false) catch |err| switch (err) {
                error.Canceled => |e| return e,
                error.WouldBlock => unreachable,
                else => |e| break :o .{ e, 0 },
            };
            break :o .{ null, 1 };
        } },
    }
}

fn batchAwaitAsync(userdata: ?*anyopaque, b: *Io.Batch) Io.Cancelable!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (is_windows) {
        batchDrainSubmittedWindows(t, b, false) catch |err| switch (err) {
            error.ConcurrencyUnavailable => unreachable, // passed concurrency=false
            else => |e| return e,
        };
        const alertable_syscall = try AlertableSyscall.start();
        while (b.pending.head != .none and b.completed.head == .none) waitForApcOrAlert();
        alertable_syscall.finish();
        return;
    }
    if (have_poll) {
        var poll_buffer: [poll_buffer_len]posix.pollfd = undefined;
        var poll_len: u32 = 0;
        {
            var index = b.submitted.head;
            while (index != .none and poll_len < poll_buffer_len) {
                const submission = &b.storage[index.toIndex()].submission;
                switch (submission.operation) {
                    .file_read_streaming => |o| {
                        poll_buffer[poll_len] = .{
                            .fd = o.file.handle,
                            .events = posix.POLL.IN | posix.POLL.ERR,
                            .revents = 0,
                        };
                        poll_len += 1;
                    },
                    .file_write_streaming => |o| {
                        poll_buffer[poll_len] = .{
                            .fd = o.file.handle,
                            .events = posix.POLL.OUT | posix.POLL.ERR,
                            .revents = 0,
                        };
                        poll_len += 1;
                    },
                    .device_io_control => |o| {
                        poll_buffer[poll_len] = .{
                            .fd = o.file.handle,
                            .events = posix.POLL.OUT | posix.POLL.IN | posix.POLL.ERR,
                            .revents = 0,
                        };
                        poll_len += 1;
                    },
                    .net_receive => |*o| {
                        poll_buffer[poll_len] = .{
                            .fd = o.socket_handle,
                            .events = posix.POLL.IN | posix.POLL.ERR,
                            .revents = 0,
                        };
                        poll_len += 1;
                    },
                }
                index = submission.node.next;
            }
        }
        switch (poll_len) {
            0 => return,
            1 => {},
            else => while (true) {
                const timeout_ms: i32 = t: {
                    if (b.completed.head != .none) {
                        // It is legal to call batchWait with already completed
                        // operations in the ring. In such case, we need to avoid
                        // blocking in the poll syscall, but we can still take this
                        // opportunity to find additional ready operations.
                        break :t 0;
                    }
                    break :t std.math.maxInt(i32);
                };
                const syscall = try Syscall.start();
                const rc = posix.system.poll(&poll_buffer, poll_len, timeout_ms);
                syscall.finish();
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        if (rc == 0) {
                            if (b.completed.head != .none) {
                                // Since there are already completions available in the
                                // queue, this is neither a timeout nor a case for
                                // retrying.
                                return;
                            }
                            continue;
                        }
                        var prev_index: Io.Operation.OptionalIndex = .none;
                        var index = b.submitted.head;
                        for (poll_buffer[0..poll_len]) |poll_entry| {
                            const storage = &b.storage[index.toIndex()];
                            const submission = &storage.submission;
                            const next_index = submission.node.next;
                            if (poll_entry.revents != 0) {
                                const result = try operate(t, submission.operation);

                                switch (prev_index) {
                                    .none => b.submitted.head = next_index,
                                    else => b.storage[prev_index.toIndex()].submission.node.next = next_index,
                                }
                                if (next_index == .none) b.submitted.tail = prev_index;

                                switch (b.completed.tail) {
                                    .none => b.completed.head = index,
                                    else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
                                }
                                storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
                                b.completed.tail = index;
                            } else prev_index = index;
                            index = next_index;
                        }
                        assert(index == .none);
                        return;
                    },
                    .INTR => continue,
                    else => break,
                }
            },
        }
    }

    var tail_index = b.completed.tail;
    defer b.completed.tail = tail_index;
    var index = b.submitted.head;
    errdefer b.submitted.head = index;
    while (index != .none) {
        const storage = &b.storage[index.toIndex()];
        const submission = &storage.submission;
        const next_index = submission.node.next;
        const result = try operate(t, submission.operation);

        switch (tail_index) {
            .none => b.completed.head = index,
            else => b.storage[tail_index.toIndex()].completion.node.next = index,
        }
        storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
        tail_index = index;
        index = next_index;
    }
    b.submitted = .{ .head = .none, .tail = .none };
}

fn batchAwaitConcurrent(userdata: ?*anyopaque, b: *Io.Batch, timeout: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (is_windows) {
        const deadline: ?Io.Clock.Timestamp = timeout.toTimestamp(io(t));
        try batchDrainSubmittedWindows(t, b, true);
        while (b.pending.head != .none and b.completed.head == .none) {
            var delay_interval: windows.LARGE_INTEGER = interval: {
                const d = deadline orelse break :interval std.math.minInt(windows.LARGE_INTEGER);
                break :interval timeoutToWindowsInterval(.{ .deadline = d }).?;
            };
            const alertable_syscall = try AlertableSyscall.start();
            const delay_rc = windows.ntdll.NtDelayExecution(.TRUE, &delay_interval);
            alertable_syscall.finish();
            switch (delay_rc) {
                .SUCCESS, .TIMEOUT => {
                    // The thread woke due to the timeout. Although spurious
                    // timeouts are OK, when no deadline is passed we must not
                    // return `error.Timeout`.
                    if (timeout != .none and b.completed.head == .none) return error.Timeout;
                },
                else => {},
            }
        }
        return;
    }
    if (native_os == .wasi) {
        // TODO call poll_oneoff
        return error.ConcurrencyUnavailable;
    }
    if (!have_poll) return error.ConcurrencyUnavailable;
    var poll_buffer: [poll_buffer_len]posix.pollfd = undefined;
    var poll_storage: struct {
        gpa: Allocator,
        batch: *Io.Batch,
        slice: []posix.pollfd,
        len: u32,

        fn add(storage: *@This(), fd: File.Handle, events: @FieldType(posix.pollfd, "events")) Io.ConcurrentError!void {
            const len = storage.len;
            if (len == poll_buffer_len) {
                const slice: []posix.pollfd = if (storage.batch.userdata) |batch_userdata|
                    @as([*]posix.pollfd, @ptrCast(@alignCast(batch_userdata)))[0..storage.batch.storage.len]
                else allocation: {
                    const allocation = storage.gpa.alloc(posix.pollfd, storage.batch.storage.len) catch
                        return error.ConcurrencyUnavailable;
                    storage.batch.userdata = allocation.ptr;
                    break :allocation allocation;
                };
                @memcpy(slice[0..poll_buffer_len], storage.slice);
                storage.slice = slice;
            }
            storage.slice[len] = .{
                .fd = fd,
                .events = events,
                .revents = 0,
            };
            storage.len = len + 1;
        }
    } = .{ .gpa = t.allocator, .batch = b, .slice = &poll_buffer, .len = 0 };
    {
        var index = b.submitted.head;
        while (index != .none) {
            const storage = &b.storage[index.toIndex()];
            const submission = storage.submission;
            switch (submission.operation) {
                .file_read_streaming => |o| try poll_storage.add(o.file.handle, posix.POLL.IN | posix.POLL.ERR),
                .file_write_streaming => |o| try poll_storage.add(o.file.handle, posix.POLL.OUT | posix.POLL.ERR),
                .device_io_control => |o| try poll_storage.add(o.file.handle, posix.POLL.IN | posix.POLL.OUT | posix.POLL.ERR),
                .net_receive => |*o| nb: {
                    var data_i: usize = 0;
                    const result: Io.Operation.Result = .{ .net_receive = for (o.message_buffer, 0..) |*msg, msg_i| {
                        const remaining_data_buffer = o.data_buffer[data_i..];
                        netReceivePosix(o.socket_handle, msg, remaining_data_buffer, o.flags, true) catch |err| switch (err) {
                            error.Canceled => |e| return e,
                            error.WouldBlock => {
                                if (msg_i != 0) break .{ null, msg_i };
                                try poll_storage.add(o.socket_handle, posix.POLL.IN | posix.POLL.ERR);
                                break :nb;
                            },
                            else => |e| break .{ e, 0 },
                        };
                        data_i += msg.data.len;
                    } else .{ null, o.message_buffer.len } };
                    switch (b.completed.tail) {
                        .none => b.completed.head = index,
                        else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
                    }
                    storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
                    b.completed.tail = index;
                },
            }
            index = submission.node.next;
        }
    }
    switch (poll_storage.len) {
        0 => return,
        1 => if (timeout == .none and b.completed.head == .none) {
            const index = b.submitted.head;
            const storage = &b.storage[index.toIndex()];
            const result = try operate(t, storage.submission.operation);

            b.submitted = .{ .head = .none, .tail = .none };

            switch (b.completed.tail) {
                .none => b.completed.head = index,
                else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
            }
            storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
            b.completed.tail = index;
            return;
        },
        else => {},
    }
    const t_io = io(t);
    const deadline = timeout.toTimestamp(t_io);
    while (true) {
        const timeout_ms: i32 = t: {
            if (b.completed.head != .none) {
                // It is legal to call batchWait with already completed
                // operations in the ring. In such case, we need to avoid
                // blocking in the poll syscall, but we can still take this
                // opportunity to find additional ready operations.
                break :t 0;
            }
            const d = deadline orelse break :t -1;
            const duration = d.durationFromNow(t_io);
            break :t @min(@max(0, duration.raw.toMilliseconds()), std.math.maxInt(i32));
        };
        const syscall = try Syscall.start();
        const rc = posix.system.poll(poll_storage.slice.ptr, poll_storage.len, timeout_ms);
        syscall.finish();
        switch (posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) {
                    if (b.completed.head != .none) {
                        // Since there are already completions available in the
                        // queue, this is neither a timeout nor a case for
                        // retrying.
                        return;
                    }
                    // Although spurious timeouts are OK, when no deadline is
                    // passed we must not return `error.Timeout`.
                    if (deadline == null) continue;
                    return error.Timeout;
                }
                var prev_index: Io.Operation.OptionalIndex = .none;
                var index = b.submitted.head;
                for (poll_storage.slice[0..poll_storage.len]) |poll_entry| {
                    const submission = &b.storage[index.toIndex()].submission;
                    const next_index = submission.node.next;
                    if (poll_entry.revents != 0) {
                        const result = try operate(t, submission.operation);

                        switch (prev_index) {
                            .none => b.submitted.head = next_index,
                            else => b.storage[prev_index.toIndex()].submission.node.next = next_index,
                        }
                        if (next_index == .none) b.submitted.tail = prev_index;

                        switch (b.completed.tail) {
                            .none => b.completed.head = index,
                            else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
                        }
                        b.completed.tail = index;
                        b.storage[index.toIndex()] = .{ .completion = .{
                            .node = .{ .next = .none },
                            .result = result,
                        } };
                    } else prev_index = index;
                    index = next_index;
                }
                assert(index == .none);
                return;
            },
            .INTR => continue,
            else => return error.ConcurrencyUnavailable,
        }
    }
}

const WindowsBatchOperationUserdata = extern struct {
    file: windows.HANDLE,
    iosb: windows.IO_STATUS_BLOCK,

    const Erased = Io.Operation.Storage.Pending.Userdata;

    comptime {
        assert(@sizeOf(WindowsBatchOperationUserdata) <= @sizeOf(Erased));
    }

    fn toErased(userdata: *WindowsBatchOperationUserdata) *Erased {
        return @ptrCast(userdata);
    }

    fn fromErased(erased: *Erased) *WindowsBatchOperationUserdata {
        return @ptrCast(erased);
    }
};

fn batchCancel(userdata: ?*anyopaque, b: *Io.Batch) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (is_windows) {
        if (b.pending.head == .none) return;
        waitForApcOrAlert();
        var index = b.pending.head;
        while (index != .none) {
            const pending = &b.storage[index.toIndex()].pending;
            const operation_userdata: *WindowsBatchOperationUserdata = .fromErased(&pending.userdata);
            var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
            _ = windows.ntdll.NtCancelIoFileEx(operation_userdata.file, &operation_userdata.iosb, &cancel_iosb);
            index = pending.node.next;
        }
        while (b.pending.head != .none) waitForApcOrAlert();
    } else if (b.userdata) |batch_userdata| {
        const poll_storage: [*]posix.pollfd = @ptrCast(@alignCast(batch_userdata));
        t.allocator.free(poll_storage[0..b.storage.len]);
        b.userdata = null;
    }
}

fn batchCompleteBlockingWindows(
    b: *Io.Batch,
    operation_userdata: *WindowsBatchOperationUserdata,
    result: Io.Operation.Result,
) void {
    const erased_userdata = operation_userdata.toErased();
    const pending: *Io.Operation.Storage.Pending = @fieldParentPtr("userdata", erased_userdata);
    switch (pending.node.prev) {
        .none => b.pending.head = pending.node.next,
        else => |prev_index| b.storage[prev_index.toIndex()].pending.node.next = pending.node.next,
    }
    switch (pending.node.next) {
        .none => b.pending.tail = pending.node.prev,
        else => |next_index| b.storage[next_index.toIndex()].pending.node.prev = pending.node.prev,
    }
    const storage: *Io.Operation.Storage = @fieldParentPtr("pending", pending);
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - b.storage.ptr);
    switch (b.completed.tail) {
        .none => b.completed.head = index,
        else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
    }
    b.completed.tail = index;
    storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
}

fn batchApc(
    apc_context: ?*anyopaque,
    iosb: *windows.IO_STATUS_BLOCK,
    _: windows.ULONG,
) align(apc_align) callconv(.winapi) void {
    const b: *Io.Batch = @ptrCast(@alignCast(apc_context));
    const operation_userdata: *WindowsBatchOperationUserdata = @fieldParentPtr("iosb", iosb);
    const erased_userdata = operation_userdata.toErased();
    const pending: *Io.Operation.Storage.Pending = @fieldParentPtr("userdata", erased_userdata);
    switch (pending.node.prev) {
        .none => b.pending.head = pending.node.next,
        else => |prev_index| b.storage[prev_index.toIndex()].pending.node.next = pending.node.next,
    }
    switch (pending.node.next) {
        .none => b.pending.tail = pending.node.prev,
        else => |next_index| b.storage[next_index.toIndex()].pending.node.prev = pending.node.prev,
    }
    const storage: *Io.Operation.Storage = @fieldParentPtr("pending", pending);
    const index: Io.Operation.OptionalIndex = .fromIndex(storage - b.storage.ptr);
    switch (iosb.u.Status) {
        .CANCELLED => {
            const tail_index = b.unused.tail;
            switch (tail_index) {
                .none => b.unused.head = index,
                else => b.storage[tail_index.toIndex()].unused.next = index,
            }
            storage.* = .{ .unused = .{ .prev = tail_index, .next = .none } };
            b.unused.tail = index;
        },
        else => {
            switch (b.completed.tail) {
                .none => b.completed.head = index,
                else => |tail_index| b.storage[tail_index.toIndex()].completion.node.next = index,
            }
            b.completed.tail = index;
            const result: Io.Operation.Result = switch (pending.tag) {
                .file_read_streaming => .{ .file_read_streaming = ntReadFileResult(iosb) },
                .file_write_streaming => .{ .file_write_streaming = ntWriteFileResult(iosb) },
                .device_io_control => .{ .device_io_control = iosb.* },
                .net_receive => unreachable,
            };
            storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
        },
    }
}

/// If `concurrency` is false, `error.ConcurrencyUnavailable` is unreachable.
fn batchDrainSubmittedWindows(t: *Threaded, b: *Io.Batch, concurrency: bool) (Io.ConcurrentError || Io.Cancelable)!void {
    var index = b.submitted.head;
    errdefer b.submitted.head = index;
    while (index != .none) {
        const storage = &b.storage[index.toIndex()];
        const submission = storage.submission;
        storage.* = .{ .pending = .{
            .node = .{ .prev = b.pending.tail, .next = .none },
            .tag = submission.operation,
            .userdata = undefined,
        } };
        switch (b.pending.tail) {
            .none => b.pending.head = index,
            else => |tail_index| b.storage[tail_index.toIndex()].pending.node.next = index,
        }
        b.pending.tail = index;
        const operation_userdata: *WindowsBatchOperationUserdata = .fromErased(&storage.pending.userdata);
        errdefer {
            operation_userdata.iosb = .{ .u = .{ .Status = .CANCELLED }, .Information = undefined };
            batchApc(b, &operation_userdata.iosb, 0);
        }
        switch (submission.operation) {
            .file_read_streaming => |o| o: {
                var data_index: usize = 0;
                while (o.data.len - data_index != 0 and o.data[data_index].len == 0) data_index += 1;
                if (o.data.len - data_index == 0) {
                    operation_userdata.iosb = .{ .u = .{ .Status = .SUCCESS }, .Information = 0 };
                    batchApc(b, &operation_userdata.iosb, 0);
                    break :o;
                }
                const buffer = o.data[data_index];
                const short_buffer_len = std.math.lossyCast(u32, buffer.len);

                if (o.file.flags.nonblocking) {
                    operation_userdata.file = o.file.handle;
                    switch (windows.ntdll.NtReadFile(
                        o.file.handle,
                        null, // event
                        &batchApc,
                        b,
                        &operation_userdata.iosb,
                        buffer.ptr,
                        short_buffer_len,
                        null, // byte offset
                        null, // key
                    )) {
                        .PENDING, .SUCCESS => {},
                        .CANCELLED => unreachable,
                        else => |status| {
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                        },
                    }
                } else {
                    if (concurrency) return error.ConcurrencyUnavailable;

                    const syscall: Syscall = try .start();
                    while (true) switch (windows.ntdll.NtReadFile(
                        o.file.handle,
                        null, // event
                        null, // APC routine
                        null, // APC context
                        &operation_userdata.iosb,
                        buffer.ptr,
                        short_buffer_len,
                        null, // byte offset
                        null, // key
                    )) {
                        .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
                        .CANCELLED => {
                            try syscall.checkCancel();
                            continue;
                        },
                        else => |status| {
                            syscall.finish();
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                            break;
                        },
                    };
                }
            },
            .file_write_streaming => |o| o: {
                const buffer = windowsWriteBuffer(o.header, o.data, o.splat);
                if (buffer.len == 0) {
                    operation_userdata.iosb = .{ .u = .{ .Status = .SUCCESS }, .Information = 0 };
                    batchApc(b, &operation_userdata.iosb, 0);
                    break :o;
                }
                if (o.file.flags.nonblocking) {
                    operation_userdata.file = o.file.handle;
                    switch (windows.ntdll.NtWriteFile(
                        o.file.handle,
                        null, // event
                        &batchApc,
                        b,
                        &operation_userdata.iosb,
                        buffer.ptr,
                        @intCast(buffer.len),
                        null, // byte offset
                        null, // key
                    )) {
                        .PENDING, .SUCCESS => {},
                        .CANCELLED => unreachable,
                        else => |status| {
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                        },
                    }
                } else {
                    if (concurrency) return error.ConcurrencyUnavailable;

                    const syscall: Syscall = try .start();
                    while (true) switch (windows.ntdll.NtWriteFile(
                        o.file.handle,
                        null, // event
                        null, // APC routine
                        null, // APC context
                        &operation_userdata.iosb,
                        buffer.ptr,
                        @intCast(buffer.len),
                        null, // byte offset
                        null, // key
                    )) {
                        .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
                        .CANCELLED => {
                            try syscall.checkCancel();
                            continue;
                        },
                        else => |status| {
                            syscall.finish();
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                            break;
                        },
                    };
                }
            },
            .device_io_control => |o| {
                const NtControlFile = switch (o.code.DeviceType) {
                    .FILE_SYSTEM, .NAMED_PIPE => &windows.ntdll.NtFsControlFile,
                    else => &windows.ntdll.NtDeviceIoControlFile,
                };
                if (o.file.flags.nonblocking) {
                    operation_userdata.file = o.file.handle;
                    switch (NtControlFile(
                        o.file.handle,
                        null, // event
                        &batchApc,
                        b,
                        &operation_userdata.iosb,
                        o.code,
                        if (o.in.len > 0) o.in.ptr else null,
                        @intCast(o.in.len),
                        if (o.out.len > 0) o.out.ptr else null,
                        @intCast(o.out.len),
                    )) {
                        .PENDING, .SUCCESS => {},
                        .CANCELLED => unreachable,
                        else => |status| {
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                        },
                    }
                } else {
                    if (concurrency) return error.ConcurrencyUnavailable;

                    const syscall: Syscall = try .start();
                    while (true) switch (NtControlFile(
                        o.file.handle,
                        null, // event
                        null, // APC routine
                        null, // APC context
                        &operation_userdata.iosb,
                        o.code,
                        if (o.in.len > 0) o.in.ptr else null,
                        @intCast(o.in.len),
                        if (o.out.len > 0) o.out.ptr else null,
                        @intCast(o.out.len),
                    )) {
                        .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
                        .CANCELLED => {
                            try syscall.checkCancel();
                            continue;
                        },
                        else => |status| {
                            syscall.finish();
                            operation_userdata.iosb.u.Status = status;
                            batchApc(b, &operation_userdata.iosb, 0);
                            break;
                        },
                    };
                }
            },
            .net_receive => |*o| {
                // TODO integrate with overlapped I/O or equivalent to avoid this error
                if (concurrency) return error.ConcurrencyUnavailable;
                batchCompleteBlockingWindows(b, operation_userdata, .{
                    .net_receive = netReceiveWindows(t, o.socket_handle, o.message_buffer, o.data_buffer, o.flags),
                });
            },
        }
        index = submission.node.next;
    }
    b.submitted = .{ .head = .none, .tail = .none };
}

/// Since Windows only supports writing one contiguous buffer, returns the
/// first one, while also limiting it to a length representable by 32-bit
/// unsigned integer.
fn windowsWriteBuffer(header: []const u8, data: []const []const u8, splat: usize) []const u8 {
    const buffer = b: {
        if (header.len != 0) break :b header;
        for (data[0 .. data.len - 1]) |buffer| {
            if (buffer.len != 0) break :b buffer;
        }
        if (splat == 0) return &.{};
        break :b data[data.len - 1];
    };
    return buffer[0..std.math.lossyCast(u32, buffer.len)];
}

fn submitComplete(ring: []u32, complete_tail: *Io.Batch.RingIndex, op: u32) void {
    const ct = complete_tail.*;
    const len: u31 = @intCast(ring.len);
    ring[ct.index(len)] = op;
    complete_tail.* = ct.next(len);
}

const dirCreateDir = switch (native_os) {
    .windows => dirCreateDirWindows,
    .wasi => dirCreateDirWasi,
    else => dirCreateDirPosix,
};

fn dirCreateDirPosix(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.mkdirat(dir.handle, sub_path_posix, permissions.toMode()))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ACCES => return syscall.fail(error.AccessDenied),
            .PERM => return syscall.fail(error.PermissionDenied),
            .DQUOT => return syscall.fail(error.DiskQuota),
            .EXIST => return syscall.fail(error.PathAlreadyExists),
            .LOOP => return syscall.fail(error.SymLinkLoop),
            .MLINK => return syscall.fail(error.LinkQuotaExceeded),
            .NAMETOOLONG => return syscall.fail(error.NameTooLong),
            .NOENT => return syscall.fail(error.FileNotFound),
            .NOMEM => return syscall.fail(error.SystemResources),
            .NOSPC => return syscall.fail(error.NoSpaceLeft),
            .NOTDIR => return syscall.fail(error.NotDir),
            .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
            // dragonfly: when dir_fd is unlinked from filesystem
            .NOTCONN => return syscall.fail(error.FileNotFound),
            .ILSEQ => return syscall.fail(error.BadPathName),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            .FAULT => |err| return syscall.errnoBug(err),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn dirCreateDirWasi(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void {
    if (builtin.link_libc) return dirCreateDirPosix(userdata, dir, sub_path, permissions);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.wasi.path_create_directory(dir.handle, sub_path.ptr, sub_path.len)) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirCreateDirWindows(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, permissions: Dir.Permissions) Dir.CreateDirError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    _ = permissions; // TODO use this value

    const sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .Attributes = .{ .INHERIT = false },
        .ObjectName = @constCast(&windows.UNICODE_STRING.init(sub_path_w.span())),
        .SecurityDescriptor = null,
        .SecurityQualityOfService = null,
    };

    var sub_dir_handle: windows.HANDLE = undefined;
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var attempt: u5 = 0;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtCreateFile(
        &sub_dir_handle,
        .{
            .GENERIC = .{ .READ = true },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &attr,
        &io_status_block,
        null,
        .{ .NORMAL = true },
        .VALID_FLAGS,
        .CREATE,
        .{
            .DIRECTORY_FILE = true,
            .NON_DIRECTORY_FILE = false,
            .IO = .SYNCHRONOUS_NONALERT,
            .OPEN_REPARSE_POINT = false,
        },
        null,
        0,
    )) {
        .SUCCESS => {
            syscall.finish();
            windows.CloseHandle(sub_dir_handle);
            return;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .SHARING_VIOLATION => {
            // This occurs if the file attempting to be opened is a running
            // executable. However, there's a kernel bug: the error may be
            // incorrectly returned for an indeterminate amount of time
            // after an executable file is closed. Here we work around the
            // kernel bug with retry attempts.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.Unexpected;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .DELETE_PENDING => {
            // This error means that there *was* a file in this location on
            // the file system, but it was deleted. However, the OS is not
            // finished with the deletion operation, and so this CreateFile
            // call has failed. There is not really a sane way to handle
            // this other than retrying the creation after the OS finishes
            // the deletion.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.Unexpected;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
        .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .OBJECT_NAME_COLLISION => return syscall.fail(error.PathAlreadyExists),
        .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
        .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
        .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
        .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
}

fn dirCreateDirPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirPathError!Dir.CreatePathStatus {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    var it = Dir.path.componentIterator(sub_path);
    var status: Dir.CreatePathStatus = .existed;
    var component = it.last() orelse return error.BadPathName;
    while (true) {
        if (dirCreateDir(t, dir, component.path, permissions)) |_| {
            status = .created;
        } else |err| switch (err) {
            error.PathAlreadyExists => {
                // It is important to return an error if it's not a directory
                // because otherwise a dangling symlink could cause an infinite
                // loop.
                const kind = try filePathKind(t, dir, component.path);
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

const dirCreateDirPathOpen = switch (native_os) {
    .windows => dirCreateDirPathOpenWindows,
    .wasi => dirCreateDirPathOpenWasi,
    else => dirCreateDirPathOpenPosix,
};

fn dirCreateDirPathOpenPosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const t_io = io(t);
    return dirOpenDirPosix(t, dir, sub_path, options) catch |err| switch (err) {
        error.FileNotFound => {
            _ = try dir.createDirPathStatus(t_io, sub_path, permissions);
            return dirOpenDirPosix(t, dir, sub_path, options);
        },
        else => |e| return e,
    };
}

fn dirCreateDirPathOpenWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const w = windows;

    _ = permissions; // TODO apply these permissions

    var it = Dir.path.componentIterator(sub_path);
    // If there are no components in the path, then create a dummy component with the full path.
    var component: Dir.path.NativeComponentIterator.Component = it.last() orelse .{
        .name = "",
        .path = sub_path,
    };

    components: while (true) {
        const sub_path_w = try sliceToPrefixedFileW(dir.handle, component.path, .{});
        const attr: windows.OBJECT.ATTRIBUTES = .{
            .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
            .ObjectName = @constCast(&sub_path_w.string()),
        };
        const is_last = it.peekNext() == null;
        var result: Dir = .{ .handle = undefined };
        var iosb: w.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (w.ntdll.NtCreateFile(
            &result.handle,
            .{
                .SPECIFIC = .{ .FILE_DIRECTORY = .{
                    .LIST = options.iterate,
                    .READ_EA = true,
                    .READ_ATTRIBUTES = true,
                    .TRAVERSE = true,
                } },
                .STANDARD = .{
                    .RIGHTS = .READ,
                    .SYNCHRONIZE = true,
                },
            },
            &attr,
            &iosb,
            null,
            .{ .NORMAL = true },
            .VALID_FLAGS,
            if (is_last) .OPEN_IF else .CREATE,
            .{
                .DIRECTORY_FILE = true,
                .IO = .SYNCHRONOUS_NONALERT,
                .OPEN_FOR_BACKUP_INTENT = true,
                .OPEN_REPARSE_POINT = !options.follow_symlinks,
            },
            null,
            0,
        )) {
            .SUCCESS => {
                syscall.finish();
                component = it.next() orelse return result;
                w.CloseHandle(result.handle);
                continue :components;
            },
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
            .OBJECT_NAME_COLLISION => {
                syscall.finish();
                assert(!is_last);
                // stat the file and return an error if it's not a directory
                // this is important because otherwise a dangling symlink
                // could cause an infinite loop
                const fstat = try dirStatFileWindows(t, dir, component.path, .{
                    .follow_symlinks = options.follow_symlinks,
                });
                if (fstat.kind != .directory) return error.NotDir;

                component = it.next().?;
                continue :components;
            },

            .OBJECT_NAME_NOT_FOUND,
            .OBJECT_PATH_NOT_FOUND,
            => {
                syscall.finish();
                component = it.previous() orelse return error.FileNotFound;
                continue :components;
            },

            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            // This can happen if the directory has 'List folder contents' permission set to 'Deny'
            // and the directory is trying to be opened for iteration.
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .DISK_FULL => return syscall.fail(error.NoSpaceLeft),
            .INVALID_PARAMETER => |s| return syscall.ntstatusBug(s),
            else => |s| return syscall.unexpectedNtstatus(s),
        };
    }
}

fn dirCreateDirPathOpenWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.OpenOptions,
) Dir.CreateDirPathOpenError!Dir {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const t_io = io(t);
    return dirOpenDirWasi(t, dir, sub_path, options) catch |err| switch (err) {
        error.FileNotFound => {
            _ = try dir.createDirPathStatus(t_io, sub_path, permissions);
            return dirOpenDirWasi(t, dir, sub_path, options);
        },
        else => |e| return e,
    };
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    return fileStat(t, .{
        .handle = dir.handle,
        .flags = .{ .nonblocking = false },
    });
}

const dirStatFile = switch (native_os) {
    .linux => dirStatFileLinux,
    .windows => dirStatFileWindows,
    .wasi => dirStatFileWasi,
    else => dirStatFilePosix,
};

fn dirStatFileLinux(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const linux = std.os.linux;
    const sys = if (statx_use_c) std.c else std.os.linux;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: u32 = linux.AT.NO_AUTOMOUNT |
        @as(u32, if (!options.follow_symlinks) linux.AT.SYMLINK_NOFOLLOW else 0);

    const syscall: Syscall = try .start();
    while (true) {
        var statx = std.mem.zeroes(linux.Statx);
        switch (sys.errno(sys.statx(dir.handle, sub_path_posix, flags, linux_statx_request, &statx))) {
            .SUCCESS => {
                syscall.finish();
                return statFromLinux(&statx);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .LOOP => return error.SymLinkLoop,
                    .NAMETOOLONG => |err| return errnoBug(err), // Handled by pathToPosix() above.
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.NotDir,
                    .NOMEM => return error.SystemResources,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirStatFilePosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: u32 = if (!options.follow_symlinks) posix.AT.SYMLINK_NOFOLLOW else 0;

    return posixStatFile(dir.handle, sub_path_posix, flags);
}

fn posixStatFile(dir_fd: posix.fd_t, sub_path: [:0]const u8, flags: u32) Dir.StatFileError!File.Stat {
    const syscall: Syscall = try .start();
    while (true) {
        var stat = std.mem.zeroes(posix.Stat);
        switch (posix.errno(fstatat_sym(dir_fd, sub_path, &stat, flags))) {
            .SUCCESS => {
                syscall.finish();
                return statFromPosix(&stat);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirStatFileWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const file = try dirOpenFileWindows(t, dir, sub_path, .{
        .follow_symlinks = options.follow_symlinks,
    });
    defer windows.CloseHandle(file.handle);
    return fileStatWindows(t, file);
}

fn dirStatFileWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    if (builtin.link_libc) return dirStatFilePosix(userdata, dir, sub_path, options);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const wasi = std.os.wasi;
    const flags: wasi.lookupflags_t = .{
        .SYMLINK_FOLLOW = options.follow_symlinks,
    };
    var stat: wasi.filestat_t = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (wasi.path_filestat_get(dir.handle, flags, sub_path.ptr, sub_path.len, &stat)) {
            .SUCCESS => {
                syscall.finish();
                return statFromWasi(&stat);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOMEM => return error.SystemResources,
                    .ACCES => return error.AccessDenied,
                    .FAULT => |err| return errnoBug(err),
                    .NAMETOOLONG => return error.NameTooLong,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.FileNotFound,
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn filePathKind(t: *Threaded, dir: Dir, sub_path: []const u8) !File.Kind {
    if (native_os == .linux) {
        var path_buffer: [posix.PATH_MAX]u8 = undefined;
        const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

        const linux = std.os.linux;
        const syscall: Syscall = try .start();
        while (true) {
            var statx = std.mem.zeroes(linux.Statx);
            switch (linux.errno(linux.statx(
                dir.handle,
                sub_path_posix,
                linux.AT.NO_AUTOMOUNT | linux.AT.SYMLINK_NOFOLLOW,
                .{ .TYPE = true },
                &statx,
            ))) {
                .SUCCESS => {
                    syscall.finish();
                    if (!statx.mask.TYPE) return error.Unexpected;
                    return statxKind(statx.mode);
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .NOMEM => return syscall.fail(error.SystemResources),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }

    const stat = try dirStatFile(t, dir, sub_path, .{ .follow_symlinks = false });
    return stat.kind;
}

fn fileLength(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    if (native_os == .linux) {
        const linux = std.os.linux;

        const syscall: Syscall = try .start();
        while (true) {
            var statx = std.mem.zeroes(linux.Statx);
            switch (linux.errno(linux.statx(file.handle, "", linux.AT.EMPTY_PATH, .{ .SIZE = true }, &statx))) {
                .SUCCESS => {
                    syscall.finish();
                    if (!statx.mask.SIZE) return error.Unexpected;
                    return statx.size;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .ACCES => |err| return errnoBug(err),
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .FAULT => |err| return errnoBug(err),
                        .INVAL => |err| return errnoBug(err),
                        .LOOP => |err| return errnoBug(err),
                        .NAMETOOLONG => |err| return errnoBug(err),
                        .NOENT => |err| return errnoBug(err),
                        .NOMEM => return error.SystemResources,
                        .NOTDIR => |err| return errnoBug(err),
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    } else if (is_windows) {
        // TODO call NtQueryInformationFile and ask for only the size instead of "all"
    }

    const stat = try fileStat(t, file);
    return stat.size;
}

const fileStat = switch (native_os) {
    .linux => fileStatLinux,
    .windows => fileStatWindows,
    .wasi => fileStatWasi,
    else => fileStatPosix,
};

fn fileStatPosix(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (posix.Stat == void) return error.Streaming;

    const syscall: Syscall = try .start();
    while (true) {
        var stat = std.mem.zeroes(posix.Stat);
        switch (posix.errno(fstat_sym(file.handle, &stat))) {
            .SUCCESS => {
                syscall.finish();
                return statFromPosix(&stat);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOMEM => return error.SystemResources,
                    .ACCES => return error.AccessDenied,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileStatLinux(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const linux = std.os.linux;
    const sys = if (statx_use_c) std.c else std.os.linux;

    const syscall: Syscall = try .start();
    while (true) {
        var statx = std.mem.zeroes(linux.Statx);
        switch (sys.errno(sys.statx(file.handle, "", linux.AT.EMPTY_PATH, linux_statx_request, &statx))) {
            .SUCCESS => {
                syscall.finish();
                return statFromLinux(&statx);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .LOOP => |err| return errnoBug(err),
                    .NAMETOOLONG => |err| return errnoBug(err),
                    .NOENT => |err| return errnoBug(err),
                    .NOMEM => return error.SystemResources,
                    .NOTDIR => |err| return errnoBug(err),
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileStatWindows(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    const block_size: u32 = if (t.systemBasicInformation()) |sbi|
        @intCast(@max(sbi.PageSize, sbi.AllocationGranularity))
    else
        std.heap.page_size_max;

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var info: windows.FILE.ALL_INFORMATION = undefined;
    {
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtQueryInformationFile(
            file.handle,
            &io_status_block,
            &info,
            @sizeOf(windows.FILE.ALL_INFORMATION),
            .All,
        )) {
            .SUCCESS => break syscall.finish(),
            // Buffer overflow here indicates that there is more information available than was able to be stored in the buffer
            // size provided. This is treated as success because the type of variable-length information that this would be relevant for
            // (name, volume name, etc) we don't care about.
            .BUFFER_OVERFLOW => break syscall.finish(),
            .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => |s| return syscall.unexpectedNtstatus(s),
        };
    }
    return .{
        .inode = info.InternalInformation.IndexNumber,
        .size = @as(u64, @bitCast(info.StandardInformation.EndOfFile)),
        .permissions = .default_file,
        .kind = if (info.BasicInformation.FileAttributes.REPARSE_POINT) reparse_point: {
            var tag_info: windows.FILE.ATTRIBUTE_TAG_INFO = undefined;
            const syscall: Syscall = try .start();
            while (true) switch (windows.ntdll.NtQueryInformationFile(
                file.handle,
                &io_status_block,
                &tag_info,
                @sizeOf(windows.FILE.ATTRIBUTE_TAG_INFO),
                .AttributeTag,
            )) {
                .SUCCESS => break syscall.finish(),
                // INFO_LENGTH_MISMATCH and ACCESS_DENIED are the only documented possible errors
                // https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/d295752f-ce89-4b98-8553-266d37c84f0e
                .INFO_LENGTH_MISMATCH => |err| return syscall.ntstatusBug(err),
                .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
                .CANCELLED => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |s| return syscall.unexpectedNtstatus(s),
            };
            if (tag_info.ReparseTag.IsSurrogate) break :reparse_point .sym_link;
            // Unknown reparse point
            break :reparse_point .unknown;
        } else if (info.BasicInformation.FileAttributes.DIRECTORY)
            .directory
        else
            .file,
        .atime = windows.fromSysTime(info.BasicInformation.LastAccessTime),
        .mtime = windows.fromSysTime(info.BasicInformation.LastWriteTime),
        .ctime = windows.fromSysTime(info.BasicInformation.ChangeTime),
        .nlink = info.StandardInformation.NumberOfLinks,
        .block_size = block_size,
    };
}

fn systemBasicInformation(t: *Threaded) ?*const windows.SYSTEM.BASIC_INFORMATION {
    if (!t.system_basic_information.initialized.load(.acquire)) {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);

        switch (windows.ntdll.NtQuerySystemInformation(
            .Basic,
            &t.system_basic_information.buffer,
            @sizeOf(windows.SYSTEM.BASIC_INFORMATION),
            null,
        )) {
            .SUCCESS => {},
            else => return null,
        }

        t.system_basic_information.initialized.store(true, .release);
    }
    return &t.system_basic_information.buffer;
}

fn fileStatWasi(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    if (builtin.link_libc) return fileStatPosix(userdata, file);

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const syscall: Syscall = try .start();
    while (true) {
        var stat: std.os.wasi.filestat_t = undefined;
        switch (std.os.wasi.fd_filestat_get(file.handle, &stat)) {
            .SUCCESS => {
                syscall.finish();
                return statFromWasi(&stat);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOMEM => return error.SystemResources,
                    .ACCES => return error.AccessDenied,
                    .NOTCAPABLE => return error.AccessDenied,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirAccess = switch (native_os) {
    .windows => dirAccessWindows,
    .wasi => dirAccessWasi,
    else => dirAccessPosix,
};

fn dirAccessPosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const flags: u32 = @as(u32, if (!options.follow_symlinks) posix.AT.SYMLINK_NOFOLLOW else 0);

    const mode: u32 =
        @as(u32, if (options.read) posix.R_OK else 0) |
        @as(u32, if (options.write) posix.W_OK else 0) |
        @as(u32, if (options.execute) posix.X_OK else 0);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.faccessat(dir.handle, sub_path_posix, mode, flags))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirAccessWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    if (builtin.link_libc) return dirAccessPosix(userdata, dir, sub_path, options);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const wasi = std.os.wasi;
    const flags: wasi.lookupflags_t = .{
        .SYMLINK_FOLLOW = options.follow_symlinks,
    };
    var stat: wasi.filestat_t = undefined;

    const syscall: Syscall = try .start();
    while (true) {
        switch (wasi.path_filestat_get(dir.handle, flags, sub_path.ptr, sub_path.len, &stat)) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOMEM => return error.SystemResources,
                    .ACCES => return error.AccessDenied,
                    .FAULT => |err| return errnoBug(err),
                    .NAMETOOLONG => return error.NameTooLong,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.FileNotFound,
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }

    if (!options.read and !options.write and !options.execute)
        return;

    var directory: wasi.fdstat_t = undefined;
    if (wasi.fd_fdstat_get(dir.handle, &directory) != .SUCCESS)
        return error.AccessDenied;

    var rights: wasi.rights_t = .{};
    if (options.read) {
        if (stat.filetype == .DIRECTORY) {
            rights.FD_READDIR = true;
        } else {
            rights.FD_READ = true;
        }
    }
    if (options.write)
        rights.FD_WRITE = true;

    // No validation for execution.

    // https://github.com/ziglang/zig/issues/18882
    const rights_int: u64 = @bitCast(rights);
    const inheriting_int: u64 = @bitCast(directory.fs_rights_inheriting);
    if ((rights_int & inheriting_int) != rights_int)
        return error.AccessDenied;
}

fn dirAccessWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.AccessOptions,
) Dir.AccessError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    _ = options; // TODO

    if (std.mem.eql(u8, sub_path, ".") or std.mem.eql(u8, sub_path, "..")) return;
    const sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .ObjectName = @constCast(&sub_path_w.string()),
    };
    var basic_info: windows.FILE.BASIC_INFORMATION = undefined;
    const syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtQueryAttributesFile(&attr, &basic_info)) {
        .SUCCESS => return syscall.finish(),
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_NAME_INVALID => |err| return syscall.ntstatusBug(err),
        .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .OBJECT_PATH_SYNTAX_BAD => |err| return syscall.ntstatusBug(err),
        else => |rc| return syscall.unexpectedNtstatus(rc),
    };
}

const dirCreateFile = switch (native_os) {
    .windows => dirCreateFileWindows,
    .wasi => dirCreateFileWasi,
    else => dirCreateFilePosix,
};

fn dirCreateFilePosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.CreateFileOptions,
) File.OpenError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var flags: posix.O = .{
        .ACCMODE = if (options.read) .RDWR else .WRONLY,
        .CREAT = true,
        .TRUNC = options.truncate,
        .EXCL = options.exclusive,
    };
    if (@hasField(posix.O, "LARGEFILE")) flags.LARGEFILE = true;
    if (@hasField(posix.O, "CLOEXEC")) flags.CLOEXEC = true;
    if (@hasField(posix.O, "RESOLVE_BENEATH")) flags.RESOLVE_BENEATH = options.resolve_beneath;

    // Use the O locking flags if the os supports them to acquire the lock
    // atomically. Note that the NONBLOCK flag is removed after the openat()
    // call is successful.
    if (have_flock_open_flags) switch (options.lock) {
        .none => {},
        .shared => {
            flags.SHLOCK = true;
            flags.NONBLOCK = options.lock_nonblocking;
        },
        .exclusive => {
            flags.EXLOCK = true;
            flags.NONBLOCK = options.lock_nonblocking;
        },
    };

    const fd: posix.fd_t = fd: {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = openat_sym(dir.handle, sub_path_posix, flags, options.permissions.toMode());
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break :fd @intCast(rc);
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
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
                        .SRCH => return error.FileNotFound, // Linux when accessing procfs.
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
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    };
    errdefer closeFd(fd);

    if (have_flock and !have_flock_open_flags and options.lock != .none) {
        const lock_nonblocking: i32 = if (options.lock_nonblocking) posix.LOCK.NB else 0;
        const lock_flags = switch (options.lock) {
            .none => unreachable,
            .shared => posix.LOCK.SH | lock_nonblocking,
            .exclusive => posix.LOCK.EX | lock_nonblocking,
        };

        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(posix.system.flock(fd, lock_flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => |err| return errnoBug(err), // invalid parameters
                        .NOLCK => return error.SystemResources,
                        .AGAIN => return error.WouldBlock,
                        .OPNOTSUPP => return error.FileLocksUnsupported,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    if (have_flock_open_flags and options.lock_nonblocking) {
        var fl_flags: usize = fl: {
            const syscall: Syscall = try .start();
            while (true) {
                const rc = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break :fl @intCast(rc);
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |err| {
                        syscall.finish();
                        return posix.unexpectedErrno(err);
                    },
                }
            }
        };

        fl_flags |= @as(usize, 1 << @bitOffsetOf(posix.O, "NONBLOCK"));

        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, fl_flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |err| {
                    syscall.finish();
                    return posix.unexpectedErrno(err);
                },
            }
        }
    }

    return .{
        .handle = fd,
        .flags = .{ .nonblocking = false },
    };
}

fn dirCreateFileWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: Dir.CreateFileOptions,
) File.OpenError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (std.mem.eql(u8, sub_path, ".")) return error.IsDir;
    if (std.mem.eql(u8, sub_path, "..")) return error.IsDir;

    const sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .ObjectName = @constCast(&sub_path_w.string()),
    };
    const create_disposition: windows.FILE.CREATE_DISPOSITION = if (flags.exclusive)
        .CREATE
    else if (flags.truncate)
        .OVERWRITE_IF
    else
        .OPEN_IF;

    const access_mask: windows.ACCESS_MASK = .{
        .STANDARD = .{ .SYNCHRONIZE = true },
        .GENERIC = .{
            .WRITE = true,
            .READ = flags.read,
        },
    };

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var attempt: u5 = 0;
    var handle: windows.HANDLE = undefined;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtCreateFile(
        &handle,
        access_mask,
        &attr,
        &io_status_block,
        null,
        .{ .NORMAL = true },
        .VALID_FLAGS, // share access
        create_disposition,
        .{
            .NON_DIRECTORY_FILE = true,
            .IO = .SYNCHRONOUS_NONALERT,
        },
        null,
        0,
    )) {
        .SUCCESS => {
            syscall.finish();
            break;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .SHARING_VIOLATION => {
            // This occurs if the file attempting to be opened is a running
            // executable. However, there's a kernel bug: the error may be
            // incorrectly returned for an indeterminate amount of time
            // after an executable file is closed. Here we work around the
            // kernel bug with retry attempts.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .DELETE_PENDING => {
            // This error means that there *was* a file in this location on
            // the file system, but it was deleted. However, the OS is not
            // finished with the deletion operation, and so this CreateFile
            // call has failed. Here, we simulate the kernel bug being
            // fixed by sleeping and retrying until the error goes away.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
        .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
        .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .PIPE_BUSY => return syscall.fail(error.PipeBusy),
        .PIPE_NOT_AVAILABLE => return syscall.fail(error.NoDevice),
        .OBJECT_NAME_COLLISION => return syscall.fail(error.PathAlreadyExists),
        .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
        .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
        .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        .VIRUS_INFECTED, .VIRUS_DELETED => return syscall.fail(error.AntivirusInterference),
        .DISK_FULL => return syscall.fail(error.NoSpaceLeft),
        .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
        .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
        .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
    errdefer windows.CloseHandle(handle);

    const exclusive = switch (flags.lock) {
        .none => return .{
            .handle = handle,
            .flags = .{ .nonblocking = false },
        },
        .shared => false,
        .exclusive => true,
    };

    syscall = try .start();
    while (true) switch (windows.ntdll.NtLockFile(
        handle,
        null,
        null,
        null,
        &io_status_block,
        &windows_lock_range_off,
        &windows_lock_range_len,
        null,
        .fromBool(flags.lock_nonblocking),
        .fromBool(exclusive),
    )) {
        .SUCCESS => {
            syscall.finish();
            return .{
                .handle = handle,
                .flags = .{ .nonblocking = false },
            };
        },
        .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
        .LOCK_NOT_GRANTED => return syscall.fail(error.WouldBlock),
        .ACCESS_VIOLATION => |err| return syscall.ntstatusBug(err), // bad io_status_block pointer
        else => |status| return syscall.unexpectedNtstatus(status),
    };
}

fn dirCreateFileWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: Dir.CreateFileOptions,
) File.OpenError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const wasi = std.os.wasi;
    const lookup_flags: wasi.lookupflags_t = .{};
    const oflags: wasi.oflags_t = .{
        .CREAT = true,
        .TRUNC = flags.truncate,
        .EXCL = flags.exclusive,
    };
    const fdflags: wasi.fdflags_t = .{};
    const base: wasi.rights_t = .{
        .FD_READ = flags.read,
        .FD_WRITE = true,
        .FD_DATASYNC = true,
        .FD_SEEK = true,
        .FD_TELL = true,
        .FD_FDSTAT_SET_FLAGS = true,
        .FD_SYNC = true,
        .FD_ALLOCATE = true,
        .FD_ADVISE = true,
        .FD_FILESTAT_SET_TIMES = true,
        .FD_FILESTAT_SET_SIZE = true,
        .FD_FILESTAT_GET = true,
        // POLL_FD_READWRITE only grants extra rights if the corresponding FD_READ and/or
        // FD_WRITE is also set.
        .POLL_FD_READWRITE = true,
    };
    const inheriting: wasi.rights_t = .{};
    var fd: posix.fd_t = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (wasi.path_open(dir.handle, lookup_flags, sub_path.ptr, sub_path.len, oflags, base, inheriting, fdflags, &fd)) {
            .SUCCESS => {
                syscall.finish();
                return .{
                    .handle = fd,
                    .flags = .{ .nonblocking = false },
                };
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirCreateFileAtomic(
    userdata: ?*anyopaque,
    dir: Dir,
    dest_path: []const u8,
    options: Dir.CreateFileAtomicOptions,
) Dir.CreateFileAtomicError!File.Atomic {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const t_io = io(t);

    // Linux has O_TMPFILE, but linkat() does not support AT_REPLACE, so it's
    // useless when we have to make up a bogus path name to do the rename()
    // anyway.
    if (native_os == .linux and !options.replace) tmpfile: {
        const flags: posix.O = if (@hasField(posix.O, "TMPFILE")) .{
            .ACCMODE = .RDWR,
            .TMPFILE = true,
            .DIRECTORY = true,
            .CLOEXEC = true,
        } else if (@hasField(posix.O, "TMPFILE0") and !@hasField(posix.O, "TMPFILE2")) .{
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
            if (options.make_path) dir.createDirPath(t_io, dirname) catch |err| switch (err) {
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

        var path_buffer: [posix.PATH_MAX]u8 = undefined;
        const sub_path_posix = try pathToPosix(dest_dirname orelse ".", &path_buffer);

        const syscall: Syscall = try .start();
        while (true) {
            const rc = openat_sym(dir.handle, sub_path_posix, flags, options.permissions.toMode());
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    return .{
                        .file = .{
                            .handle = @intCast(rc),
                            .flags = .{ .nonblocking = false },
                        },
                        .file_basename_hex = 0,
                        .dest_sub_path = dest_path,
                        .file_open = true,
                        .file_exists = false,
                        .close_dir_on_deinit = false,
                        .dir = dir,
                    };
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .ISDIR, .NOENT, .OPNOTSUPP => {
                    // Ambiguous error code. It might mean the file system
                    // does not support O_TMPFILE. Therefore, we must fall
                    // back to not using O_TMPFILE.
                    syscall.finish();
                    break :tmpfile;
                },
                .INVAL => return syscall.fail(error.BadPathName),
                .ACCES => return syscall.fail(error.AccessDenied),
                .LOOP => return syscall.fail(error.SymLinkLoop),
                .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
                .NAMETOOLONG => return syscall.fail(error.NameTooLong),
                .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
                .NODEV => return syscall.fail(error.NoDevice),
                .NOMEM => return syscall.fail(error.SystemResources),
                .NOSPC => return syscall.fail(error.NoSpaceLeft),
                .NOTDIR => return syscall.fail(error.NotDir),
                .PERM => return syscall.fail(error.PermissionDenied),
                .AGAIN => return syscall.fail(error.WouldBlock),
                .NXIO => return syscall.fail(error.NoDevice),
                .ILSEQ => return syscall.fail(error.BadPathName),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }

    if (Dir.path.dirname(dest_path)) |dirname| {
        const new_dir = if (options.make_path)
            dir.createDirPathOpen(t_io, dirname, .{}) catch |err| switch (err) {
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
            try dir.openDir(t_io, dirname, .{});

        return atomicFileInit(t_io, Dir.path.basename(dest_path), options.permissions, new_dir, true);
    }

    return atomicFileInit(t_io, dest_path, options.permissions, dir, false);
}

fn atomicFileInit(
    t_io: Io,
    dest_basename: []const u8,
    permissions: File.Permissions,
    dir: Dir,
    close_dir_on_deinit: bool,
) Dir.CreateFileAtomicError!File.Atomic {
    while (true) {
        var random_integer: u64 = undefined;
        t_io.random(@ptrCast(&random_integer));
        const tmp_sub_path = std.fmt.hex(random_integer);
        const file = dir.createFile(t_io, &tmp_sub_path, .{
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

const dirOpenFile = switch (native_os) {
    .windows => dirOpenFileWindows,
    .wasi => dirOpenFileWasi,
    else => dirOpenFilePosix,
};

fn dirOpenFilePosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenFileOptions,
) File.OpenError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var flags: posix.O = switch (native_os) {
        .wasi => .{
            .read = options.mode != .write_only,
            .write = options.mode != .read_only,
            .NOFOLLOW = !options.follow_symlinks,
        },
        else => .{
            .ACCMODE = switch (options.mode) {
                .read_only => .RDONLY,
                .write_only => .WRONLY,
                .read_write => .RDWR,
            },
            .NOFOLLOW = !options.follow_symlinks,
        },
    };
    if (@hasField(posix.O, "CLOEXEC")) flags.CLOEXEC = true;
    if (@hasField(posix.O, "LARGEFILE")) flags.LARGEFILE = true;
    if (@hasField(posix.O, "NOCTTY")) flags.NOCTTY = !options.allow_ctty;
    if (@hasField(posix.O, "PATH")) flags.PATH = options.path_only;
    if (@hasField(posix.O, "RESOLVE_BENEATH")) flags.RESOLVE_BENEATH = options.resolve_beneath;

    // Use the O locking options if the os supports them to acquire the lock
    // atomically. Note that the NONBLOCK flag is removed after the openat()
    // call is successful.
    if (have_flock_open_flags) switch (options.lock) {
        .none => {},
        .shared => {
            flags.SHLOCK = true;
            flags.NONBLOCK = options.lock_nonblocking;
        },
        .exclusive => {
            flags.EXLOCK = true;
            flags.NONBLOCK = options.lock_nonblocking;
        },
    };

    const mode: posix.mode_t = 0;

    const fd: posix.fd_t = fd: {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = openat_sym(dir.handle, sub_path_posix, flags, mode);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break :fd @intCast(rc);
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
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
                        .OPNOTSUPP => return error.FileLocksUnsupported,
                        .AGAIN => return error.WouldBlock,
                        .TXTBSY => return error.FileBusy,
                        .NXIO => return error.NoDevice,
                        .ROFS => return error.ReadOnlyFileSystem,
                        .ILSEQ => return error.BadPathName,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    };
    errdefer closeFd(fd);

    if (!options.allow_directory) {
        const is_dir = is_dir: {
            const stat = fileStat(t, .{
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

    if (have_flock and !have_flock_open_flags and options.lock != .none) {
        const lock_nonblocking: i32 = if (options.lock_nonblocking) posix.LOCK.NB else 0;
        const lock_flags = switch (options.lock) {
            .none => unreachable,
            .shared => posix.LOCK.SH | lock_nonblocking,
            .exclusive => posix.LOCK.EX | lock_nonblocking,
        };
        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(posix.system.flock(fd, lock_flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => |err| return errnoBug(err), // invalid parameters
                        .NOLCK => return error.SystemResources,
                        .AGAIN => return error.WouldBlock,
                        .OPNOTSUPP => return error.FileLocksUnsupported,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    if (have_flock_open_flags and options.lock_nonblocking) {
        var fl_flags: usize = fl: {
            const syscall: Syscall = try .start();
            while (true) {
                const rc = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break :fl @intCast(rc);
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |err| {
                        syscall.finish();
                        return posix.unexpectedErrno(err);
                    },
                }
            }
        };

        fl_flags |= @as(usize, 1 << @bitOffsetOf(posix.O, "NONBLOCK"));

        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, fl_flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |err| {
                    syscall.finish();
                    return posix.unexpectedErrno(err);
                },
            }
        }
    }

    return .{
        .handle = fd,
        .flags = .{ .nonblocking = false },
    };
}

fn dirOpenFileWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: Dir.OpenFileOptions,
) File.OpenError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const sub_path_w_array = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const sub_path_w = sub_path_w_array.span();
    const dir_handle = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w)) null else dir.handle;
    return dirOpenFileWtf16(dir_handle, sub_path_w, flags);
}

pub fn dirOpenFileWtf16(
    dir_handle: ?windows.HANDLE,
    sub_path_w: []const u16,
    flags: Dir.OpenFileOptions,
) File.OpenError!File {
    const allow_directory = flags.allow_directory and !flags.isWrite();
    if (!allow_directory and std.mem.eql(u16, sub_path_w, &.{'.'})) return error.IsDir;
    if (!allow_directory and std.mem.eql(u16, sub_path_w, &.{ '.', '.' })) return error.IsDir;
    const w = windows;

    var io_status_block: w.IO_STATUS_BLOCK = undefined;
    var attempt: u5 = 0;
    var syscall: Syscall = try .start();
    const handle = while (true) {
        var result: w.HANDLE = undefined;
        switch (w.ntdll.NtCreateFile(
            &result,
            .{
                .STANDARD = .{ .SYNCHRONIZE = true },
                .GENERIC = .{
                    .READ = flags.isRead(),
                    .WRITE = flags.isWrite(),
                },
            },
            &.{
                .RootDirectory = dir_handle,
                .ObjectName = @constCast(&w.UNICODE_STRING.init(sub_path_w)),
            },
            &io_status_block,
            null,
            .{ .NORMAL = true },
            .VALID_FLAGS,
            .OPEN,
            .{
                .IO = if (flags.follow_symlinks) .SYNCHRONOUS_NONALERT else .ASYNCHRONOUS,
                .NON_DIRECTORY_FILE = !allow_directory,
                .OPEN_REPARSE_POINT = !flags.follow_symlinks,
            },
            null,
            0,
        )) {
            .SUCCESS => {
                syscall.finish();
                break result;
            },
            .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
            .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
            .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
            .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
            .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .SHARING_VIOLATION => {
                // This occurs if the file attempting to be opened is a running
                // executable. However, there's a kernel bug: the error may be
                // incorrectly returned for an indeterminate amount of time
                // after an executable file is closed. Here we work around the
                // kernel bug with retry attempts.
                syscall.finish();
                if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
                try parking_sleep.sleep(.{ .duration = .{
                    .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                    .clock = .awake,
                } });
                attempt += 1;
                syscall = try .start();
                continue;
            },
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .PIPE_BUSY => return syscall.fail(error.PipeBusy),
            .PIPE_NOT_AVAILABLE => return syscall.fail(error.NoDevice),
            .OBJECT_PATH_SYNTAX_BAD => |err| return syscall.ntstatusBug(err),
            .OBJECT_NAME_COLLISION => return syscall.fail(error.PathAlreadyExists),
            .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
            .INVALID_HANDLE => |err| return syscall.ntstatusBug(err),
            .DELETE_PENDING => {
                // This error means that there *was* a file in this location on
                // the file system, but it was deleted. However, the OS is not
                // finished with the deletion operation, and so this CreateFile
                // call has failed. Here, we simulate the kernel bug being
                // fixed by sleeping and retrying until the error goes away.
                syscall.finish();
                if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
                try parking_sleep.sleep(.{ .duration = .{
                    .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                    .clock = .awake,
                } });
                attempt += 1;
                syscall = try .start();
                continue;
            },
            .VIRUS_INFECTED, .VIRUS_DELETED => return syscall.fail(error.AntivirusInterference),
            else => |rc| return syscall.unexpectedNtstatus(rc),
        }
    };
    errdefer w.CloseHandle(handle);

    const exclusive = switch (flags.lock) {
        .none => return .{
            .handle = handle,
            .flags = .{ .nonblocking = false },
        },
        .shared => false,
        .exclusive => true,
    };
    syscall = try .start();
    while (true) switch (w.ntdll.NtLockFile(
        handle,
        null,
        null,
        null,
        &io_status_block,
        &windows_lock_range_off,
        &windows_lock_range_len,
        null,
        .fromBool(flags.lock_nonblocking),
        .fromBool(exclusive),
    )) {
        .SUCCESS => break syscall.finish(),
        .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
        .LOCK_NOT_GRANTED => return syscall.fail(error.WouldBlock),
        .ACCESS_VIOLATION => |err| return syscall.ntstatusBug(err), // bad io_status_block pointer
        else => |status| return syscall.unexpectedNtstatus(status),
    };
    return .{
        .handle = handle,
        .flags = .{ .nonblocking = false },
    };
}

fn dirOpenFileWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    flags: Dir.OpenFileOptions,
) File.OpenError!File {
    if (builtin.link_libc) return dirOpenFilePosix(userdata, dir, sub_path, flags);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const wasi = std.os.wasi;
    var base: std.os.wasi.rights_t = .{};
    // POLL_FD_READWRITE only grants extra rights if the corresponding FD_READ and/or FD_WRITE
    // is also set.
    if (flags.isRead()) {
        base.FD_READ = true;
        base.FD_TELL = true;
        base.FD_SEEK = true;
        base.FD_FILESTAT_GET = true;
        base.POLL_FD_READWRITE = true;
    }
    if (flags.isWrite()) {
        base.FD_WRITE = true;
        base.FD_TELL = true;
        base.FD_SEEK = true;
        base.FD_DATASYNC = true;
        base.FD_FDSTAT_SET_FLAGS = true;
        base.FD_SYNC = true;
        base.FD_ALLOCATE = true;
        base.FD_ADVISE = true;
        base.FD_FILESTAT_SET_TIMES = true;
        base.FD_FILESTAT_SET_SIZE = true;
        base.POLL_FD_READWRITE = true;
    }
    const lookup_flags: wasi.lookupflags_t = .{};
    const oflags: wasi.oflags_t = .{};
    const inheriting: wasi.rights_t = .{};
    const fdflags: wasi.fdflags_t = .{};
    var fd: posix.fd_t = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (wasi.path_open(dir.handle, lookup_flags, sub_path.ptr, sub_path.len, oflags, base, inheriting, fdflags, &fd)) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .FAULT => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .ACCES => return error.AccessDenied,
                    .FBIG => return error.FileTooBig,
                    .OVERFLOW => return error.FileTooBig,
                    .ISDIR => return error.IsDir,
                    .LOOP => return error.SymLinkLoop,
                    .MFILE => return error.ProcessFdQuotaExceeded,
                    .NFILE => return error.SystemFdQuotaExceeded,
                    .NODEV => return error.NoDevice,
                    .NOENT => return error.FileNotFound,
                    .NOMEM => return error.SystemResources,
                    .NOTDIR => return error.NotDir,
                    .PERM => return error.PermissionDenied,
                    .BUSY => return error.DeviceBusy,
                    .NOTCAPABLE => return error.AccessDenied,
                    .NAMETOOLONG => return error.NameTooLong,
                    .INVAL => return error.BadPathName,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
    errdefer closeFd(fd);

    if (!flags.allow_directory) {
        const is_dir = is_dir: {
            const stat = fileStat(t, .{ .handle = fd, .flags = .{ .nonblocking = false } }) catch |err| switch (err) {
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
        .flags = .{ .nonblocking = false },
    };
}

const dirOpenDir = switch (native_os) {
    .wasi => dirOpenDirWasi,
    .haiku => dirOpenDirHaiku,
    else => dirOpenDirPosix,
};

/// This function is also used for WASI when libc is linked.
fn dirOpenDirPosix(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        const sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
        return dirOpenDirWindows(dir, sub_path_w.span(), options);
    }

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    var flags: posix.O = switch (native_os) {
        .wasi => .{
            .read = true,
            .NOFOLLOW = !options.follow_symlinks,
            .DIRECTORY = true,
        },
        else => .{
            .ACCMODE = .RDONLY,
            .NOFOLLOW = !options.follow_symlinks,
            .DIRECTORY = true,
            .CLOEXEC = true,
        },
    };

    if (@hasField(posix.O, "PATH") and !options.iterate)
        flags.PATH = true;

    const mode: posix.mode_t = 0;

    const syscall: Syscall = try .start();
    while (true) {
        const rc = openat_sym(dir.handle, sub_path_posix, flags, mode);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return .{ .handle = @intCast(rc) };
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .INVAL => return syscall.fail(error.BadPathName),
            .ACCES => return syscall.fail(error.AccessDenied),
            .LOOP => return syscall.fail(error.SymLinkLoop),
            .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
            .NAMETOOLONG => return syscall.fail(error.NameTooLong),
            .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
            .NODEV => return syscall.fail(error.NoDevice),
            .NOENT => return syscall.fail(error.FileNotFound),
            .NOMEM => return syscall.fail(error.SystemResources),
            .NOTDIR => return syscall.fail(error.NotDir),
            .PERM => return syscall.fail(error.PermissionDenied),
            .NXIO => return syscall.fail(error.NoDevice),
            .ILSEQ => return syscall.fail(error.BadPathName),
            .FAULT => |err| return syscall.errnoBug(err),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            .BUSY => |err| return syscall.errnoBug(err), // O_EXCL not passed
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn dirOpenDirHaiku(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    _ = options;

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system._kern_open_dir(dir.handle, sub_path_posix);
        if (rc >= 0) {
            syscall.finish();
            return .{ .handle = rc };
        }
        switch (@as(posix.E, @enumFromInt(rc))) {
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
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
                    .BUSY => return error.DeviceBusy,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

pub fn dirOpenDirWindows(
    dir: Dir,
    sub_path_w: []const u16,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    const w = windows;

    var io_status_block: w.IO_STATUS_BLOCK = undefined;
    var result: Dir = .{ .handle = undefined };

    const attr: w.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w)) null else dir.handle,
        .ObjectName = @constCast(&w.UNICODE_STRING.init(sub_path_w)),
    };

    const syscall: Syscall = try .start();
    while (true) switch (w.ntdll.NtCreateFile(
        &result.handle,
        // TODO remove some of these flags if options.access_sub_paths is false
        .{
            .SPECIFIC = .{ .FILE_DIRECTORY = .{
                .LIST = options.iterate,
                .READ_EA = true,
                .TRAVERSE = true,
                .READ_ATTRIBUTES = true,
            } },
            .STANDARD = .{
                .RIGHTS = .READ,
                .SYNCHRONIZE = true,
            },
        },
        &attr,
        &io_status_block,
        null,
        .{ .NORMAL = true },
        .VALID_FLAGS,
        .OPEN,
        .{
            .DIRECTORY_FILE = true,
            .IO = .SYNCHRONOUS_NONALERT,
            .OPEN_FOR_BACKUP_INTENT = true,
            .OPEN_REPARSE_POINT = !options.follow_symlinks,
        },
        null,
        0,
    )) {
        .SUCCESS => {
            syscall.finish();
            return result;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_NAME_COLLISION => |err| return w.statusBug(err),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
        // This can happen if the directory has 'List folder contents' permission set to 'Deny'
        // and the directory is trying to be opened for iteration.
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
        else => |rc| return syscall.unexpectedNtstatus(rc),
    };
}

fn dirClose(userdata: ?*anyopaque, dirs: []const Dir) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    for (dirs) |dir| {
        if (is_windows) {
            windows.CloseHandle(dir.handle);
        } else {
            closeFd(dir.handle);
        }
    }
}

const dirRead = switch (native_os) {
    .linux => dirReadLinux,
    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => dirReadDarwin,
    .freebsd, .netbsd, .dragonfly, .openbsd => dirReadBsd,
    .illumos => dirReadIllumos,
    .haiku => dirReadHaiku,
    .windows => dirReadWindows,
    .wasi => dirReadWasi,
    else => dirReadUnimplemented,
};

fn dirReadLinux(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const linux = std.os.linux;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .reset) {
                posixSeekTo(dr.dir.handle, 0) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const syscall: Syscall = try .start();
            const n = while (true) {
                const rc = linux.getdents64(dr.dir.handle, dr.buffer.ptr, dr.buffer.len);
                switch (linux.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break rc;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
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
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
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

fn dirReadDarwin(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
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
                posixSeekTo(dr.dir.handle, 0) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const dents_buffer = dr.buffer[header_end..];
            const syscall: Syscall = try .start();
            const n: usize = while (true) {
                const rc = posix.system.getdirentries(dr.dir.handle, dents_buffer.ptr, dents_buffer.len, &header.seek);
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break @intCast(rc);
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability.
                            .FAULT => |err| return errnoBug(err),
                            .NOTDIR => |err| return errnoBug(err),
                            .INVAL => |err| return errnoBug(err),
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            };
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = header_end;
            dr.end = header_end + n;
        }
        const darwin_entry = @as(*align(1) posix.system.dirent, @ptrCast(&dr.buffer[dr.index]));
        const next_index = dr.index + darwin_entry.reclen;
        dr.index = next_index;

        const name = @as([*]u8, @ptrCast(&darwin_entry.name))[0..darwin_entry.namlen];
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or (darwin_entry.ino == 0))
            continue;

        const entry_kind: File.Kind = switch (darwin_entry.type) {
            posix.DT.BLK => .block_device,
            posix.DT.CHR => .character_device,
            posix.DT.DIR => .directory,
            posix.DT.FIFO => .named_pipe,
            posix.DT.LNK => .sym_link,
            posix.DT.REG => .file,
            posix.DT.SOCK => .unix_domain_socket,
            posix.DT.WHT => .whiteout,
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

fn dirReadBsd(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .reset) {
                posixSeekTo(dr.dir.handle, 0) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const syscall: Syscall = try .start();
            const n: usize = while (true) {
                const rc = posix.system.getdents(dr.dir.handle, dr.buffer.ptr, dr.buffer.len);
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break @intCast(rc);
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability
                            .FAULT => |err| return errnoBug(err),
                            .NOTDIR => |err| return errnoBug(err),
                            .INVAL => |err| return errnoBug(err),
                            // Introduced in freebsd 13.2: directory unlinked
                            // but still open. To be consistent, iteration ends
                            // if the directory being iterated is deleted
                            // during iteration.
                            .NOENT => {
                                dr.state = .finished;
                                return 0;
                            },
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            };
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = 0;
            dr.end = n;
        }
        const bsd_entry = @as(*align(1) posix.system.dirent, @ptrCast(&dr.buffer[dr.index]));
        const next_index = dr.index +
            if (@hasField(posix.system.dirent, "reclen")) bsd_entry.reclen else bsd_entry.reclen();
        dr.index = next_index;

        const name = @as([*]u8, @ptrCast(&bsd_entry.name))[0..bsd_entry.namlen];

        const skip_zero_fileno = switch (native_os) {
            // fileno=0 is used to mark invalid entries or deleted files.
            .openbsd, .netbsd => true,
            else => false,
        };
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or
            (skip_zero_fileno and bsd_entry.fileno == 0))
        {
            continue;
        }

        const entry_kind: File.Kind = switch (bsd_entry.type) {
            posix.DT.BLK => .block_device,
            posix.DT.CHR => .character_device,
            posix.DT.DIR => .directory,
            posix.DT.FIFO => .named_pipe,
            posix.DT.LNK => .sym_link,
            posix.DT.REG => .file,
            posix.DT.SOCK => .unix_domain_socket,
            posix.DT.WHT => .whiteout,
            else => .unknown,
        };
        buffer[buffer_index] = .{
            .name = name,
            .kind = entry_kind,
            .inode = bsd_entry.fileno,
        };
        buffer_index += 1;
    }
    return buffer_index;
}

fn dirReadIllumos(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .reset) {
                posixSeekTo(dr.dir.handle, 0) catch |err| switch (err) {
                    error.Unseekable => return error.Unexpected,
                    else => |e| return e,
                };
                dr.state = .reading;
            }
            const syscall: Syscall = try .start();
            const n: usize = while (true) {
                const rc = posix.system.getdents(dr.dir.handle, dr.buffer.ptr, dr.buffer.len);
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        break rc;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability
                            .FAULT => |err| return errnoBug(err),
                            .NOTDIR => |err| return errnoBug(err),
                            .INVAL => |err| return errnoBug(err),
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            };
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = 0;
            dr.end = n;
        }
        const entry = @as(*align(1) posix.system.dirent, @ptrCast(&dr.buffer[dr.index]));
        const next_index = dr.index + entry.reclen;
        dr.index = next_index;

        const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&entry.name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        // illumos dirent doesn't expose type, so we have to call stat to get it.
        const stat = try posixStatFile(dr.dir.handle, name, posix.AT.SYMLINK_NOFOLLOW);

        buffer[buffer_index] = .{
            .name = name,
            .kind = stat.kind,
            .inode = entry.ino,
        };
        buffer_index += 1;
    }
    return buffer_index;
}

fn dirReadHaiku(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    _ = userdata;
    _ = dr;
    _ = buffer;
    @panic("TODO implement dirReadHaiku");
}

fn dirReadWindows(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const w = windows;

    // We want to be able to use the `dr.buffer` for both the NtQueryDirectoryFile call (which
    // returns WTF-16 names) *and* as a buffer for storing those WTF-16 names as WTF-8 to be able
    // to return them in `Dir.Entry.name`. However, the problem that needs to be overcome in order to do
    // that is that each WTF-16 code unit can be encoded as a maximum of 3 WTF-8 bytes, which means
    // that it's not guaranteed that the memory used for the WTF-16 name will be sufficient
    // for the WTF-8 encoding of the same name (for example, € is encoded as one WTF-16 code unit,
    // [2 bytes] but encoded in WTF-8 as 3 bytes).
    //
    // The approach taken here is to "reserve" enough space in the `dr.buffer` to ensure that
    // at least one entry with the maximum possible WTF-8 name length can be stored without clobbering
    // any entries that follow it. That is, we determine how much space is needed to allow that,
    // and then only provide the remaining portion of `dr.buffer` to the NtQueryDirectoryFile
    // call. The WTF-16 names can then be safely converted using the full `dr.buffer` slice, making
    // sure that each name can only potentially overwrite the data of its own entry.
    //
    // The worst case, where an entry's name is both the maximum length of a component and
    // made up entirely of code points that are encoded as one WTF-16 code unit/three WTF-8 bytes,
    // would therefore look like the diagram below, and only one entry would be able to be returned:
    //
    //     |   reserved  | remaining unreserved buffer |
    //                   | entry 1 | entry 2 |   ...   |
    //     | wtf-8 name of entry 1 |
    //
    // However, in the average case we will be able to store more than one WTF-8 name at a time in the
    // available buffer and therefore we will be able to populate more than one `Dir.Entry` at a time.
    // That might look something like this (where name 1, name 2, etc are the converted WTF-8 names):
    //
    //     |   reserved  | remaining unreserved buffer |
    //                   | entry 1 | entry 2 |   ...   |
    //     | name 1 | name 2 | name 3 | name 4 |  ...  |
    //
    // Note: More than the minimum amount of space could be reserved to make the "worst case"
    // less likely, but since the worst-case also requires a maximum length component to matter,
    // it's unlikely for it to become a problem in normal scenarios even if all names on the filesystem
    // are made up of non-ASCII characters that have the "one WTF-16 code unit <-> three WTF-8 bytes"
    // property (e.g. code points >= U+0800 and <= U+FFFF), as it's unlikely for a significant
    // number of components to be maximum length.

    // We need `3 * NAME_MAX` bytes to store a max-length component as WTF-8 safely.
    // Because needing to store a max-length component depends on a `FileName` *with* the maximum
    // component length, we know that the corresponding populated `FILE_BOTH_DIR_INFORMATION` will
    // be of size `@sizeOf(w.FILE_BOTH_DIR_INFORMATION) + 2 * NAME_MAX` bytes, so we only need to
    // reserve enough to get us to up to having `3 * NAME_MAX` bytes available when taking into account
    // that we have the ability to write over top of the reserved memory + the full footprint of that
    // particular `FILE_BOTH_DIR_INFORMATION`.
    const max_info_len = @sizeOf(w.FILE_BOTH_DIR_INFORMATION) + w.NAME_MAX * 2;
    const info_align = @alignOf(w.FILE_BOTH_DIR_INFORMATION);
    const reserve_needed = std.mem.alignForward(usize, Dir.max_name_bytes, info_align) - max_info_len;
    const unreserved_start = std.mem.alignForward(usize, reserve_needed, info_align);
    const unreserved_buffer = dr.buffer[unreserved_start..];
    // This is enforced by `Dir.Reader`
    assert(unreserved_buffer.len >= max_info_len);

    var name_index: usize = 0;
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        if (dr.end - dr.index == 0) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;

            var io_status_block: w.IO_STATUS_BLOCK = undefined;
            const syscall: Syscall = try .start();
            const rc = while (true) switch (w.ntdll.NtQueryDirectoryFile(
                dr.dir.handle,
                null,
                null,
                null,
                &io_status_block,
                unreserved_buffer.ptr,
                std.math.lossyCast(w.ULONG, unreserved_buffer.len),
                .BothDirectory,
                .FALSE,
                null,
                .fromBool(dr.state == .reset),
            )) {
                .CANCELLED => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |rc| {
                    syscall.finish();
                    break rc;
                },
            };
            dr.state = .reading;
            if (io_status_block.Information == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = 0;
            dr.end = io_status_block.Information;
            switch (rc) {
                .SUCCESS => {},
                .ACCESS_DENIED => return error.AccessDenied, // Double-check that the Dir was opened with iteration ability
                else => return w.unexpectedStatus(rc),
            }
        }

        // While the official API docs guarantee FILE_BOTH_DIR_INFORMATION to be aligned properly
        // this may not always be the case (e.g. due to faulty VM/sandboxing tools)
        const dir_info: *align(2) w.FILE_BOTH_DIR_INFORMATION = @ptrCast(@alignCast(&unreserved_buffer[dr.index]));
        const backtrack_index = dr.index;
        if (dir_info.NextEntryOffset != 0) {
            dr.index += dir_info.NextEntryOffset;
        } else {
            dr.index = dr.end;
        }

        const name_wtf16le = @as([*]u16, @ptrCast(&dir_info.FileName))[0 .. dir_info.FileNameLength / 2];

        if (std.mem.eql(u16, name_wtf16le, &[_]u16{'.'}) or std.mem.eql(u16, name_wtf16le, &[_]u16{ '.', '.' })) {
            continue;
        }

        // Read any relevant information from the `dir_info` now since it's possible the WTF-8
        // name will overwrite it.
        const kind: File.Kind = blk: {
            const attrs = dir_info.FileAttributes;
            if (attrs.REPARSE_POINT) break :blk .sym_link;
            if (attrs.DIRECTORY) break :blk .directory;
            break :blk .file;
        };
        const inode: File.INode = dir_info.FileIndex;

        // If there's no more space for WTF-8 names without bleeding over into
        // the remaining unprocessed entries, then backtrack and return what we have so far.
        if (name_index + std.unicode.calcWtf8Len(name_wtf16le) > unreserved_start + dr.index) {
            // We should always be able to fit at least one entry into the buffer no matter what
            assert(buffer_index != 0);
            dr.index = backtrack_index;
            break;
        }

        const name_buf = dr.buffer[name_index..];
        const name_wtf8_len = std.unicode.wtf16LeToWtf8(name_buf, name_wtf16le);
        const name_wtf8 = name_buf[0..name_wtf8_len];
        name_index += name_wtf8_len;

        buffer[buffer_index] = .{
            .name = name_wtf8,
            .kind = kind,
            .inode = inode,
        };
        buffer_index += 1;
    }

    return buffer_index;
}

fn dirReadWasi(userdata: ?*anyopaque, dr: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    // We intentinally use fd_readdir even when linked with libc, since its
    // implementation is exactly the same as below, and we avoid the code
    // complexity here.
    const wasi = std.os.wasi;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const Header = extern struct {
        cookie: u64,
    };
    const header: *align(@alignOf(usize)) Header = @ptrCast(dr.buffer.ptr);
    const header_end: usize = @sizeOf(Header);
    if (dr.index < header_end) {
        // Initialize header.
        dr.index = header_end;
        dr.end = header_end;
        header.* = .{ .cookie = wasi.DIRCOOKIE_START };
    }
    var buffer_index: usize = 0;
    while (buffer.len - buffer_index != 0) {
        // According to the WASI spec, the last entry might be truncated, so we
        // need to check if the remaining buffer contains the whole dirent.
        if (dr.end - dr.index < @sizeOf(wasi.dirent_t)) {
            // Refill the buffer, unless we've already created references to
            // buffered data.
            if (buffer_index != 0) break;
            if (dr.state == .reset) {
                header.* = .{ .cookie = wasi.DIRCOOKIE_START };
                dr.state = .reading;
            }
            const dents_buffer = dr.buffer[header_end..];
            var n: usize = undefined;
            const syscall: Syscall = try .start();
            while (true) {
                switch (wasi.fd_readdir(dr.dir.handle, dents_buffer.ptr, dents_buffer.len, header.cookie, &n)) {
                    .SUCCESS => {
                        syscall.finish();
                        break;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .BADF => |err| return errnoBug(err), // Dir is invalid or was opened without iteration ability.
                            .FAULT => |err| return errnoBug(err),
                            .NOTDIR => |err| return errnoBug(err),
                            .INVAL => |err| return errnoBug(err),
                            // To be consistent across platforms, iteration
                            // ends if the directory being iterated is deleted
                            // during iteration. This matches the behavior of
                            // non-Linux, non-WASI UNIX platforms.
                            .NOENT => {
                                dr.state = .finished;
                                return 0;
                            },
                            .NOTCAPABLE => return error.AccessDenied,
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            }
            if (n == 0) {
                dr.state = .finished;
                return 0;
            }
            dr.index = header_end;
            dr.end = header_end + n;
        }
        const entry: *align(1) wasi.dirent_t = @ptrCast(&dr.buffer[dr.index]);
        const entry_size = @sizeOf(wasi.dirent_t);
        const name_index = dr.index + entry_size;
        if (name_index + entry.namlen > dr.end) {
            // This case, the name is truncated, so we need to call readdir to store the entire name.
            dr.end = dr.index; // Force fd_readdir in the next loop.
            continue;
        }
        const name = dr.buffer[name_index..][0..entry.namlen];
        const next_index = name_index + entry.namlen;
        dr.index = next_index;
        header.cookie = entry.next;

        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, ".."))
            continue;

        const entry_kind: File.Kind = switch (entry.type) {
            .BLOCK_DEVICE => .block_device,
            .CHARACTER_DEVICE => .character_device,
            .DIRECTORY => .directory,
            .SYMBOLIC_LINK => .sym_link,
            .REGULAR_FILE => .file,
            .SOCKET_STREAM, .SOCKET_DGRAM => .unix_domain_socket,
            else => .unknown,
        };
        buffer[buffer_index] = .{
            .name = name,
            .kind = entry_kind,
            .inode = entry.ino,
        };
        buffer_index += 1;
    }
    return buffer_index;
}

fn dirReadUnimplemented(userdata: ?*anyopaque, dir_reader: *Dir.Reader, buffer: []Dir.Entry) Dir.Reader.Error!usize {
    _ = userdata;
    _ = dir_reader;
    _ = buffer;
    return error.Unexpected;
}

const dirRealPathFile = switch (native_os) {
    .windows => dirRealPathFileWindows,
    else => dirRealPathFilePosix,
};

fn dirRealPathFileWindows(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_name_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});

    const h_file = handle: {
        if (OpenFile(path_name_w.span(), .{
            .dir = dir.handle,
            .access_mask = .{
                .GENERIC = .{ .READ = true },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            .creation = .OPEN,
            .filter = .any,
        })) |handle| {
            break :handle handle;
        } else |err| switch (err) {
            error.WouldBlock => unreachable,
            else => |e| return e,
        }
    };
    defer windows.CloseHandle(h_file);

    // We can re-use the path buffer for the WTF-16 representation since
    // we don't need the prefixed path anymore
    return realPathWindowsBuf(h_file, out_buffer, &path_name_w.data);
}

fn realPathWindows(h_file: windows.HANDLE, out_buffer: []u8) File.RealPathError!usize {
    var wide_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
    return realPathWindowsBuf(h_file, out_buffer, &wide_buf);
}

fn realPathWindowsBuf(h_file: windows.HANDLE, out_buffer: []u8, wtf16_buffer: []u16) File.RealPathError!usize {
    const wide_slice = try GetFinalPathNameByHandle(h_file, .{}, wtf16_buffer);

    const len = std.unicode.calcWtf8Len(wide_slice);
    if (len > out_buffer.len)
        return error.NameTooLong;

    return std.unicode.wtf16LeToWtf8(out_buffer, wide_slice);
}

/// Specifies how to format volume path in the result of `GetFinalPathNameByHandle`.
/// Defaults to DOS volume names.
pub const GetFinalPathNameByHandleFormat = struct {
    volume_name: enum {
        /// Format as DOS volume name
        Dos,
        /// Format as NT volume name
        Nt,
    } = .Dos,
};

pub const GetFinalPathNameByHandleError = error{
    AccessDenied,
    FileNotFound,
    NameTooLong,
    /// The volume does not contain a recognized file system. File system
    /// drivers might not be loaded, or the volume may be corrupt.
    UnrecognizedVolume,
} || Io.Cancelable || Io.UnexpectedError;

/// Returns canonical (normalized) path of handle.
/// Use `GetFinalPathNameByHandleFormat` to specify whether the path is meant to include
/// NT or DOS volume name (e.g., `\Device\HarddiskVolume0\foo.txt` versus `C:\foo.txt`).
/// If DOS volume name format is selected, note that this function does *not* prepend
/// `\\?\` prefix to the resultant path.
pub fn GetFinalPathNameByHandle(
    hFile: windows.HANDLE,
    fmt: GetFinalPathNameByHandleFormat,
    out_buffer: []u16,
) GetFinalPathNameByHandleError![]u16 {
    const final_path = QueryObjectName(hFile, out_buffer) catch |err| switch (err) {
        // we assume InvalidHandle is close enough to FileNotFound in semantics
        // to not further complicate the error set
        error.InvalidHandle => return error.FileNotFound,
        else => |e| return e,
    };

    switch (fmt.volume_name) {
        .Nt => {
            // the returned path is already in .Nt format
            return final_path;
        },
        .Dos => {
            // parse the string to separate volume path from file path
            const device_prefix = std.unicode.utf8ToUtf16LeStringLiteral("\\Device\\");

            // We aren't entirely sure of the structure of the path returned by
            // QueryObjectName in all contexts/environments.
            // This code is written to cover the various cases that have
            // been encountered and solved appropriately. But note that there's
            // no easy way to verify that they have all been tackled!
            // (Unless you, the reader knows of one then please do action that!)
            if (!std.mem.startsWith(u16, final_path, device_prefix)) {
                // Wine seems to return NT namespaced paths starting with \??\ from QueryObjectName
                // (e.g. `\??\Z:\some\path\to\a\file.txt`), in which case we can just strip the
                // prefix to turn it into an absolute path.
                // https://github.com/ziglang/zig/issues/26029
                // https://bugs.winehq.org/show_bug.cgi?id=39569
                return windows.ntToWin32Namespace(final_path, out_buffer) catch |err| switch (err) {
                    error.NotNtPath => return error.Unexpected,
                    error.NameTooLong => |e| return e,
                };
            }

            const file_path_begin_index = std.mem.findPos(u16, final_path, device_prefix.len, &[_]u16{'\\'}) orelse unreachable;
            const volume_name_u16 = final_path[0..file_path_begin_index];
            const device_name_u16 = volume_name_u16[device_prefix.len..];
            const file_name_u16 = final_path[file_path_begin_index..];

            // MUP is Multiple UNC Provider, and indicates that the path is a UNC
            // path. In this case, the canonical UNC path can be gotten by just
            // dropping the \Device\Mup\ and making sure the path begins with \\
            if (std.mem.eql(u16, device_name_u16, std.unicode.utf8ToUtf16LeStringLiteral("Mup"))) {
                out_buffer[0] = '\\';
                @memmove(out_buffer[1..][0..file_name_u16.len], file_name_u16);
                return out_buffer[0 .. 1 + file_name_u16.len];
            }

            // Get DOS volume name. DOS volume names are actually symbolic link objects to the
            // actual NT volume. For example:
            // (NT) \Device\HarddiskVolume4 => (DOS) \DosDevices\C: == (DOS) C:
            const MIN_SIZE = @sizeOf(windows.MOUNTMGR_MOUNT_POINT) + windows.MAX_PATH;
            // We initialize the input buffer to all zeros for convenience since
            // `DeviceIoControl` with `IOCTL_MOUNTMGR_QUERY_POINTS` expects this.
            var input_buf: [MIN_SIZE]u8 align(@alignOf(windows.MOUNTMGR_MOUNT_POINT)) = [_]u8{0} ** MIN_SIZE;
            var output_buf: [MIN_SIZE * 4]u8 align(@alignOf(windows.MOUNTMGR_MOUNT_POINTS)) = undefined;

            // This surprising path is a filesystem path to the mount manager on Windows.
            // Source: https://stackoverflow.com/questions/3012828/using-ioctl-mountmgr-query-points
            // This is the NT namespaced version of \\.\MountPointManager
            const mgmt_path_u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\??\\MountPointManager");
            const mgmt_handle = OpenFile(mgmt_path_u16, .{
                .access_mask = .{ .STANDARD = .{ .SYNCHRONIZE = true } },
                .creation = .OPEN,
            }) catch |err| switch (err) {
                error.IsDir => return error.Unexpected,
                error.NotDir => return error.Unexpected,
                error.NoDevice => return error.Unexpected,
                error.AccessDenied => return error.Unexpected,
                error.PipeBusy => return error.Unexpected,
                error.FileBusy => return error.Unexpected,
                error.PathAlreadyExists => return error.Unexpected,
                error.WouldBlock => return error.Unexpected,
                error.NetworkNotFound => return error.Unexpected,
                error.AntivirusInterference => return error.Unexpected,
                error.BadPathName => return error.Unexpected,
                else => |e| return e,
            };
            defer windows.CloseHandle(mgmt_handle);

            var input_struct: *windows.MOUNTMGR_MOUNT_POINT = @ptrCast(&input_buf[0]);
            input_struct.DeviceNameOffset = @sizeOf(windows.MOUNTMGR_MOUNT_POINT);
            input_struct.DeviceNameLength = @intCast(volume_name_u16.len * 2);
            @memcpy(input_buf[@sizeOf(windows.MOUNTMGR_MOUNT_POINT)..][0 .. volume_name_u16.len * 2], @as([*]const u8, @ptrCast(volume_name_u16.ptr)));

            switch ((try deviceIoControl(&.{
                .file = .{ .handle = mgmt_handle, .flags = .{ .nonblocking = false } },
                .code = windows.IOCTL.MOUNTMGR.QUERY_POINTS,
                .in = &input_buf,
                .out = &output_buf,
            })).u.Status) {
                .SUCCESS => {},
                .CANCELLED => unreachable,
                .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
                else => |status| return windows.unexpectedStatus(status),
            }
            const mount_points_struct: *const windows.MOUNTMGR_MOUNT_POINTS = @ptrCast(&output_buf[0]);

            const mount_points = @as(
                [*]const windows.MOUNTMGR_MOUNT_POINT,
                @ptrCast(&mount_points_struct.MountPoints[0]),
            )[0..mount_points_struct.NumberOfMountPoints];

            for (mount_points) |mount_point| {
                const symlink = @as(
                    [*]const u16,
                    @ptrCast(@alignCast(&output_buf[mount_point.SymbolicLinkNameOffset])),
                )[0 .. mount_point.SymbolicLinkNameLength / 2];

                // Look for `\DosDevices\` prefix. We don't really care if there are more than one symlinks
                // with traditional DOS drive letters, so pick the first one available.
                var prefix_buf = std.unicode.utf8ToUtf16LeStringLiteral("\\DosDevices\\");
                const prefix = prefix_buf[0..prefix_buf.len];

                if (std.mem.startsWith(u16, symlink, prefix)) {
                    const drive_letter = symlink[prefix.len..];

                    if (out_buffer.len < drive_letter.len + file_name_u16.len) return error.NameTooLong;

                    @memcpy(out_buffer[0..drive_letter.len], drive_letter);
                    @memmove(out_buffer[drive_letter.len..][0..file_name_u16.len], file_name_u16);
                    const total_len = drive_letter.len + file_name_u16.len;

                    // Validate that DOS does not contain any spurious nul bytes.
                    assert(std.mem.findScalar(u16, out_buffer[0..total_len], 0) == null);

                    return out_buffer[0..total_len];
                } else if (mountmgrIsVolumeName(symlink)) {
                    // If the symlink is a volume GUID like \??\Volume{383da0b0-717f-41b6-8c36-00500992b58d},
                    // then it is a volume mounted as a path rather than a drive letter. We need to
                    // query the mount manager again to get the DOS path for the volume.

                    // 49 is the maximum length accepted by mountmgrIsVolumeName
                    const vol_input_size = @sizeOf(windows.MOUNTMGR_TARGET_NAME) + (49 * 2);
                    var vol_input_buf: [vol_input_size]u8 align(@alignOf(windows.MOUNTMGR_TARGET_NAME)) = [_]u8{0} ** vol_input_size;
                    // Note: If the path exceeds MAX_PATH, the Disk Management GUI doesn't accept the full path,
                    // and instead if must be specified using a shortened form (e.g. C:\FOO~1\BAR~1\<...>).
                    // However, just to be sure we can handle any path length, we use PATH_MAX_WIDE here.
                    const min_output_size = @sizeOf(windows.MOUNTMGR_VOLUME_PATHS) + (windows.PATH_MAX_WIDE * 2);
                    var vol_output_buf: [min_output_size]u8 align(@alignOf(windows.MOUNTMGR_VOLUME_PATHS)) = undefined;

                    var vol_input_struct: *windows.MOUNTMGR_TARGET_NAME = @ptrCast(&vol_input_buf[0]);
                    vol_input_struct.DeviceNameLength = @intCast(symlink.len * 2);
                    @memcpy(@as([*]windows.WCHAR, &vol_input_struct.DeviceName)[0..symlink.len], symlink);

                    switch ((try deviceIoControl(&.{
                        .file = .{ .handle = mgmt_handle, .flags = .{ .nonblocking = true } },
                        .code = windows.IOCTL.MOUNTMGR.QUERY_DOS_VOLUME_PATH,
                        .in = &vol_input_buf,
                        .out = &vol_output_buf,
                    })).u.Status) {
                        .SUCCESS => {},
                        .CANCELLED => unreachable,
                        .UNRECOGNIZED_VOLUME => return error.UnrecognizedVolume,
                        else => |status| return windows.unexpectedStatus(status),
                    }
                    const volume_paths_struct: *const windows.MOUNTMGR_VOLUME_PATHS = @ptrCast(&vol_output_buf[0]);
                    const volume_path = std.mem.sliceTo(@as(
                        [*]const u16,
                        &volume_paths_struct.MultiSz,
                    )[0 .. volume_paths_struct.MultiSzLength / 2], 0);

                    if (out_buffer.len < volume_path.len + file_name_u16.len) return error.NameTooLong;

                    // `out_buffer` currently contains the memory of `file_name_u16`, so it can overlap with where
                    // we want to place the filename before returning. Here are the possible overlapping cases:
                    //
                    // out_buffer:       [filename]
                    //       dest: [___(a)___] [___(b)___]
                    //
                    // In the case of (a), we need to copy forwards, and in the case of (b) we need
                    // to copy backwards. We also need to do this before copying the volume path because
                    // it could overwrite the file_name_u16 memory.
                    const file_name_dest = out_buffer[volume_path.len..][0..file_name_u16.len];
                    @memmove(file_name_dest, file_name_u16);
                    @memcpy(out_buffer[0..volume_path.len], volume_path);
                    const total_len = volume_path.len + file_name_u16.len;

                    // Validate that DOS does not contain any spurious nul bytes.
                    assert(std.mem.findScalar(u16, out_buffer[0..total_len], 0) == null);

                    return out_buffer[0..total_len];
                }
            }

            // If we've ended up here, then something went wrong/is corrupted in the OS,
            // so error out!
            return error.FileNotFound;
        },
    }
}

test GetFinalPathNameByHandle {
    if (builtin.os.tag != .windows)
        return;

    //any file will do
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const handle = tmp.dir.handle;
    var buffer: [windows.PATH_MAX_WIDE]u16 = undefined;

    //check with sufficient size
    const nt_path = try GetFinalPathNameByHandle(handle, .{ .volume_name = .Nt }, &buffer);
    _ = try GetFinalPathNameByHandle(handle, .{ .volume_name = .Dos }, &buffer);

    const required_len_in_u16 = nt_path.len + @divExact(@intFromPtr(nt_path.ptr) - @intFromPtr(&buffer), 2) + 1;
    //check with insufficient size
    try std.testing.expectError(error.NameTooLong, GetFinalPathNameByHandle(handle, .{ .volume_name = .Nt }, buffer[0 .. required_len_in_u16 - 1]));
    try std.testing.expectError(error.NameTooLong, GetFinalPathNameByHandle(handle, .{ .volume_name = .Dos }, buffer[0 .. required_len_in_u16 - 1]));

    //check with exactly-sufficient size
    _ = try GetFinalPathNameByHandle(handle, .{ .volume_name = .Nt }, buffer[0..required_len_in_u16]);
    _ = try GetFinalPathNameByHandle(handle, .{ .volume_name = .Dos }, buffer[0..required_len_in_u16]);
}

/// Equivalent to the MOUNTMGR_IS_VOLUME_NAME macro in mountmgr.h
fn mountmgrIsVolumeName(name: []const u16) bool {
    return (name.len == 48 or (name.len == 49 and name[48] == std.mem.nativeToLittle(u16, '\\'))) and
        name[0] == std.mem.nativeToLittle(u16, '\\') and
        (name[1] == std.mem.nativeToLittle(u16, '?') or name[1] == std.mem.nativeToLittle(u16, '\\')) and
        name[2] == std.mem.nativeToLittle(u16, '?') and
        name[3] == std.mem.nativeToLittle(u16, '\\') and
        std.mem.startsWith(u16, name[4..], std.unicode.utf8ToUtf16LeStringLiteral("Volume{")) and
        name[19] == std.mem.nativeToLittle(u16, '-') and
        name[24] == std.mem.nativeToLittle(u16, '-') and
        name[29] == std.mem.nativeToLittle(u16, '-') and
        name[34] == std.mem.nativeToLittle(u16, '-') and
        name[47] == std.mem.nativeToLittle(u16, '}');
}

test mountmgrIsVolumeName {
    @setEvalBranchQuota(2000);
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    try std.testing.expect(mountmgrIsVolumeName(L("\\\\?\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}")));
    try std.testing.expect(mountmgrIsVolumeName(L("\\??\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}")));
    try std.testing.expect(mountmgrIsVolumeName(L("\\\\?\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}\\")));
    try std.testing.expect(mountmgrIsVolumeName(L("\\??\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}\\")));
    try std.testing.expect(!mountmgrIsVolumeName(L("\\\\.\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}")));
    try std.testing.expect(!mountmgrIsVolumeName(L("\\??\\Volume{383da0b0-717f-41b6-8c36-00500992b58d}\\foo")));
    try std.testing.expect(!mountmgrIsVolumeName(L("\\??\\Volume{383da0b0-717f-41b6-8c36-00500992b58}")));
}

pub const QueryObjectNameError = error{
    AccessDenied,
    InvalidHandle,
    NameTooLong,
    Unexpected,
};

pub fn QueryObjectName(handle: windows.HANDLE, out_buffer: []u16) QueryObjectNameError![]u16 {
    const out_buffer_aligned = std.mem.alignInSlice(out_buffer, @alignOf(windows.OBJECT.NAME_INFORMATION)) orelse return error.NameTooLong;

    const info: *windows.OBJECT.NAME_INFORMATION = @ptrCast(out_buffer_aligned);
    // buffer size is specified in bytes
    const out_buffer_len = std.math.cast(windows.ULONG, out_buffer_aligned.len * 2) orelse std.math.maxInt(windows.ULONG);
    // last argument would return the length required for full_buffer, not exposed here
    return switch (windows.ntdll.NtQueryObject(handle, .Name, info, out_buffer_len, null)) {
        .SUCCESS => {
            // info.Name from ObQueryNameString is documented to be empty if the object
            // was "unnamed", not sure if this can happen for file handles
            return if (info.Name.isEmpty()) error.Unexpected else info.Name.slice();
        },
        .ACCESS_DENIED => error.AccessDenied,
        .INVALID_HANDLE => error.InvalidHandle,
        // triggered when the buffer is too small for the OBJECT_NAME_INFORMATION object (.INFO_LENGTH_MISMATCH),
        // or if the buffer is too small for the file path returned (.BUFFER_OVERFLOW, .BUFFER_TOO_SMALL)
        .INFO_LENGTH_MISMATCH, .BUFFER_OVERFLOW, .BUFFER_TOO_SMALL => error.NameTooLong,
        else => |e| windows.unexpectedStatus(e),
    };
}

test QueryObjectName {
    if (builtin.os.tag != .windows)
        return;

    //any file will do; canonicalization works on NTFS junctions and symlinks, hardlinks remain separate paths.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const handle = tmp.dir.handle;
    var out_buffer: [windows.PATH_MAX_WIDE]u16 = undefined;

    const result_path = try QueryObjectName(handle, &out_buffer);
    const required_len_in_u16 = result_path.len + @divExact(@intFromPtr(result_path.ptr) - @intFromPtr(&out_buffer), 2) + 1;
    //insufficient size
    try std.testing.expectError(error.NameTooLong, QueryObjectName(handle, out_buffer[0 .. required_len_in_u16 - 1]));
    //exactly-sufficient size
    _ = try QueryObjectName(handle, out_buffer[0..required_len_in_u16]);
}

const Wtf16ToPrefixedFileWError = error{
    AccessDenied,
    FileNotFound,
} || Dir.PathNameError || Io.Cancelable || Io.UnexpectedError;

const Wtf16ToPrefixedFileWOptions = struct {
    allow_relative: bool = true,
};

/// Converts the `path` to WTF16, null-terminated. If the path contains any
/// namespace prefix, or is anything but a relative path (rooted, drive relative,
/// etc) the result will have the NT-style prefix `\??\`.
///
/// Similar to RtlDosPathNameToNtPathName_U with a few differences:
/// - Does not allocate on the heap.
/// - Relative paths are kept as relative unless they contain too many ..
///   components, in which case they are resolved against the `dir` if it
///   is non-null, or the CWD if it is null.
/// - Special case device names like COM1, NUL, etc are not handled specially (TODO)
/// - . and space are not stripped from the end of relative paths (potential TODO)
pub fn wToPrefixedFileW(dir: ?windows.HANDLE, path: [:0]const u16, options: Wtf16ToPrefixedFileWOptions) Wtf16ToPrefixedFileWError!WindowsPathSpace {
    const nt_prefix = [_]u16{ '\\', '?', '?', '\\' };
    if (windows.hasCommonNtPrefix(u16, path)) {
        // TODO: Figure out a way to design an API that can avoid the copy for NT,
        //       since it is always returned fully unmodified.
        var path_space: WindowsPathSpace = undefined;
        path_space.data[0..nt_prefix.len].* = nt_prefix;
        const len_after_prefix = path.len - nt_prefix.len;
        @memcpy(path_space.data[nt_prefix.len..][0..len_after_prefix], path[nt_prefix.len..]);
        path_space.len = path.len;
        path_space.data[path_space.len] = 0;
        return path_space;
    } else {
        const path_type = Dir.path.getWin32PathType(u16, path);
        var path_space: WindowsPathSpace = undefined;
        if (path_type == .local_device) switch (getLocalDevicePathType(u16, path)) {
            .verbatim => {
                path_space.data[0..nt_prefix.len].* = nt_prefix;
                const len_after_prefix = path.len - nt_prefix.len;
                @memcpy(path_space.data[nt_prefix.len..][0..len_after_prefix], path[nt_prefix.len..]);
                path_space.len = path.len;
                path_space.data[path_space.len] = 0;
                return path_space;
            },
            .local_device, .fake_verbatim => {
                const path_byte_len = windows.ntdll.RtlGetFullPathName_U(
                    path.ptr,
                    path_space.data.len * 2,
                    &path_space.data,
                    null,
                );
                if (path_byte_len == 0) {
                    // TODO: This may not be the right error
                    return error.BadPathName;
                } else if (path_byte_len / 2 > path_space.data.len) {
                    return error.NameTooLong;
                }
                path_space.len = path_byte_len / 2;
                // Both prefixes will be normalized but retained, so all
                // we need to do now is replace them with the NT prefix
                path_space.data[0..nt_prefix.len].* = nt_prefix;
                return path_space;
            },
        };
        if (options.allow_relative and path_type == .relative) relative: {
            // TODO: Handle special case device names like COM1, AUX, NUL, CONIN$, CONOUT$, etc.
            //       See https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html

            // TODO: Potentially strip all trailing . and space characters from the
            //       end of the path. This is something that both RtlDosPathNameToNtPathName_U
            //       and RtlGetFullPathName_U do. Technically, trailing . and spaces
            //       are allowed, but such paths may not interact well with Windows (i.e.
            //       files with these paths can't be deleted from explorer.exe, etc).
            //       This could be something that normalizePath may want to do.

            @memcpy(path_space.data[0..path.len], path);
            // Try to normalize, but if we get too many parent directories,
            // then we need to start over and use RtlGetFullPathName_U instead.
            path_space.len = windows.normalizePath(u16, path_space.data[0..path.len]) catch |err| switch (err) {
                error.TooManyParentDirs => break :relative,
            };
            path_space.data[path_space.len] = 0;
            return path_space;
        }
        // We now know we are going to return an absolute NT path, so
        // we can unconditionally prefix it with the NT prefix.
        path_space.data[0..nt_prefix.len].* = nt_prefix;
        if (path_type == .root_local_device) {
            // `\\.` and `\\?` always get converted to `\??\` exactly, so
            // we can just stop here
            path_space.len = nt_prefix.len;
            path_space.data[path_space.len] = 0;
            return path_space;
        }
        const path_buf_offset = switch (path_type) {
            // UNC paths will always start with `\\`. However, we want to
            // end up with something like `\??\UNC\server\share`, so to get
            // RtlGetFullPathName to write into the spot we want the `server`
            // part to end up, we need to provide an offset such that
            // the `\\` part gets written where the `C\` of `UNC\` will be
            // in the final NT path.
            .unc_absolute => nt_prefix.len + 2,
            else => nt_prefix.len,
        };
        const buf_len: u32 = @intCast(path_space.data.len - path_buf_offset);
        const path_to_get: [:0]const u16 = path_to_get: {
            // If dir is null, then we don't need to bother with GetFinalPathNameByHandle because
            // RtlGetFullPathName_U will resolve relative paths against the CWD for us.
            if (path_type != .relative or dir == null) {
                break :path_to_get path;
            }
            // We can also skip GetFinalPathNameByHandle if the handle matches
            // the handle returned by Io.Dir.cwd()
            if (dir.? == Io.Dir.cwd().handle) {
                break :path_to_get path;
            }
            // At this point, we know we have a relative path that had too many
            // `..` components to be resolved by normalizePath, so we need to
            // convert it into an absolute path and let RtlGetFullPathName_U
            // canonicalize it. We do this by getting the path of the `dir`
            // and appending the relative path to it.
            var dir_path_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
            const dir_path = GetFinalPathNameByHandle(dir.?, .{}, &dir_path_buf) catch |err| switch (err) {
                // This mapping is not correct; it is actually expected
                // that calling GetFinalPathNameByHandle might return
                // error.UnrecognizedVolume, and in fact has been observed
                // in the wild. The problem is that wToPrefixedFileW was
                // never intended to make *any* OS syscall APIs. It's only
                // supposed to convert a string to one that is eligible to
                // be used in the ntdll syscalls.
                //
                // To solve this, this function needs to no longer call
                // GetFinalPathNameByHandle under any conditions, or the
                // calling function needs to get reworked to not need to
                // call this function.
                //
                // This may involve making breaking API changes.
                error.UnrecognizedVolume => return error.Unexpected,
                else => |e| return e,
            };
            if (dir_path.len + 1 + path.len > windows.PATH_MAX_WIDE) {
                return error.NameTooLong;
            }
            // We don't have to worry about potentially doubling up path separators
            // here since RtlGetFullPathName_U will handle canonicalizing it.
            dir_path_buf[dir_path.len] = '\\';
            @memcpy(dir_path_buf[dir_path.len + 1 ..][0..path.len], path);
            const full_len = dir_path.len + 1 + path.len;
            dir_path_buf[full_len] = 0;
            break :path_to_get dir_path_buf[0..full_len :0];
        };
        const path_byte_len = windows.ntdll.RtlGetFullPathName_U(
            path_to_get.ptr,
            buf_len * 2,
            path_space.data[path_buf_offset..].ptr,
            null,
        );
        if (path_byte_len == 0) {
            // TODO: This may not be the right error
            return error.BadPathName;
        } else if (path_byte_len / 2 > buf_len) {
            return error.NameTooLong;
        }
        path_space.len = path_buf_offset + (path_byte_len / 2);
        if (path_type == .unc_absolute) {
            // Now add in the UNC, the `C` should overwrite the first `\` of the
            // FullPathName, ultimately resulting in `\??\UNC\<the rest of the path>`
            assert(path_space.data[path_buf_offset] == '\\');
            assert(path_space.data[path_buf_offset + 1] == '\\');
            const unc = [_]u16{ 'U', 'N', 'C' };
            path_space.data[nt_prefix.len..][0..unc.len].* = unc;
        }
        return path_space;
    }
}

const LocalDevicePathType = enum {
    /// `\\.\` (path separators can be `\` or `/`)
    local_device,
    /// `\\?\`
    /// When converted to an NT path, everything past the prefix is left
    /// untouched and `\\?\` is replaced by `\??\`.
    verbatim,
    /// `\\?\` without all path separators being `\`.
    /// This seems to be recognized as a prefix, but the 'verbatim' aspect
    /// is not respected (i.e. if `//?/C:/foo` is converted to an NT path,
    /// it will become `\??\C:\foo` [it will be canonicalized and the //?/ won't
    /// be treated as part of the final path])
    fake_verbatim,
};

/// Only relevant for Win32 -> NT path conversion.
/// Asserts `path` is of type `Dir.path.Win32PathType.local_device`.
fn getLocalDevicePathType(comptime T: type, path: []const T) LocalDevicePathType {
    if (std.debug.runtime_safety) {
        assert(Dir.path.getWin32PathType(T, path) == .local_device);
    }

    const backslash = std.mem.nativeToLittle(T, '\\');
    const all_backslash = path[0] == backslash and
        path[1] == backslash and
        path[3] == backslash;
    return switch (path[2]) {
        std.mem.nativeToLittle(T, '?') => if (all_backslash) .verbatim else .fake_verbatim,
        std.mem.nativeToLittle(T, '.') => .local_device,
        else => unreachable,
    };
}

pub const Wtf8ToPrefixedFileWError = Wtf16ToPrefixedFileWError;

/// Same as `wToPrefixedFileW` but accepts a WTF-8 encoded path.
/// https://wtf-8.codeberg.page/
pub fn sliceToPrefixedFileW(dir: ?windows.HANDLE, path: []const u8, options: Wtf16ToPrefixedFileWOptions) Wtf8ToPrefixedFileWError!WindowsPathSpace {
    var temp_path: WindowsPathSpace = undefined;
    temp_path.len = std.unicode.wtf8ToWtf16Le(&temp_path.data, path) catch |err| switch (err) {
        error.InvalidWtf8 => return error.BadPathName,
    };
    temp_path.data[temp_path.len] = 0;
    return wToPrefixedFileW(dir, temp_path.span(), options);
}

pub const WindowsPathSpace = struct {
    data: [windows.PATH_MAX_WIDE:0]u16,
    len: usize,

    pub fn span(wps: *const WindowsPathSpace) [:0]const u16 {
        return wps.data[0..wps.len :0];
    }

    pub fn string(wps: *const WindowsPathSpace) windows.UNICODE_STRING {
        return .init(wps.span());
    }
};

fn dirRealPathFilePosix(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, out_buffer: []u8) Dir.RealPathFileError!usize {
    if (native_os == .wasi) return error.OperationUnsupported;

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    if (builtin.link_libc and dir.handle == posix.AT.FDCWD) {
        if (out_buffer.len < posix.PATH_MAX) return error.NameTooLong;
        const syscall: Syscall = try .start();
        while (true) {
            if (std.c.realpath(sub_path_posix, out_buffer.ptr)) |redundant_pointer| {
                syscall.finish();
                assert(redundant_pointer == out_buffer.ptr);
                return std.mem.indexOfScalar(u8, out_buffer, 0) orelse out_buffer.len;
            }
            const err: posix.E = @enumFromInt(std.c._errno().*);
            if (err == .INTR) {
                try syscall.checkCancel();
                continue;
            }
            syscall.finish();
            switch (err) {
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
                else => return posix.unexpectedErrno(err),
            }
        }
    }

    var flags: posix.O = .{};
    if (@hasField(posix.O, "NONBLOCK")) flags.NONBLOCK = true;
    if (@hasField(posix.O, "CLOEXEC")) flags.CLOEXEC = true;
    if (@hasField(posix.O, "PATH")) flags.PATH = true;

    const mode: posix.mode_t = 0;

    const syscall: Syscall = try .start();
    const fd: posix.fd_t = while (true) {
        const rc = openat_sym(dir.handle, sub_path_posix, flags, mode);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                break @intCast(rc);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    .SRCH => return error.FileNotFound, // Linux when accessing procfs.
                    .NOMEM => return error.SystemResources,
                    .NOSPC => return error.NoSpaceLeft,
                    .NOTDIR => return error.NotDir,
                    .PERM => return error.PermissionDenied,
                    .EXIST => return error.PathAlreadyExists,
                    .BUSY => return error.DeviceBusy,
                    .NXIO => return error.NoDevice,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    };
    defer closeFd(fd);
    return realPathPosix(fd, out_buffer);
}

const dirRealPath = switch (native_os) {
    .windows => dirRealPathWindows,
    else => dirRealPathPosix,
};

fn dirRealPathPosix(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    if (native_os == .wasi) return error.OperationUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return realPathPosix(dir.handle, out_buffer);
}

fn dirRealPathWindows(userdata: ?*anyopaque, dir: Dir, out_buffer: []u8) Dir.RealPathError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return realPathWindows(dir.handle, out_buffer);
}

const fileRealPath = switch (native_os) {
    .windows => fileRealPathWindows,
    else => fileRealPathPosix,
};

fn fileRealPathWindows(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    if (native_os == .wasi) return error.OperationUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return realPathWindows(file.handle, out_buffer);
}

fn fileRealPathPosix(userdata: ?*anyopaque, file: File, out_buffer: []u8) File.RealPathError!usize {
    if (native_os == .wasi) return error.OperationUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return realPathPosix(file.handle, out_buffer);
}

fn realPathPosix(fd: posix.fd_t, out_buffer: []u8) File.RealPathError!usize {
    switch (native_os) {
        .dragonfly, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
            var sufficient_buffer: [posix.PATH_MAX]u8 = undefined;
            @memset(&sufficient_buffer, 0);
            const syscall: Syscall = try .start();
            while (true) {
                switch (posix.errno(posix.system.fcntl(fd, posix.F.GETPATH, &sufficient_buffer))) {
                    .SUCCESS => {
                        syscall.finish();
                        break;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .ACCES => return error.AccessDenied,
                            .BADF => return error.FileNotFound,
                            .NOENT => return error.FileNotFound,
                            .NOMEM => return error.SystemResources,
                            .NOSPC => return error.NameTooLong,
                            .RANGE => return error.NameTooLong,
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            }
            const n = std.mem.indexOfScalar(u8, &sufficient_buffer, 0) orelse sufficient_buffer.len;
            if (n > out_buffer.len) return error.NameTooLong;
            @memcpy(out_buffer[0..n], sufficient_buffer[0..n]);
            return n;
        },
        .linux, .serenity, .illumos => {
            var procfs_buf: ["/proc/self/path/-2147483648\x00".len]u8 = undefined;
            const template = if (native_os == .illumos) "/proc/self/path/{d}" else "/proc/self/fd/{d}";
            const proc_path = std.fmt.bufPrintSentinel(&procfs_buf, template, .{fd}, 0) catch unreachable;
            const syscall: Syscall = try .start();
            while (true) {
                const rc = posix.system.readlink(proc_path, out_buffer.ptr, out_buffer.len);
                switch (posix.errno(rc)) {
                    .SUCCESS => {
                        syscall.finish();
                        const len: usize = @bitCast(rc);
                        return len;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        switch (e) {
                            .ACCES => return error.AccessDenied,
                            .FAULT => |err| return errnoBug(err),
                            .IO => return error.FileSystem,
                            .LOOP => return error.SymLinkLoop,
                            .NAMETOOLONG => return error.NameTooLong,
                            .NOENT => return error.FileNotFound,
                            .NOMEM => return error.SystemResources,
                            .NOTDIR => return error.NotDir,
                            .ILSEQ => |err| return errnoBug(err),
                            else => |err| return posix.unexpectedErrno(err),
                        }
                    },
                }
            }
        },
        .freebsd => {
            var k_file: std.c.kinfo_file = undefined;
            k_file.structsize = std.c.KINFO_FILE_SIZE;
            const syscall: Syscall = try .start();
            while (true) {
                switch (posix.errno(std.c.fcntl(fd, std.c.F.KINFO, @intFromPtr(&k_file)))) {
                    .SUCCESS => {
                        syscall.finish();
                        break;
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    .BADF => {
                        syscall.finish();
                        return error.FileNotFound;
                    },
                    else => |err| {
                        syscall.finish();
                        return posix.unexpectedErrno(err);
                    },
                }
            }
            const len = std.mem.findScalar(u8, &k_file.path, 0) orelse k_file.path.len;
            if (len == 0) return error.NameTooLong;
            @memcpy(out_buffer[0..len], k_file.path[0..len]);
            return len;
        },
        else => return error.OperationUnsupported,
    }
    comptime unreachable;
}

fn fileHardLink(
    userdata: ?*anyopaque,
    file: File,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: File.HardLinkOptions,
) File.HardLinkError!void {
    _ = userdata;
    if (native_os != .linux) return error.OperationUnsupported;

    var new_path_buffer: [posix.PATH_MAX]u8 = undefined;
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    const flags: u32 = if (options.follow_symlinks)
        posix.AT.SYMLINK_FOLLOW | posix.AT.EMPTY_PATH
    else
        posix.AT.EMPTY_PATH;

    return linkat(file.handle, "", new_dir.handle, new_sub_path_posix, flags) catch |err| switch (err) {
        error.FileNotFound => {
            if (options.follow_symlinks) return error.FileNotFound;
            var proc_buf: ["/proc/self/fd/-2147483648\x00".len]u8 = undefined;
            const proc_path = std.fmt.bufPrintSentinel(&proc_buf, "/proc/self/fd/{d}", .{file.handle}, 0) catch
                unreachable;
            return linkat(posix.AT.FDCWD, proc_path, new_dir.handle, new_sub_path_posix, posix.AT.SYMLINK_FOLLOW);
        },
        else => |e| return e,
    };
}

fn linkat(
    old_dir: posix.fd_t,
    old_path: [*:0]const u8,
    new_dir: posix.fd_t,
    new_path: [*:0]const u8,
    flags: u32,
) File.HardLinkError!void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.linkat(old_dir, old_path, new_dir, new_path, flags))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ACCES => return syscall.fail(error.AccessDenied),
            .DQUOT => return syscall.fail(error.DiskQuota),
            .EXIST => return syscall.fail(error.PathAlreadyExists),
            .IO => return syscall.fail(error.HardwareFailure),
            .LOOP => return syscall.fail(error.SymLinkLoop),
            .MLINK => return syscall.fail(error.LinkQuotaExceeded),
            .NAMETOOLONG => return syscall.fail(error.NameTooLong),
            .NOENT => return syscall.fail(error.FileNotFound),
            .NOMEM => return syscall.fail(error.SystemResources),
            .NOSPC => return syscall.fail(error.NoSpaceLeft),
            .NOTDIR => return syscall.fail(error.NotDir),
            .PERM => return syscall.fail(error.PermissionDenied),
            .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
            .XDEV => return syscall.fail(error.CrossDevice),
            .ILSEQ => return syscall.fail(error.BadPathName),
            .FAULT => |err| return syscall.errnoBug(err),
            .INVAL => |err| return syscall.errnoBug(err),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

const dirDeleteFile = switch (native_os) {
    .windows => dirDeleteFileWindows,
    .wasi => dirDeleteFileWasi,
    else => dirDeleteFilePosix,
};

fn dirDeleteFileWindows(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    return dirDeleteWindows(userdata, dir, sub_path, false) catch |err| switch (err) {
        error.DirNotEmpty => unreachable,
        else => |e| return e,
    };
}

fn dirDeleteFileWasi(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    if (builtin.link_libc) return dirDeleteFilePosix(userdata, dir, sub_path);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const syscall: Syscall = try .start();
    while (true) {
        const res = std.os.wasi.path_unlink_file(dir.handle, sub_path.ptr, sub_path.len);
        switch (res) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .PERM => return error.PermissionDenied,
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    .INVAL => |err| return errnoBug(err), // invalid flags, or pathname has . as last component
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirDeleteFilePosix(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.unlinkat(dir.handle, sub_path_posix, 0))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            // Some systems return permission errors when trying to delete a
            // directory, so we need to handle that case specifically and
            // translate the error.
            .PERM => switch (native_os) {
                .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .netbsd, .dragonfly, .openbsd, .illumos => {

                    // Don't follow symlinks to match unlinkat (which acts on symlinks rather than follows them).
                    var st = std.mem.zeroes(posix.Stat);
                    while (true) {
                        try syscall.checkCancel();
                        switch (posix.errno(fstatat_sym(dir.handle, sub_path_posix, &st, posix.AT.SYMLINK_NOFOLLOW))) {
                            .SUCCESS => {
                                syscall.finish();
                                break;
                            },
                            .INTR => continue,
                            else => {
                                syscall.finish();
                                return error.PermissionDenied;
                            },
                        }
                    }
                    const is_dir = st.mode & posix.S.IFMT == posix.S.IFDIR;
                    if (is_dir)
                        return error.IsDir
                    else
                        return error.PermissionDenied;
                },
                else => {
                    syscall.finish();
                    return error.PermissionDenied;
                },
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirDeleteDir = switch (native_os) {
    .windows => dirDeleteDirWindows,
    .wasi => dirDeleteDirWasi,
    else => dirDeleteDirPosix,
};

fn dirDeleteDirWindows(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    return dirDeleteWindows(userdata, dir, sub_path, true) catch |err| switch (err) {
        error.IsDir => unreachable,
        else => |e| return e,
    };
}

fn dirDeleteWindows(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, remove_dir: bool) (Dir.DeleteDirError || Dir.DeleteFileError)!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const w = windows;

    if (std.mem.eql(u8, sub_path, "..")) {
        // Can't remove the parent directory with an open handle.
        return error.FileBusy;
    }
    var sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    if (std.mem.eql(u8, sub_path, ".")) {
        // Windows does not recognize this, but it does work with empty string.
        sub_path_w.len = 0;
    }
    const attr: w.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .ObjectName = @constCast(&sub_path_w.string()),
    };

    var io_status_block: w.IO_STATUS_BLOCK = undefined;
    var tmp_handle: w.HANDLE = undefined;
    {
        const syscall: Syscall = try .start();
        while (true) switch (w.ntdll.NtCreateFile(
            &tmp_handle,
            .{ .STANDARD = .{
                .RIGHTS = .{ .DELETE = true },
                .SYNCHRONIZE = true,
            } },
            &attr,
            &io_status_block,
            null,
            .{},
            .VALID_FLAGS,
            .OPEN,
            .{
                .DIRECTORY_FILE = remove_dir,
                .IO = .SYNCHRONOUS_NONALERT,
                .NON_DIRECTORY_FILE = !remove_dir,
                .OPEN_REPARSE_POINT = true, // would we ever want to delete the target instead?
            },
            null,
            0,
        )) {
            .SUCCESS => break syscall.finish(),
            .OBJECT_NAME_INVALID => |err| return syscall.ntstatusBug(err),
            .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
            .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
            .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
            .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            .SHARING_VIOLATION => return syscall.fail(error.FileBusy),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .DELETE_PENDING => return syscall.finish(),
            else => |rc| return syscall.unexpectedNtstatus(rc),
        };
    }
    defer w.CloseHandle(tmp_handle);

    // FileDispositionInformationEx has varying levels of support:
    // - FILE_DISPOSITION_INFORMATION_EX requires >= win10_rs1
    //   (INVALID_INFO_CLASS is returned if not supported)
    // - Requires the NTFS filesystem
    //   (on filesystems like FAT32, INVALID_PARAMETER is returned)
    // - FILE_DISPOSITION_POSIX_SEMANTICS requires >= win10_rs1
    // - FILE_DISPOSITION_IGNORE_READONLY_ATTRIBUTE requires >= win10_rs5
    //   (NOT_SUPPORTED is returned if a flag is unsupported)
    //
    // The strategy here is just to try using FileDispositionInformationEx and fall back to
    // FileDispositionInformation if the return value lets us know that some aspect of it is not supported.
    const rc = rc: {
        // Deletion with posix semantics if the filesystem supports it.
        var info: w.FILE.DISPOSITION.INFORMATION.EX = .{ .Flags = .{
            .DELETE = true,
            .POSIX_SEMANTICS = true,
            .IGNORE_READONLY_ATTRIBUTE = true,
        } };

        const syscall: Syscall = try .start();
        while (true) switch (w.ntdll.NtSetInformationFile(
            tmp_handle,
            &io_status_block,
            &info,
            @sizeOf(w.FILE.DISPOSITION.INFORMATION.EX),
            .DispositionEx,
        )) {
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            // The filesystem does not support FileDispositionInformationEx
            .INVALID_PARAMETER,
            // The operating system does not support FileDispositionInformationEx
            .INVALID_INFO_CLASS,
            // The operating system does not support one of the flags
            .NOT_SUPPORTED,
            => break, // use fallback path below; `syscall` still active

            // For all other statuses, fall down to the switch below to handle them.
            else => |rc| {
                syscall.finish();
                break :rc rc;
            },
        };

        // Deletion with file pending semantics, which requires waiting or moving
        // files to get them removed (from here).
        var file_dispo: w.FILE.DISPOSITION.INFORMATION = .{ .DeleteFile = .TRUE };

        while (true) switch (w.ntdll.NtSetInformationFile(
            tmp_handle,
            &io_status_block,
            &file_dispo,
            @sizeOf(w.FILE.DISPOSITION.INFORMATION),
            .Disposition,
        )) {
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => |rc| {
                syscall.finish();
                break :rc rc;
            },
        };
    };
    switch (rc) {
        .SUCCESS => {},
        .DIRECTORY_NOT_EMPTY => return error.DirNotEmpty,
        .INVALID_PARAMETER => |err| return w.statusBug(err),
        .CANNOT_DELETE => return error.AccessDenied,
        .MEDIA_WRITE_PROTECTED => return error.AccessDenied,
        .ACCESS_DENIED => return error.AccessDenied,
        else => return w.unexpectedStatus(rc),
    }
}

fn dirDeleteDirWasi(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    if (builtin.link_libc) return dirDeleteDirPosix(userdata, dir, sub_path);

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const syscall: Syscall = try .start();
    while (true) {
        const res = std.os.wasi.path_remove_directory(dir.handle, sub_path.ptr, sub_path.len);
        switch (res) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .PERM => return error.PermissionDenied,
                    .BUSY => return error.FileBusy,
                    .FAULT => |err| return errnoBug(err),
                    .IO => return error.FileSystem,
                    .LOOP => return error.SymLinkLoop,
                    .NAMETOOLONG => return error.NameTooLong,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.NotDir,
                    .NOMEM => return error.SystemResources,
                    .ROFS => return error.ReadOnlyFileSystem,
                    .NOTEMPTY => return error.DirNotEmpty,
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    .INVAL => |err| return errnoBug(err), // invalid flags, or pathname has . as last component
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirDeleteDirPosix(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.unlinkat(dir.handle, sub_path_posix, posix.AT.REMOVEDIR))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirRename = switch (native_os) {
    .windows => dirRenameWindows,
    .wasi => dirRenameWasi,
    else => dirRenamePosix,
};

fn dirRenameWindows(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return dirRenameWindowsInner(old_dir, old_sub_path, new_dir, new_sub_path, true) catch |err| switch (err) {
        error.PathAlreadyExists => return error.Unexpected,
        error.OperationUnsupported => return error.Unexpected,
        else => |e| return e,
    };
}

fn dirRenamePreserve(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (is_windows) return dirRenameWindowsInner(old_dir, old_sub_path, new_dir, new_sub_path, false);
    if (native_os == .linux) return dirRenamePreserveLinux(old_dir, old_sub_path, new_dir, new_sub_path);
    // Make a hard link then delete the original.
    try dirHardLink(t, old_dir, old_sub_path, new_dir, new_sub_path, .{ .follow_symlinks = false });
    const prev = swapCancelProtection(t, .blocked);
    defer _ = swapCancelProtection(t, prev);
    dirDeleteFile(t, old_dir, old_sub_path) catch {};
}

fn dirRenameWindowsInner(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    replace_if_exists: bool,
) Dir.RenamePreserveError!void {
    const w = windows;
    const old_path_w_buf = try sliceToPrefixedFileW(old_dir.handle, old_sub_path, .{});
    const old_path_w = old_path_w_buf.span();
    const new_path_w_buf = try sliceToPrefixedFileW(new_dir.handle, new_sub_path, .{});
    const new_path_w = new_path_w_buf.span();

    const src_fd = src_fd: {
        if (OpenFile(old_path_w, .{
            .dir = old_dir.handle,
            .access_mask = .{
                .GENERIC = .{ .WRITE = true },
                .STANDARD = .{
                    .RIGHTS = .{ .DELETE = true },
                    .SYNCHRONIZE = true,
                },
            },
            .creation = .OPEN,
            .filter = .any, // This function is supposed to rename both files and directories.
            .follow_symlinks = false,
        })) |handle| {
            break :src_fd handle;
        } else |err| switch (err) {
            error.WouldBlock => unreachable, // Not possible without `.share_access_nonblocking = true`.
            else => |e| return e,
        }
    };
    defer w.CloseHandle(src_fd);

    var rc: w.NTSTATUS = undefined;
    // FileRenameInformationEx has varying levels of support:
    // - FILE_RENAME_INFORMATION_EX requires >= win10_rs1
    //   (INVALID_INFO_CLASS is returned if not supported)
    // - Requires the NTFS filesystem
    //   (on filesystems like FAT32, INVALID_PARAMETER is returned)
    // - FILE_RENAME_POSIX_SEMANTICS requires >= win10_rs1
    // - FILE_RENAME_IGNORE_READONLY_ATTRIBUTE requires >= win10_rs5
    //   (NOT_SUPPORTED is returned if a flag is unsupported)
    //
    // The strategy here is just to try using FileRenameInformationEx and fall back to
    // FileRenameInformation if the return value lets us know that some aspect of it is not supported.
    const need_fallback = need_fallback: {
        var rename_info: w.FILE.RENAME_INFORMATION = .init(.{
            .Flags = .{
                .REPLACE_IF_EXISTS = replace_if_exists,
                .POSIX_SEMANTICS = true,
                .IGNORE_READONLY_ATTRIBUTE = true,
            },
            .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(new_path_w)) null else new_dir.handle,
            .FileName = new_path_w,
        });
        var io_status_block: w.IO_STATUS_BLOCK = undefined;
        const rename_info_buf = rename_info.toBuffer();
        rc = w.ntdll.NtSetInformationFile(
            src_fd,
            &io_status_block,
            rename_info_buf.ptr,
            @intCast(rename_info_buf.len),
            .RenameEx,
        );
        switch (rc) {
            .SUCCESS => return,
            // The filesystem does not support FileDispositionInformationEx
            .INVALID_PARAMETER,
            // The operating system does not support FileDispositionInformationEx
            .INVALID_INFO_CLASS,
            // The operating system does not support one of the flags
            .NOT_SUPPORTED,
            => break :need_fallback true,
            // For all other statuses, fall down to the switch below to handle them.
            else => break :need_fallback false,
        }
    };

    if (need_fallback) {
        var rename_info: w.FILE.RENAME_INFORMATION = .init(.{
            .Flags = .{ .REPLACE_IF_EXISTS = replace_if_exists },
            .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(new_path_w)) null else new_dir.handle,
            .FileName = new_path_w,
        });
        var io_status_block: w.IO_STATUS_BLOCK = undefined;
        const rename_info_buf = rename_info.toBuffer();
        rc = w.ntdll.NtSetInformationFile(
            src_fd,
            &io_status_block,
            rename_info_buf.ptr,
            @intCast(rename_info_buf.len),
            .Rename,
        );
    }

    switch (rc) {
        .SUCCESS => {},
        .INVALID_HANDLE => |err| return w.statusBug(err),
        .INVALID_PARAMETER => |err| return w.statusBug(err),
        .OBJECT_PATH_SYNTAX_BAD => |err| return w.statusBug(err),
        .ACCESS_DENIED => return error.AccessDenied,
        .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
        .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
        .NOT_SAME_DEVICE => return error.CrossDevice,
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        .DIRECTORY_NOT_EMPTY => return error.DirNotEmpty,
        .FILE_IS_A_DIRECTORY => return error.IsDir,
        .NOT_A_DIRECTORY => return error.NotDir,
        else => return w.unexpectedStatus(rc),
    }
}

fn dirRenameWasi(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    if (builtin.link_libc) return dirRenamePosix(userdata, old_dir, old_sub_path, new_dir, new_sub_path);

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.wasi.path_rename(old_dir.handle, old_sub_path.ptr, old_sub_path.len, new_dir.handle, new_sub_path.ptr, new_sub_path.len)) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .PERM => return error.PermissionDenied,
                    .BUSY => return error.FileBusy,
                    .DQUOT => return error.DiskQuota,
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .ISDIR => return error.IsDir,
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirRenamePosix(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var old_path_buffer: [posix.PATH_MAX]u8 = undefined;
    var new_path_buffer: [posix.PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    return renameat(old_dir.handle, old_sub_path_posix, new_dir.handle, new_sub_path_posix);
}

fn dirRenamePreserveLinux(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenamePreserveError!void {
    const linux = std.os.linux;

    var old_path_buffer: [linux.PATH_MAX]u8 = undefined;
    var new_path_buffer: [linux.PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    const syscall: Syscall = try .start();
    while (true) switch (linux.errno(linux.renameat2(
        old_dir.handle,
        old_sub_path_posix,
        new_dir.handle,
        new_sub_path_posix,
        .{ .NOREPLACE = true },
    ))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ACCES => return syscall.fail(error.AccessDenied),
        .PERM => return syscall.fail(error.PermissionDenied),
        .BUSY => return syscall.fail(error.FileBusy),
        .DQUOT => return syscall.fail(error.DiskQuota),
        .ISDIR => return syscall.fail(error.IsDir),
        .LOOP => return syscall.fail(error.SymLinkLoop),
        .MLINK => return syscall.fail(error.LinkQuotaExceeded),
        .NAMETOOLONG => return syscall.fail(error.NameTooLong),
        .NOENT => return syscall.fail(error.FileNotFound),
        .NOTDIR => return syscall.fail(error.NotDir),
        .NOMEM => return syscall.fail(error.SystemResources),
        .NOSPC => return syscall.fail(error.NoSpaceLeft),
        .EXIST => return syscall.fail(error.PathAlreadyExists),
        .NOTEMPTY => return syscall.fail(error.DirNotEmpty),
        .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
        .XDEV => return syscall.fail(error.CrossDevice),
        .ILSEQ => return syscall.fail(error.BadPathName),
        .FAULT => |err| return syscall.errnoBug(err),
        .INVAL => |err| return syscall.errnoBug(err),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn renameat(
    old_dir: posix.fd_t,
    old_sub_path: [*:0]const u8,
    new_dir: posix.fd_t,
    new_sub_path: [*:0]const u8,
) Dir.RenameError!void {
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.renameat(old_dir, old_sub_path, new_dir, new_sub_path))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ACCES => return syscall.fail(error.AccessDenied),
        .PERM => return syscall.fail(error.PermissionDenied),
        .BUSY => return syscall.fail(error.FileBusy),
        .DQUOT => return syscall.fail(error.DiskQuota),
        .ISDIR => return syscall.fail(error.IsDir),
        .IO => return syscall.fail(error.HardwareFailure),
        .LOOP => return syscall.fail(error.SymLinkLoop),
        .MLINK => return syscall.fail(error.LinkQuotaExceeded),
        .NAMETOOLONG => return syscall.fail(error.NameTooLong),
        .NOENT => return syscall.fail(error.FileNotFound),
        .NOTDIR => return syscall.fail(error.NotDir),
        .NOMEM => return syscall.fail(error.SystemResources),
        .NOSPC => return syscall.fail(error.NoSpaceLeft),
        .EXIST => return syscall.fail(error.DirNotEmpty),
        .NOTEMPTY => return syscall.fail(error.DirNotEmpty),
        .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
        .XDEV => return syscall.fail(error.CrossDevice),
        .ILSEQ => return syscall.fail(error.BadPathName),
        .FAULT => |err| return syscall.errnoBug(err),
        .INVAL => |err| return syscall.errnoBug(err),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn renameatPreserve(
    old_dir: posix.fd_t,
    old_sub_path: [*:0]const u8,
    new_dir: posix.fd_t,
    new_sub_path: [*:0]const u8,
) Dir.RenameError!void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.renameat(old_dir, old_sub_path, new_dir, new_sub_path))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .PERM => return error.PermissionDenied,
                    .BUSY => return error.FileBusy,
                    .DQUOT => return error.DiskQuota,
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .ISDIR => return error.IsDir,
                    .LOOP => return error.SymLinkLoop,
                    .MLINK => return error.LinkQuotaExceeded,
                    .NAMETOOLONG => return error.NameTooLong,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.NotDir,
                    .NOMEM => return error.SystemResources,
                    .NOSPC => return error.NoSpaceLeft,
                    .EXIST => return error.PathAlreadyExists,
                    .NOTEMPTY => return error.PathAlreadyExists,
                    .ROFS => return error.ReadOnlyFileSystem,
                    .XDEV => return error.CrossDevice,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirSymLink = switch (native_os) {
    .windows => dirSymLinkWindows,
    .wasi => dirSymLinkWasi,
    else => dirSymLinkPosix,
};

fn dirSymLinkWindows(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const w = windows;

    // Target path does not use sliceToPrefixedFileW because certain paths
    // are handled differently when creating a symlink than they would be
    // when converting to an NT namespaced path.
    var target_path_w: WindowsPathSpace = undefined;
    target_path_w.len = try w.wtf8ToWtf16Le(&target_path_w.data, target_path);
    target_path_w.data[target_path_w.len] = 0;
    // However, we need to canonicalize any path separators to `\`, since if
    // the target path is relative, then it must use `\` as the path separator.
    std.mem.replaceScalar(
        u16,
        target_path_w.data[0..target_path_w.len],
        std.mem.nativeToLittle(u16, '/'),
        std.mem.nativeToLittle(u16, '\\'),
    );

    const sym_link_path_w = try sliceToPrefixedFileW(dir.handle, sym_link_path, .{});

    const SYMLINK_DATA = extern struct {
        ReparseTag: w.IO_REPARSE_TAG,
        ReparseDataLength: w.USHORT,
        Reserved: w.USHORT,
        SubstituteNameOffset: w.USHORT,
        SubstituteNameLength: w.USHORT,
        PrintNameOffset: w.USHORT,
        PrintNameLength: w.USHORT,
        Flags: w.ULONG,
    };

    const symlink_handle = handle: {
        if (OpenFile(sym_link_path_w.span(), .{
            .access_mask = .{
                .GENERIC = .{ .READ = true, .WRITE = true },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            .dir = dir.handle,
            .creation = .CREATE,
            .filter = if (flags.is_directory) .dir_only else .non_directory_only,
        })) |handle| {
            break :handle handle;
        } else |err| switch (err) {
            error.IsDir => return error.PathAlreadyExists,
            error.NotDir => return error.Unexpected,
            error.WouldBlock => return error.Unexpected,
            error.PipeBusy => return error.Unexpected,
            error.FileBusy => return error.Unexpected,
            error.NoDevice => return error.Unexpected,
            error.AntivirusInterference => return error.Unexpected,
            else => |e| return e,
        }
    };
    defer w.CloseHandle(symlink_handle);

    // Relevant portions of the documentation:
    // > Relative links are specified using the following conventions:
    // > - Root relative—for example, "\Windows\System32" resolves to "current drive:\Windows\System32".
    // > - Current working directory–relative—for example, if the current working directory is
    // >   C:\Windows\System32, "C:File.txt" resolves to "C:\Windows\System32\File.txt".
    // > Note: If you specify a current working directory–relative link, it is created as an absolute
    // > link, due to the way the current working directory is processed based on the user and the thread.
    // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinkw
    var is_target_absolute = false;
    const final_target_path = target_path: {
        if (w.hasCommonNtPrefix(u16, target_path_w.span())) {
            // Already an NT path, no need to do anything to it
            break :target_path target_path_w.span();
        } else {
            switch (Dir.path.getWin32PathType(u16, target_path_w.span())) {
                // Rooted paths need to avoid getting put through wToPrefixedFileW
                // (and they are treated as relative in this context)
                // Note: It seems that rooted paths in symbolic links are relative to
                //       the drive that the symbolic exists on, not to the CWD's drive.
                //       So, if the symlink is on C:\ and the CWD is on D:\,
                //       it will still resolve the path relative to the root of
                //       the C:\ drive.
                .rooted => break :target_path target_path_w.span(),
                // Keep relative paths relative, but anything else needs to get NT-prefixed.
                else => if (!Dir.path.isAbsoluteWindowsWtf16(target_path_w.span()))
                    break :target_path target_path_w.span(),
            }
        }
        var prefixed_target_path = try wToPrefixedFileW(dir.handle, target_path_w.span(), .{});
        // We do this after prefixing to ensure that drive-relative paths are treated as absolute
        is_target_absolute = Dir.path.isAbsoluteWindowsWtf16(prefixed_target_path.span());
        break :target_path prefixed_target_path.span();
    };

    // prepare reparse data buffer
    var buffer: [w.MAXIMUM_REPARSE_DATA_BUFFER_SIZE]u8 = undefined;
    const buf_len = @sizeOf(SYMLINK_DATA) + final_target_path.len * 4;
    const header_len = @sizeOf(w.ULONG) + @sizeOf(w.USHORT) * 2;
    const target_is_absolute = Dir.path.isAbsoluteWindowsWtf16(final_target_path);
    const symlink_data: SYMLINK_DATA = .{
        .ReparseTag = .SYMLINK,
        .ReparseDataLength = @intCast(buf_len - header_len),
        .Reserved = 0,
        .SubstituteNameOffset = @intCast(final_target_path.len * 2),
        .SubstituteNameLength = @intCast(final_target_path.len * 2),
        .PrintNameOffset = 0,
        .PrintNameLength = @intCast(final_target_path.len * 2),
        .Flags = if (!target_is_absolute) w.SYMLINK_FLAG_RELATIVE else 0,
    };

    @memcpy(buffer[0..@sizeOf(SYMLINK_DATA)], std.mem.asBytes(&symlink_data));
    @memcpy(buffer[@sizeOf(SYMLINK_DATA)..][0 .. final_target_path.len * 2], @as([*]const u8, @ptrCast(final_target_path)));
    const paths_start = @sizeOf(SYMLINK_DATA) + final_target_path.len * 2;
    @memcpy(buffer[paths_start..][0 .. final_target_path.len * 2], @as([*]const u8, @ptrCast(final_target_path)));
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = symlink_handle, .flags = .{ .nonblocking = false } },
        .code = .SET_REPARSE_POINT,
        .in = buffer[0..buf_len],
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        .PRIVILEGE_NOT_HELD => return error.PermissionDenied,
        .ACCESS_DENIED => return error.AccessDenied,
        .INVALID_DEVICE_REQUEST => return error.FileSystem,
        else => |status| return w.unexpectedStatus(status),
    }
}

fn dirSymLinkWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    if (builtin.link_libc) return dirSymLinkPosix(userdata, dir, target_path, sym_link_path, flags);

    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.wasi.path_symlink(target_path.ptr, target_path.len, dir.handle, sym_link_path.ptr, sym_link_path.len)) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err),
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirSymLinkPosix(
    userdata: ?*anyopaque,
    dir: Dir,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: Dir.SymLinkFlags,
) Dir.SymLinkError!void {
    _ = flags;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var target_path_buffer: [posix.PATH_MAX]u8 = undefined;
    var sym_link_path_buffer: [posix.PATH_MAX]u8 = undefined;

    const target_path_posix = try pathToPosix(target_path, &target_path_buffer);
    const sym_link_path_posix = try pathToPosix(sym_link_path, &sym_link_path_buffer);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.symlinkat(target_path_posix, dir.handle, sym_link_path_posix))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirReadLink(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    switch (native_os) {
        .windows => return dirReadLinkWindows(dir, sub_path, buffer),
        .wasi => return dirReadLinkWasi(dir, sub_path, buffer),
        else => return dirReadLinkPosix(dir, sub_path, buffer),
    }
}

fn dirReadLinkWindows(dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    // This gets used once for `sub_path` and then reused again temporarily
    // before converting back to `buffer`.
    var sub_path_w = try sliceToPrefixedFileW(dir.handle, sub_path, .{});
    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w.span())) null else dir.handle,
        .ObjectName = @constCast(&sub_path_w.string()),
    };
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var result_handle: windows.HANDLE = undefined;
    var attempt: u5 = 0;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtCreateFile(
        &result_handle,
        .{
            .SPECIFIC = .{ .FILE = .{
                .READ_ATTRIBUTES = true,
            } },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &attr,
        &io_status_block,
        null,
        .{ .NORMAL = true },
        .VALID_FLAGS,
        .OPEN,
        .{
            .DIRECTORY_FILE = false,
            .NON_DIRECTORY_FILE = false,
            .IO = .ASYNCHRONOUS,
            .OPEN_REPARSE_POINT = true,
        },
        null,
        0,
    )) {
        .SUCCESS => {
            syscall.finish();
            break;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .SHARING_VIOLATION => {
            // This occurs if the file attempting to be opened is a running
            // executable. However, there's a kernel bug: the error may be
            // incorrectly returned for an indeterminate amount of time
            // after an executable file is closed. Here we work around the
            // kernel bug with retry attempts.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .DELETE_PENDING => {
            // This error means that there *was* a file in this location on
            // the file system, but it was deleted. However, the OS is not
            // finished with the deletion operation, and so this CreateFile
            // call has failed. Here, we simulate the kernel bug being
            // fixed by sleeping and retrying until the error goes away.
            syscall.finish();
            if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                .clock = .awake,
            } });
            attempt += 1;
            syscall = try .start();
            continue;
        },
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
        .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
        .NO_MEDIA_IN_DEVICE => return syscall.fail(error.FileNotFound),
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .PIPE_BUSY => return syscall.fail(error.AccessDenied),
        .PIPE_NOT_AVAILABLE => return syscall.fail(error.FileNotFound),
        .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        .VIRUS_INFECTED, .VIRUS_DELETED => return syscall.fail(error.AntivirusInterference),
        .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
        .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
        .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
    defer windows.CloseHandle(result_handle);

    var reparse_buf: [windows.MAXIMUM_REPARSE_DATA_BUFFER_SIZE]u8 align(@alignOf(windows.REPARSE_DATA_BUFFER)) = undefined;

    syscall = try .start();
    while (true) switch (windows.ntdll.NtFsControlFile(
        result_handle,
        null, // event
        null, // APC routine
        null, // APC context
        &io_status_block,
        .GET_REPARSE_POINT,
        null, // input buffer
        0, // input buffer length
        &reparse_buf,
        reparse_buf.len,
    )) {
        .SUCCESS => {
            syscall.finish();
            break;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .NOT_A_REPARSE_POINT => return syscall.fail(error.NotLink),
        else => |status| return syscall.unexpectedNtstatus(status),
    };

    const reparse_struct: *const windows.REPARSE_DATA_BUFFER = @ptrCast(@alignCast(&reparse_buf));
    const IoReparseTagInt = @typeInfo(windows.IO_REPARSE_TAG).@"struct".backing_integer.?;
    const result_w = switch (@as(IoReparseTagInt, @bitCast(reparse_struct.ReparseTag))) {
        @as(IoReparseTagInt, @bitCast(windows.IO_REPARSE_TAG.SYMLINK)) => r: {
            const buf: *const windows.SYMBOLIC_LINK_REPARSE_BUFFER = @ptrCast(@alignCast(&reparse_struct.DataBuffer[0]));
            const offset = buf.SubstituteNameOffset >> 1;
            const len = buf.SubstituteNameLength >> 1;
            const path_buf = @as([*]const u16, &buf.PathBuffer);
            const is_relative = buf.Flags & windows.SYMLINK_FLAG_RELATIVE != 0;
            break :r try parseReadLinkPath(path_buf[offset..][0..len], is_relative, &sub_path_w.data);
        },
        @as(IoReparseTagInt, @bitCast(windows.IO_REPARSE_TAG.MOUNT_POINT)) => r: {
            const buf: *const windows.MOUNT_POINT_REPARSE_BUFFER = @ptrCast(@alignCast(&reparse_struct.DataBuffer[0]));
            const offset = buf.SubstituteNameOffset >> 1;
            const len = buf.SubstituteNameLength >> 1;
            const path_buf = @as([*]const u16, &buf.PathBuffer);
            break :r try parseReadLinkPath(path_buf[offset..][0..len], false, &sub_path_w.data);
        },
        else => return error.UnsupportedReparsePointType,
    };
    const len = std.unicode.calcWtf8Len(result_w);
    if (len > buffer.len) return error.NameTooLong;

    return std.unicode.wtf16LeToWtf8(buffer, result_w);
}

fn parseReadLinkPath(path: []const u16, is_relative: bool, out_buffer: []u16) error{NameTooLong}![]u16 {
    path: {
        if (is_relative) break :path;
        return windows.ntToWin32Namespace(path, out_buffer) catch |err| switch (err) {
            error.NameTooLong => |e| return e,
            error.NotNtPath => break :path,
        };
    }
    if (out_buffer.len < path.len) return error.NameTooLong;
    const dest = out_buffer[0..path.len];
    @memcpy(dest, path);
    return dest;
}

fn dirReadLinkWasi(dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    if (builtin.link_libc) return dirReadLinkPosix(dir, sub_path, buffer);

    var n: usize = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.wasi.path_readlink(dir.handle, sub_path.ptr, sub_path.len, buffer.ptr, buffer.len, &n)) {
            .SUCCESS => {
                syscall.finish();
                return n;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => return error.NotLink,
                    .IO => return error.FileSystem,
                    .LOOP => return error.SymLinkLoop,
                    .NAMETOOLONG => return error.NameTooLong,
                    .NOENT => return error.FileNotFound,
                    .NOMEM => return error.SystemResources,
                    .NOTDIR => return error.NotDir,
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirReadLinkPosix(dir: Dir, sub_path: []const u8, buffer: []u8) Dir.ReadLinkError!usize {
    var sub_path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &sub_path_buffer);

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.readlinkat(dir.handle, sub_path_posix, buffer.ptr, buffer.len);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const len: usize = @bitCast(rc);
                return len;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirSetPermissions = switch (native_os) {
    .windows => dirSetPermissionsWindows,
    else => dirSetPermissionsPosix,
};

fn dirSetPermissionsWindows(userdata: ?*anyopaque, dir: Dir, permissions: Dir.Permissions) Dir.SetPermissionsError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    _ = dir;
    _ = permissions;
    @panic("TODO implement dirSetPermissionsWindows");
}

fn dirSetPermissionsPosix(userdata: ?*anyopaque, dir: Dir, permissions: Dir.Permissions) Dir.SetPermissionsError!void {
    if (@sizeOf(Dir.Permissions) == 0) return;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return setPermissionsPosix(dir.handle, permissions.toMode());
}

fn dirSetFilePermissions(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
    options: Dir.SetFilePermissionsOptions,
) Dir.SetFilePermissionsError!void {
    if (@sizeOf(Dir.Permissions) == 0) return;
    if (is_windows) @panic("TODO implement dirSetFilePermissions windows");
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const mode = permissions.toMode();
    const flags: u32 = if (!options.follow_symlinks) posix.AT.SYMLINK_NOFOLLOW else 0;

    return posixFchmodat(t, dir.handle, sub_path_posix, mode, flags);
}

fn posixFchmodat(
    t: *Threaded,
    dir_fd: posix.fd_t,
    path: [*:0]const u8,
    mode: posix.mode_t,
    flags: u32,
) Dir.SetFilePermissionsError!void {
    // No special handling for linux is needed if we can use the libc fallback
    // or `flags` is empty. Glibc only added the fallback in 2.32.
    if (have_fchmodat_flags or flags == 0) {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = if (have_fchmodat_flags or builtin.link_libc)
                posix.system.fchmodat(dir_fd, path, mode, flags)
            else
                posix.system.fchmodat(dir_fd, path, mode);
            switch (posix.errno(rc)) {
                .SUCCESS => return syscall.finish(),
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
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
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    if (@atomicLoad(UseFchmodat2, &t.use_fchmodat2, .monotonic) == .disabled)
        return fchmodatFallback(dir_fd, path, mode);

    comptime assert(native_os == .linux);

    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.linux.errno(std.os.linux.fchmodat2(dir_fd, path, mode, flags))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    .NOSYS => {
                        @atomicStore(UseFchmodat2, &t.use_fchmodat2, .disabled, .monotonic);
                        return fchmodatFallback(dir_fd, path, mode);
                    },
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fchmodatFallback(
    dir_fd: posix.fd_t,
    path: [*:0]const u8,
    mode: posix.mode_t,
) Dir.SetFilePermissionsError!void {
    comptime assert(native_os == .linux);

    // Fallback to changing permissions using procfs:
    //
    // 1. Open `path` as a `PATH` descriptor.
    // 2. Stat the fd and check if it isn't a symbolic link.
    // 3. Generate the procfs reference to the fd via `/proc/self/fd/{fd}`.
    // 4. Pass the procfs path to `chmod` with the `mode`.
    const path_fd: posix.fd_t = fd: {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = posix.system.openat(dir_fd, path, .{
                .PATH = true,
                .NOFOLLOW = true,
                .CLOEXEC = true,
            }, @as(posix.mode_t, 0));
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break :fd @intCast(rc);
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .FAULT => |err| return errnoBug(err),
                        .INVAL => |err| return errnoBug(err),
                        .ACCES => return error.AccessDenied,
                        .PERM => return error.PermissionDenied,
                        .LOOP => return error.SymLinkLoop,
                        .MFILE => return error.ProcessFdQuotaExceeded,
                        .NAMETOOLONG => return error.NameTooLong,
                        .NFILE => return error.SystemFdQuotaExceeded,
                        .NOENT => return error.FileNotFound,
                        .NOMEM => return error.SystemResources,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    };
    defer closeFd(path_fd);

    const path_mode = mode: {
        const sys = if (statx_use_c) std.c else std.os.linux;
        const syscall: Syscall = try .start();
        while (true) {
            var statx = std.mem.zeroes(std.os.linux.Statx);
            switch (sys.errno(sys.statx(path_fd, "", posix.AT.EMPTY_PATH, .{ .TYPE = true }, &statx))) {
                .SUCCESS => {
                    syscall.finish();
                    if (!statx.mask.TYPE) return error.Unexpected;
                    break :mode statx.mode;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .ACCES => return error.AccessDenied,
                        .LOOP => return error.SymLinkLoop,
                        .NOMEM => return error.SystemResources,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    };

    // Even though we only wanted TYPE, the kernel can still fill in the additional bits.
    if ((path_mode & posix.S.IFMT) == posix.S.IFLNK)
        return error.OperationUnsupported;

    var procfs_buf: ["/proc/self/fd/-2147483648\x00".len]u8 = undefined;
    const proc_path = std.fmt.bufPrintSentinel(&procfs_buf, "/proc/self/fd/{d}", .{path_fd}, 0) catch unreachable;
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.chmod(proc_path, mode))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .NOENT => return error.OperationUnsupported, // procfs not mounted.
                    .BADF => |err| return errnoBug(err),
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .ACCES => return error.AccessDenied,
                    .IO => return error.InputOutput,
                    .LOOP => return error.SymLinkLoop,
                    .NOMEM => return error.SystemResources,
                    .NOTDIR => return error.FileNotFound,
                    .PERM => return error.PermissionDenied,
                    .ROFS => return error.ReadOnlyFileSystem,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

const dirSetOwner = switch (native_os) {
    .windows => dirSetOwnerUnsupported,
    else => dirSetOwnerPosix,
};

fn dirSetOwnerUnsupported(userdata: ?*anyopaque, dir: Dir, owner: ?File.Uid, group: ?File.Gid) Dir.SetOwnerError!void {
    _ = userdata;
    _ = dir;
    _ = owner;
    _ = group;
    return error.Unexpected;
}

fn dirSetOwnerPosix(userdata: ?*anyopaque, dir: Dir, owner: ?File.Uid, group: ?File.Gid) Dir.SetOwnerError!void {
    if (!have_fchown) return error.Unexpected; // Unsupported OS, don't call this function.
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const uid = owner orelse ~@as(posix.uid_t, 0);
    const gid = group orelse ~@as(posix.gid_t, 0);
    return posixFchown(dir.handle, uid, gid);
}

fn posixFchown(fd: posix.fd_t, uid: posix.uid_t, gid: posix.gid_t) File.SetOwnerError!void {
    comptime assert(have_fchown);
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.fchown(fd, uid, gid))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirSetFileOwner(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    owner: ?File.Uid,
    group: ?File.Gid,
    options: Dir.SetFileOwnerOptions,
) Dir.SetFileOwnerError!void {
    if (!have_fchown) return error.Unexpected; // Unsupported OS, don't call this function.
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    _ = dir;
    _ = sub_path_posix;
    _ = owner;
    _ = group;
    _ = options;
    @panic("TODO implement dirSetFileOwner");
}

const fileSync = switch (native_os) {
    .windows => fileSyncWindows,
    .wasi => fileSyncWasi,
    else => fileSyncPosix,
};

fn fileSyncWindows(userdata: ?*anyopaque, file: File) File.SyncError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (windows.ntdll.NtFlushBuffersFile(file.handle, &io_status_block)) {
            .SUCCESS => break syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INVALID_HANDLE => unreachable,
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied), // a sync was performed but the system couldn't update the access time
            .UNEXPECTED_NETWORK_ERROR => return syscall.fail(error.InputOutput),
            else => |status| return syscall.unexpectedNtstatus(status),
        }
    }
}

fn fileSyncPosix(userdata: ?*anyopaque, file: File) File.SyncError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.fsync(file.handle))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .ROFS => |err| return errnoBug(err),
                    .IO => return error.InputOutput,
                    .NOSPC => return error.NoSpaceLeft,
                    .DQUOT => return error.DiskQuota,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileSyncWasi(userdata: ?*anyopaque, file: File) File.SyncError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const syscall: Syscall = try .start();
    while (true) {
        switch (std.os.wasi.fd_sync(file.handle)) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .ROFS => |err| return errnoBug(err),
                    .IO => return error.InputOutput,
                    .NOSPC => return error.NoSpaceLeft,
                    .DQUOT => return error.DiskQuota,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileIsTty(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return isTty(file);
}

fn isTty(file: File) Io.Cancelable!bool {
    if (is_windows) {
        var get_console_mode = windows.CONSOLE.USER_IO.GET_MODE;
        switch ((try deviceIoControl(&.{
            .file = .{
                .handle = windows.peb().ProcessParameters.ConsoleHandle,
                .flags = .{ .nonblocking = false },
            },
            .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
            .in = @ptrCast(&get_console_mode.request(file, 0, .{}, 0, .{})),
        })).u.Status) {
            .SUCCESS => return true,
            .CANCELLED => unreachable,
            .INVALID_HANDLE => return isCygwinPty(file),
            else => return false,
        }
    }

    if (builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = posix.system.isatty(file.handle);
            switch (posix.errno(rc - 1)) {
                .SUCCESS => {
                    syscall.finish();
                    return true;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => {
                    syscall.finish();
                    return false;
                },
            }
        }
    }

    if (native_os == .wasi) {
        var statbuf: std.os.wasi.fdstat_t = undefined;
        const err = std.os.wasi.fd_fdstat_get(file.handle, &statbuf);
        if (err != .SUCCESS)
            return false;

        // A tty is a character device that we can't seek or tell on.
        if (statbuf.fs_filetype != .CHARACTER_DEVICE)
            return false;
        if (statbuf.fs_rights_base.FD_SEEK or statbuf.fs_rights_base.FD_TELL)
            return false;

        return true;
    }

    if (native_os == .linux) {
        const linux = std.os.linux;
        const syscall: Syscall = try .start();
        while (true) {
            var wsz: posix.winsize = undefined;
            const fd: usize = @bitCast(@as(isize, file.handle));
            const rc = linux.syscall3(.ioctl, fd, linux.T.IOCGWINSZ, @intFromPtr(&wsz));
            switch (linux.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    return true;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => {
                    syscall.finish();
                    return false;
                },
            }
        }
    }

    @compileError("unimplemented");
}

fn fileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: File) File.EnableAnsiEscapeCodesError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (!is_windows) return if (!try supportsAnsiEscapeCodes(file)) error.NotTerminalDevice;

    // For Windows Terminal, VT Sequences processing is enabled by default.
    const console: File = .{
        .handle = windows.peb().ProcessParameters.ConsoleHandle,
        .flags = .{ .nonblocking = false },
    };
    var get_console_mode = windows.CONSOLE.USER_IO.GET_MODE;
    switch ((try deviceIoControl(&.{
        .file = console,
        .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
        .in = @ptrCast(&get_console_mode.request(file, 0, .{}, 0, .{})),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INVALID_HANDLE => return if (!try isCygwinPty(file)) error.NotTerminalDevice,
        else => return error.NotTerminalDevice,
    }

    if (get_console_mode.Data & windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0) return;

    // For Windows Console, VT Sequences processing support was added in Windows 10 build 14361, but disabled by default.
    // https://devblogs.microsoft.com/commandline/tmux-support-arrives-for-bash-on-ubuntu-on-windows/
    //
    // Note: In Microsoft's example for enabling virtual terminal processing, it
    // shows attempting to enable `DISABLE_NEWLINE_AUTO_RETURN` as well:
    // https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences#example-of-enabling-virtual-terminal-processing
    // This is avoided because in the old Windows Console, that flag causes \n (as opposed to \r\n)
    // to behave unexpectedly (the cursor moves down 1 row but remains on the same column).
    // Additionally, the default console mode in Windows Terminal does not have
    // `DISABLE_NEWLINE_AUTO_RETURN` set, so by only enabling `ENABLE_VIRTUAL_TERMINAL_PROCESSING`
    // we end up matching the mode of Windows Terminal.
    var set_console_mode = windows.CONSOLE.USER_IO.SET_MODE(
        get_console_mode.Data | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING,
    );
    switch ((try deviceIoControl(&.{
        .file = console,
        .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
        .in = @ptrCast(&set_console_mode.request(file, 0, .{}, 0, .{})),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn fileSupportsAnsiEscapeCodes(userdata: ?*anyopaque, file: File) Io.Cancelable!bool {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return supportsAnsiEscapeCodes(file);
}

fn supportsAnsiEscapeCodes(file: File) Io.Cancelable!bool {
    if (is_windows) {
        var get_console_mode = windows.CONSOLE.USER_IO.GET_MODE;
        switch ((try deviceIoControl(&.{
            .file = .{
                .handle = windows.peb().ProcessParameters.ConsoleHandle,
                .flags = .{ .nonblocking = false },
            },
            .code = windows.IOCTL.CONDRV.ISSUE_USER_IO,
            .in = @ptrCast(&get_console_mode.request(file, 0, .{}, 0, .{})),
        })).u.Status) {
            .SUCCESS => if (get_console_mode.Data & windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0)
                return true,
            .CANCELLED => unreachable,
            .INVALID_HANDLE => return isCygwinPty(file),
            else => return false,
        }
    }

    if (try isTty(file)) return true;

    return false;
}

fn isCygwinPty(file: File) Io.Cancelable!bool {
    if (!is_windows) return false;

    const handle = file.handle;

    // If this is a MSYS2/cygwin pty, then it will be a named pipe with a name in one of these formats:
    //   msys-[...]-ptyN-[...]
    //   cygwin-[...]-ptyN-[...]
    //
    // Example: msys-1888ae32e00d56aa-pty0-to-master

    // First, just check that the handle is a named pipe.
    // This allows us to avoid the more costly NtQueryInformationFile call
    // for handles that aren't named pipes.
    {
        var io_status: windows.IO_STATUS_BLOCK = undefined;
        var device_info: windows.FILE.FS_DEVICE_INFORMATION = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtQueryVolumeInformationFile(
            handle,
            &io_status,
            &device_info,
            @sizeOf(windows.FILE.FS_DEVICE_INFORMATION),
            .Device,
        )) {
            .SUCCESS => break syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => {
                syscall.finish();
                return false;
            },
        };
        if (device_info.DeviceType.FileDevice != .NAMED_PIPE) return false;
    }

    const name_bytes_offset = @offsetOf(windows.FILE.NAME_INFORMATION, "FileName");
    // `NAME_MAX` UTF-16 code units (2 bytes each)
    // This buffer may not be long enough to handle *all* possible paths
    // (PATH_MAX_WIDE would be necessary for that), but because we only care
    // about certain paths and we know they must be within a reasonable length,
    // we can use this smaller buffer and just return false on any error from
    // NtQueryInformationFile.
    const num_name_bytes = windows.MAX_PATH * 2;
    var name_info_bytes align(@alignOf(windows.FILE.NAME_INFORMATION)) = [_]u8{0} ** (name_bytes_offset + num_name_bytes);

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    const syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtQueryInformationFile(
        handle,
        &io_status_block,
        &name_info_bytes,
        @intCast(name_info_bytes.len),
        .Name,
    )) {
        .SUCCESS => break syscall.finish(),
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .INVALID_PARAMETER => unreachable,
        else => {
            syscall.finish();
            return false;
        },
    };

    const name_info: *const windows.FILE.NAME_INFORMATION = @ptrCast(&name_info_bytes);
    const name_bytes = name_info_bytes[name_bytes_offset .. name_bytes_offset + name_info.FileNameLength];
    const name_wide = std.mem.bytesAsSlice(u16, name_bytes);
    // The name we get from NtQueryInformationFile will be prefixed with a '\', e.g. \msys-1888ae32e00d56aa-pty0-to-master
    return (std.mem.startsWith(u16, name_wide, &[_]u16{ '\\', 'm', 's', 'y', 's', '-' }) or
        std.mem.startsWith(u16, name_wide, &[_]u16{ '\\', 'c', 'y', 'g', 'w', 'i', 'n', '-' })) and
        std.mem.indexOf(u16, name_wide, &[_]u16{ '-', 'p', 't', 'y' }) != null;
}

fn fileSetLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const signed_len: i64 = @bitCast(length);
    if (signed_len < 0) return error.FileTooBig; // Avoid ambiguous EINVAL errors.

    if (is_windows) {
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        var eof_info: windows.FILE.END_OF_FILE_INFORMATION = .{
            .EndOfFile = signed_len,
        };

        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtSetInformationFile(
            file.handle,
            &io_status_block,
            &eof_info,
            @sizeOf(windows.FILE.END_OF_FILE_INFORMATION),
            .EndOfFile,
        )) {
            .SUCCESS => return syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INVALID_HANDLE => |err| return syscall.ntstatusBug(err), // Handle not open for writing.
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
            .INVALID_PARAMETER => return syscall.fail(error.FileTooBig),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    if (native_os == .wasi and !builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            switch (std.os.wasi.fd_filestat_set_size(file.handle, length)) {
                .SUCCESS => return syscall.finish(),
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .FBIG => return error.FileTooBig,
                        .IO => return error.InputOutput,
                        .PERM => return error.PermissionDenied,
                        .TXTBSY => return error.FileBusy,
                        .BADF => |err| return errnoBug(err), // Handle not open for writing
                        .INVAL => return error.NonResizable,
                        .NOTCAPABLE => return error.AccessDenied,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(ftruncate_sym(file.handle, signed_len))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .FBIG => return error.FileTooBig,
                    .IO => return error.InputOutput,
                    .PERM => return error.PermissionDenied,
                    .TXTBSY => return error.FileBusy,
                    .BADF => |err| return errnoBug(err), // Handle not open for writing.
                    .INVAL => return error.NonResizable, // This is returned for /dev/null for example.
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileSetOwner(userdata: ?*anyopaque, file: File, owner: ?File.Uid, group: ?File.Gid) File.SetOwnerError!void {
    if (!have_fchown) return error.Unexpected; // Unsupported OS, don't call this function.
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const uid = owner orelse ~@as(posix.uid_t, 0);
    const gid = group orelse ~@as(posix.gid_t, 0);
    return posixFchown(file.handle, uid, gid);
}

fn fileSetPermissions(userdata: ?*anyopaque, file: File, permissions: File.Permissions) File.SetPermissionsError!void {
    if (@sizeOf(File.Permissions) == 0) return;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    switch (native_os) {
        .windows => {
            var io_status_block: windows.IO_STATUS_BLOCK = undefined;
            var info: windows.FILE.BASIC_INFORMATION = .{
                .CreationTime = 0,
                .LastAccessTime = 0,
                .LastWriteTime = 0,
                .ChangeTime = 0,
                .FileAttributes = permissions.toAttributes(),
            };
            const syscall: Syscall = try .start();
            while (true) switch (windows.ntdll.NtSetInformationFile(
                file.handle,
                &io_status_block,
                &info,
                @sizeOf(windows.FILE.BASIC_INFORMATION),
                .Basic,
            )) {
                .SUCCESS => return syscall.finish(),
                .CANCELLED => {
                    try syscall.checkCancel();
                    continue;
                },
                .INVALID_HANDLE => |err| return syscall.ntstatusBug(err),
                .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
                else => |status| return syscall.unexpectedNtstatus(status),
            };
        },
        .wasi => return error.Unexpected, // Unsupported OS.
        else => return setPermissionsPosix(file.handle, permissions.toMode()),
    }
}

fn setPermissionsPosix(fd: posix.fd_t, mode: posix.mode_t) File.SetPermissionsError!void {
    comptime assert(have_fchmod);
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.fchmod(fd, mode))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirSetTimestamps(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.SetTimestampsOptions,
) Dir.SetTimestampsError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        @panic("TODO implement dirSetTimestamps windows");
    }

    if (native_os == .wasi and !builtin.link_libc) {
        @panic("TODO implement dirSetTimestamps wasi");
    }

    var times_buffer: [2]posix.timespec = undefined;
    const times = if (options.modify_timestamp == .now and options.access_timestamp == .now) null else p: {
        times_buffer = .{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        };
        break :p &times_buffer;
    };

    const flags: u32 = if (!options.follow_symlinks) posix.AT.SYMLINK_NOFOLLOW else 0;

    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const sub_path_posix = try pathToPosix(sub_path, &path_buffer);

    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.utimensat(dir.handle, sub_path_posix, times, flags))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .BADF => |err| return syscall.errnoBug(err), // always a race condition
        .FAULT => |err| return syscall.errnoBug(err),
        .INVAL => |err| return syscall.errnoBug(err),
        .ACCES => return syscall.fail(error.AccessDenied),
        .PERM => return syscall.fail(error.PermissionDenied),
        .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn fileSetTimestamps(
    userdata: ?*anyopaque,
    file: File,
    options: File.SetTimestampsOptions,
) File.SetTimestampsError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        const now_sys = if (options.access_timestamp == .now or options.modify_timestamp == .now)
            windows.ntdll.RtlGetSystemTimePrecise()
        else
            undefined;
        var iosb: windows.IO_STATUS_BLOCK = undefined;
        var info: windows.FILE.BASIC_INFORMATION = .{
            .CreationTime = 0,
            .LastAccessTime = switch (options.access_timestamp) {
                .unchanged => 0,
                .now => now_sys,
                .new => |ts| windows.toSysTime(ts),
            },
            .LastWriteTime = switch (options.modify_timestamp) {
                .unchanged => 0,
                .now => now_sys,
                .new => |ts| windows.toSysTime(ts),
            },
            .ChangeTime = 0,
            .FileAttributes = .{},
        };
        var syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtSetInformationFile(
            file.handle,
            &iosb,
            &info,
            @sizeOf(windows.FILE.BASIC_INFORMATION),
            .Basic,
        )) {
            .SUCCESS => return syscall.finish(),
            .CANCELLED => try syscall.checkCancel(),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    if (native_os == .wasi and !builtin.link_libc) {
        var atime: std.os.wasi.timestamp_t = 0;
        var mtime: std.os.wasi.timestamp_t = 0;
        var flags: std.os.wasi.fstflags_t = .{};

        switch (options.access_timestamp) {
            .unchanged => {},
            .now => flags.ATIM_NOW = true,
            .new => |ts| {
                atime = timestampToPosix(ts.nanoseconds).toTimestamp();
                flags.ATIM = true;
            },
        }

        switch (options.modify_timestamp) {
            .unchanged => {},
            .now => flags.MTIM_NOW = true,
            .new => |ts| {
                mtime = timestampToPosix(ts.nanoseconds).toTimestamp();
                flags.MTIM = true;
            },
        }

        const syscall: Syscall = try .start();
        while (true) switch (std.os.wasi.fd_filestat_set_times(file.handle, atime, mtime, flags)) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .BADF => |err| return syscall.errnoBug(err), // File descriptor use-after-free.
            .FAULT => |err| return syscall.errnoBug(err),
            .INVAL => |err| return syscall.errnoBug(err),
            .ACCES => return syscall.fail(error.AccessDenied),
            .PERM => return syscall.fail(error.PermissionDenied),
            .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
            else => |err| return syscall.unexpectedErrno(err),
        };
    }

    var times_buffer: [2]posix.timespec = undefined;
    const times = if (options.modify_timestamp == .now and options.access_timestamp == .now) null else p: {
        times_buffer = .{
            setTimestampToPosix(options.access_timestamp),
            setTimestampToPosix(options.modify_timestamp),
        };
        break :p &times_buffer;
    };

    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.futimens(file.handle, times))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .BADF => |err| return syscall.errnoBug(err), // always a race condition
        .FAULT => |err| return syscall.errnoBug(err),
        .INVAL => |err| return syscall.errnoBug(err),
        .ACCES => return syscall.fail(error.AccessDenied),
        .PERM => return syscall.fail(error.PermissionDenied),
        .ROFS => return syscall.fail(error.ReadOnlyFileSystem),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

const windows_lock_range_off: windows.LARGE_INTEGER = 0;
const windows_lock_range_len: windows.LARGE_INTEGER = 1;

fn fileLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!void {
    if (native_os == .wasi) return error.FileLocksUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        const exclusive = switch (lock) {
            .none => {
                // To match the non-Windows behavior, unlock
                var io_status_block: windows.IO_STATUS_BLOCK = undefined;
                while (true) switch (windows.ntdll.NtUnlockFile(
                    file.handle,
                    &io_status_block,
                    &windows_lock_range_off,
                    &windows_lock_range_len,
                    0,
                )) {
                    .SUCCESS => return,
                    .CANCELLED => continue,
                    .RANGE_NOT_LOCKED => return,
                    .ACCESS_VIOLATION => |err| return windows.statusBug(err), // bad io_status_block pointer
                    else => |status| return windows.unexpectedStatus(status),
                };
            },
            .shared => false,
            .exclusive => true,
        };
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtLockFile(
            file.handle,
            null,
            null,
            null,
            &io_status_block,
            &windows_lock_range_off,
            &windows_lock_range_len,
            null,
            .FALSE,
            .fromBool(exclusive),
        )) {
            .SUCCESS => return syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
            .LOCK_NOT_GRANTED => |err| return syscall.ntstatusBug(err), // passed FailImmediately=false
            .ACCESS_VIOLATION => |err| return syscall.ntstatusBug(err), // bad io_status_block pointer
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    const operation: i32 = switch (lock) {
        .none => posix.LOCK.UN,
        .shared => posix.LOCK.SH,
        .exclusive => posix.LOCK.EX,
    };
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.flock(file.handle, operation))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOLCK => return error.SystemResources,
                    .AGAIN => |err| return errnoBug(err),
                    .OPNOTSUPP => return error.FileLocksUnsupported,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileTryLock(userdata: ?*anyopaque, file: File, lock: File.Lock) File.LockError!bool {
    if (native_os == .wasi) return error.FileLocksUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        const exclusive = switch (lock) {
            .none => {
                // To match the non-Windows behavior, unlock
                var io_status_block: windows.IO_STATUS_BLOCK = undefined;
                while (true) switch (windows.ntdll.NtUnlockFile(
                    file.handle,
                    &io_status_block,
                    &windows_lock_range_off,
                    &windows_lock_range_len,
                    0,
                )) {
                    .SUCCESS => return true,
                    .CANCELLED => continue,
                    .RANGE_NOT_LOCKED => return false,
                    .ACCESS_VIOLATION => |err| return windows.statusBug(err), // bad io_status_block pointer
                    else => |status| return windows.unexpectedStatus(status),
                };
            },
            .shared => false,
            .exclusive => true,
        };
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtLockFile(
            file.handle,
            null,
            null,
            null,
            &io_status_block,
            &windows_lock_range_off,
            &windows_lock_range_len,
            null,
            .TRUE,
            .fromBool(exclusive),
        )) {
            .SUCCESS => {
                syscall.finish();
                return true;
            },
            .LOCK_NOT_GRANTED => {
                syscall.finish();
                return false;
            },
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
            .ACCESS_VIOLATION => |err| return syscall.ntstatusBug(err), // bad io_status_block pointer
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    const operation: i32 = switch (lock) {
        .none => posix.LOCK.UN,
        .shared => posix.LOCK.SH | posix.LOCK.NB,
        .exclusive => posix.LOCK.EX | posix.LOCK.NB,
    };
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.flock(file.handle, operation))) {
            .SUCCESS => {
                syscall.finish();
                return true;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .AGAIN => {
                syscall.finish();
                return false;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOLCK => return error.SystemResources,
                    .OPNOTSUPP => return error.FileLocksUnsupported,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileUnlock(userdata: ?*anyopaque, file: File) void {
    if (native_os == .wasi) return;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        while (true) switch (windows.ntdll.NtUnlockFile(
            file.handle,
            &io_status_block,
            &windows_lock_range_off,
            &windows_lock_range_len,
            0,
        )) {
            .SUCCESS => return,
            .CANCELLED => continue,
            .RANGE_NOT_LOCKED => if (is_debug) unreachable else return, // Function asserts unlocked.
            .ACCESS_VIOLATION => if (is_debug) unreachable else return, // bad io_status_block pointer
            else => if (is_debug) unreachable else return, // Resource deallocation must succeed.
        };
    }

    while (true) {
        switch (posix.errno(posix.system.flock(file.handle, posix.LOCK.UN))) {
            .SUCCESS => return,
            .CANCELED, .INTR => continue,
            .AGAIN => return assert(!is_debug), // unlocking can't block
            .BADF => return assert(!is_debug), // File descriptor used after closed.
            .INVAL => return assert(!is_debug), // invalid parameters
            .NOLCK => return assert(!is_debug), // Resource deallocation.
            .OPNOTSUPP => return assert(!is_debug), // We already got the lock.
            else => return assert(!is_debug), // Resource deallocation must succeed.
        }
    }
}

fn fileDowngradeLock(userdata: ?*anyopaque, file: File) File.DowngradeLockError!void {
    if (native_os == .wasi) return;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        // On Windows it works like a semaphore + exclusivity flag. To
        // implement this function, we first obtain another lock in shared
        // mode. This changes the exclusivity flag, but increments the
        // semaphore to 2. So we follow up with an NtUnlockFile which
        // decrements the semaphore but does not modify the exclusivity flag.
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtLockFile(
            file.handle,
            null,
            null,
            null,
            &io_status_block,
            &windows_lock_range_off,
            &windows_lock_range_len,
            null,
            .TRUE,
            .FALSE,
        )) {
            .SUCCESS => break syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INSUFFICIENT_RESOURCES => |err| return syscall.ntstatusBug(err),
            .LOCK_NOT_GRANTED => |err| return syscall.ntstatusBug(err), // File was not locked in exclusive mode.
            .ACCESS_VIOLATION => |err| return syscall.ntstatusBug(err), // bad io_status_block pointer
            else => |status| return syscall.unexpectedNtstatus(status),
        };
        while (true) switch (windows.ntdll.NtUnlockFile(
            file.handle,
            &io_status_block,
            &windows_lock_range_off,
            &windows_lock_range_len,
            0,
        )) {
            .SUCCESS => return,
            .CANCELLED => continue,
            .RANGE_NOT_LOCKED => if (is_debug) unreachable else return, // File was not locked.
            .ACCESS_VIOLATION => if (is_debug) unreachable else return, // bad io_status_block pointer
            else => if (is_debug) unreachable else return, // Resource deallocation must succeed.
        };
    }

    const operation = posix.LOCK.SH | posix.LOCK.NB;

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.flock(file.handle, operation))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .AGAIN => |err| return errnoBug(err), // File was not locked in exclusive mode.
                    .BADF => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOLCK => |err| return errnoBug(err), // Lock already obtained.
                    .OPNOTSUPP => |err| return errnoBug(err), // Lock already obtained.
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirOpenDirWasi(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.OpenOptions,
) Dir.OpenError!Dir {
    if (builtin.link_libc) return dirOpenDirPosix(userdata, dir, sub_path, options);
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const wasi = std.os.wasi;

    var base: std.os.wasi.rights_t = .{
        .FD_FILESTAT_GET = true,
        .FD_FDSTAT_SET_FLAGS = true,
        .FD_FILESTAT_SET_TIMES = true,
    };
    if (options.access_sub_paths) {
        base.FD_READDIR = true;
        base.PATH_CREATE_DIRECTORY = true;
        base.PATH_CREATE_FILE = true;
        base.PATH_LINK_SOURCE = true;
        base.PATH_LINK_TARGET = true;
        base.PATH_OPEN = true;
        base.PATH_READLINK = true;
        base.PATH_RENAME_SOURCE = true;
        base.PATH_RENAME_TARGET = true;
        base.PATH_FILESTAT_GET = true;
        base.PATH_FILESTAT_SET_SIZE = true;
        base.PATH_FILESTAT_SET_TIMES = true;
        base.PATH_SYMLINK = true;
        base.PATH_REMOVE_DIRECTORY = true;
        base.PATH_UNLINK_FILE = true;
    }

    const lookup_flags: wasi.lookupflags_t = .{ .SYMLINK_FOLLOW = options.follow_symlinks };
    const oflags: wasi.oflags_t = .{ .DIRECTORY = true };
    const fdflags: wasi.fdflags_t = .{};
    var fd: posix.fd_t = undefined;
    const syscall: Syscall = try .start();
    while (true) {
        switch (wasi.path_open(dir.handle, lookup_flags, sub_path.ptr, sub_path.len, oflags, base, base, fdflags, &fd)) {
            .SUCCESS => {
                syscall.finish();
                return .{ .handle = fd };
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => return error.BadPathName,
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
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
                    .NOTCAPABLE => return error.AccessDenied,
                    .ILSEQ => return error.BadPathName,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn dirHardLink(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    options: Dir.HardLinkOptions,
) Dir.HardLinkError!void {
    if (is_windows) return error.OperationUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (native_os == .wasi and !builtin.link_libc) {
        const flags: std.os.wasi.lookupflags_t = .{
            .SYMLINK_FOLLOW = options.follow_symlinks,
        };
        const syscall: Syscall = try .start();
        while (true) {
            switch (std.os.wasi.path_link(
                old_dir.handle,
                flags,
                old_sub_path.ptr,
                old_sub_path.len,
                new_dir.handle,
                new_sub_path.ptr,
                new_sub_path.len,
            )) {
                .SUCCESS => return syscall.finish(),
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .ACCES => return error.AccessDenied,
                        .DQUOT => return error.DiskQuota,
                        .EXIST => return error.PathAlreadyExists,
                        .FAULT => |err| return errnoBug(err),
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
                        .INVAL => |err| return errnoBug(err),
                        .ILSEQ => return error.BadPathName,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    var old_path_buffer: [posix.PATH_MAX]u8 = undefined;
    var new_path_buffer: [posix.PATH_MAX]u8 = undefined;

    const old_sub_path_posix = try pathToPosix(old_sub_path, &old_path_buffer);
    const new_sub_path_posix = try pathToPosix(new_sub_path, &new_path_buffer);

    const flags: u32 = if (options.follow_symlinks) posix.AT.SYMLINK_FOLLOW else 0;
    return linkat(old_dir.handle, old_sub_path_posix, new_dir.handle, new_sub_path_posix, flags);
}

fn fileClose(userdata: ?*anyopaque, files: []const File) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    for (files) |file| {
        if (is_windows) {
            windows.CloseHandle(file.handle);
        } else {
            closeFd(file.handle);
        }
    }
}

fn fileReadStreaming(userdata: ?*anyopaque, file: File, data: []const []u8) File.ReadStreamingError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    if (is_windows) return fileReadStreamingWindows(file, data);
    return fileReadStreamingPosix(file, data);
}

fn fileReadStreamingPosix(file: File, data: []const []u8) File.ReadStreamingError!usize {
    var iovecs_buffer: [max_iovecs_len]posix.iovec = undefined;
    var i: usize = 0;
    for (data) |buf| {
        if (iovecs_buffer.len - i == 0) break;
        if (buf.len != 0) {
            iovecs_buffer[i] = .{ .base = buf.ptr, .len = buf.len };
            i += 1;
        }
    }
    if (i == 0) return 0;
    const dest = iovecs_buffer[0..i];
    assert(dest[0].len > 0);

    if (native_os == .wasi and !builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            var nread: usize = undefined;
            switch (std.os.wasi.fd_read(file.handle, dest.ptr, dest.len, &nread)) {
                .SUCCESS => {
                    syscall.finish();
                    if (nread == 0) return error.EndOfStream;
                    return nread;
                },
                .INTR, .TIMEDOUT => {
                    try syscall.checkCancel();
                    continue;
                },
                .BADF => return syscall.fail(error.IsDir), // File operation on directory.
                .IO => return syscall.fail(error.InputOutput),
                .ISDIR => return syscall.fail(error.IsDir),
                .NOBUFS => return syscall.fail(error.SystemResources),
                .NOMEM => return syscall.fail(error.SystemResources),
                .NOTCONN => return syscall.fail(error.SocketUnconnected),
                .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
                .NOTCAPABLE => return syscall.fail(error.AccessDenied),
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.readv(file.handle, dest.ptr, @intCast(dest.len));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                if (rc == 0) return error.EndOfStream;
                return @intCast(rc);
            },
            .INTR, .TIMEDOUT => {
                try syscall.checkCancel();
                continue;
            },
            .BADF => {
                syscall.finish();
                if (native_os == .wasi) return error.IsDir; // File operation on directory.
                return error.NotOpenForReading;
            },
            .AGAIN => return syscall.fail(error.WouldBlock),
            .IO => return syscall.fail(error.InputOutput),
            .ISDIR => return syscall.fail(error.IsDir),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .NOTCONN => return syscall.fail(error.SocketUnconnected),
            .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
            .INVAL => |err| return syscall.errnoBug(err),
            .FAULT => |err| return syscall.errnoBug(err),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn fileReadStreamingWindows(file: File, data: []const []u8) File.ReadStreamingError!usize {
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var index: usize = 0;
    while (data.len - index != 0 and data[index].len == 0) index += 1;
    if (data.len - index == 0) return 0;
    const buffer = data[index];
    const short_buffer_len = std.math.lossyCast(u32, buffer.len);
    if (file.flags.nonblocking) {
        var done: bool = false;
        switch (windows.ntdll.NtReadFile(
            file.handle,
            null, // event
            flagApc,
            &done, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            null, // byte offset
            null, // key
        )) {
            // We must wait for the APC routine.
            .PENDING, .SUCCESS => while (!done) {
                // Once we get here we must not return from the function until the
                // operation completes, thereby releasing reference to the iosb.
                const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                    error.Canceled => |e| {
                        var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
                        _ = windows.ntdll.NtCancelIoFileEx(file.handle, &iosb, &cancel_iosb);
                        while (!done) waitForApcOrAlert();
                        return e;
                    },
                };
                waitForApcOrAlert();
                alertable_syscall.finish();
            },
            else => |status| iosb.u.Status = status,
        }
    } else {
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtReadFile(
            file.handle,
            null, // event
            null, // APC routine
            null, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            null, // byte offset
            null, // key
        )) {
            .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => |status| {
                syscall.finish();
                iosb.u.Status = status;
                break;
            },
        };
    }
    return ntReadFileResult(&iosb);
}

fn flagApc(userdata: ?*anyopaque, _: *windows.IO_STATUS_BLOCK, _: windows.ULONG) align(apc_align) callconv(.winapi) void {
    const flag: *bool = @ptrCast(userdata);
    flag.* = true;
}

fn ntReadFileResult(io_status_block: *const windows.IO_STATUS_BLOCK) !usize {
    switch (io_status_block.u.Status) {
        .PENDING => unreachable,
        .CANCELLED => unreachable,
        .SUCCESS => return io_status_block.Information,
        .END_OF_FILE, .PIPE_BROKEN => return error.EndOfStream,
        .INVALID_HANDLE => return error.NotOpenForReading,
        .INVALID_DEVICE_REQUEST => return error.IsDir,
        .FILE_LOCK_CONFLICT => return error.LockViolation,
        .ACCESS_DENIED => return error.AccessDenied,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn ntWriteFileResult(io_status_block: *const windows.IO_STATUS_BLOCK) !usize {
    switch (io_status_block.u.Status) {
        .PENDING => unreachable,
        .CANCELLED => unreachable,
        .SUCCESS => return io_status_block.Information,
        .INVALID_USER_BUFFER => return error.SystemResources,
        .NO_MEMORY => return error.SystemResources,
        .QUOTA_EXCEEDED => return error.SystemResources,
        .PIPE_BROKEN => return error.BrokenPipe,
        .INVALID_HANDLE => return error.NotOpenForWriting,
        .FILE_LOCK_CONFLICT => return error.LockViolation,
        .ACCESS_DENIED => return error.AccessDenied,
        .WORKING_SET_QUOTA => return error.SystemResources,
        .DISK_FULL => return error.NoSpaceLeft,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn fileReadPositionalPosix(file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    var iovecs_buffer: [max_iovecs_len]posix.iovec = undefined;
    var i: usize = 0;
    for (data) |buf| {
        if (iovecs_buffer.len - i == 0) break;
        if (buf.len != 0) {
            iovecs_buffer[i] = .{ .base = buf.ptr, .len = buf.len };
            i += 1;
        }
    }
    if (i == 0) return 0;
    const dest = iovecs_buffer[0..i];
    assert(dest[0].len > 0);

    if (native_os == .wasi and !builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            var nread: usize = undefined;
            switch (std.os.wasi.fd_pread(file.handle, dest.ptr, dest.len, offset, &nread)) {
                .SUCCESS => {
                    syscall.finish();
                    return nread;
                },
                .INTR, .TIMEDOUT => {
                    try syscall.checkCancel();
                    continue;
                },
                .NOTCONN => |err| return syscall.errnoBug(err), // not a socket
                .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err), // segmentation fault
                .AGAIN => |err| return syscall.errnoBug(err),
                .IO => return syscall.fail(error.InputOutput),
                .ISDIR => return syscall.fail(error.IsDir),
                .BADF => return syscall.fail(error.IsDir),
                .NOBUFS => return syscall.fail(error.SystemResources),
                .NOMEM => return syscall.fail(error.SystemResources),
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                .NOTCAPABLE => return syscall.fail(error.AccessDenied),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }

    if (have_preadv) {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = preadv_sym(file.handle, dest.ptr, @intCast(dest.len), @bitCast(offset));
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    return @bitCast(rc);
                },
                .INTR, .TIMEDOUT => {
                    try syscall.checkCancel();
                    continue;
                },
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                .NOBUFS => return syscall.fail(error.SystemResources),
                .NOMEM => return syscall.fail(error.SystemResources),
                .AGAIN => return syscall.fail(error.WouldBlock),
                .IO => return syscall.fail(error.InputOutput),
                .ISDIR => return syscall.fail(error.IsDir),
                .NOTCONN => |err| return syscall.errnoBug(err), // not a socket
                .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err),
                .BADF => {
                    syscall.finish();
                    if (native_os == .wasi) return error.IsDir; // File operation on directory.
                    return error.NotOpenForReading;
                },
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.pread(file.handle, dest[0].ptr, @intCast(dest[0].len), @bitCast(offset));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return @bitCast(rc);
            },
            .INTR, .TIMEDOUT => {
                try syscall.checkCancel();
                continue;
            },
            .NXIO => return syscall.fail(error.Unseekable),
            .SPIPE => return syscall.fail(error.Unseekable),
            .OVERFLOW => return syscall.fail(error.Unseekable),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .AGAIN => return syscall.fail(error.WouldBlock),
            .IO => return syscall.fail(error.InputOutput),
            .ISDIR => return syscall.fail(error.IsDir),
            .NOTCONN => |err| return syscall.errnoBug(err), // not a socket
            .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
            .INVAL => |err| return syscall.errnoBug(err),
            .FAULT => |err| return syscall.errnoBug(err),
            .BADF => {
                syscall.finish();
                if (native_os == .wasi) return error.IsDir; // File operation on directory.
                return error.NotOpenForReading;
            },
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn fileReadPositional(userdata: ?*anyopaque, file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    if (is_windows) return fileReadPositionalWindows(file, data, offset);
    return fileReadPositionalPosix(file, data, offset);
}

fn fileReadPositionalWindows(file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    var index: usize = 0;
    while (index < data.len and data[index].len == 0) index += 1;
    if (index == data.len) return 0;
    const buffer = data[index];

    return readFilePositionalWindows(file, buffer, offset);
}

fn readFilePositionalWindows(file: File, buffer: []u8, offset: u64) File.ReadPositionalError!usize {
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    const short_buffer_len = std.math.lossyCast(u32, buffer.len);
    const signed_offset: windows.LARGE_INTEGER = @intCast(offset);
    if (file.flags.nonblocking) {
        var done: bool = false;
        switch (windows.ntdll.NtReadFile(
            file.handle,
            null, // event
            flagApc,
            &done, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            &signed_offset,
            null, // key
        )) {
            // We must wait for the APC routine.
            .PENDING, .SUCCESS => while (!done) {
                // Once we get here we must not return from the function until the
                // operation completes, thereby releasing reference to the iosb.
                const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                    error.Canceled => |e| {
                        var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
                        _ = windows.ntdll.NtCancelIoFileEx(file.handle, &iosb, &cancel_iosb);
                        while (!done) waitForApcOrAlert();
                        return e;
                    },
                };
                waitForApcOrAlert();
                alertable_syscall.finish();
            },
            else => |status| iosb.u.Status = status,
        }
    } else {
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtReadFile(
            file.handle,
            null, // event
            null, // APC routine
            null, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            &signed_offset,
            null, // key
        )) {
            .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
            .CANCELLED => try syscall.checkCancel(),
            else => |status| {
                syscall.finish();
                iosb.u.Status = status;
                break;
            },
        };
    }
    return ntReadFileResult(&iosb) catch |err| switch (err) {
        error.EndOfStream => 0,
        else => |e| e,
    };
}

fn fileSeekBy(userdata: ?*anyopaque, file: File, offset: i64) File.SeekError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        var iosb: windows.IO_STATUS_BLOCK = undefined;
        var info: windows.FILE.POSITION_INFORMATION = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtQueryInformationFile(
            file.handle,
            &iosb,
            &info,
            @sizeOf(windows.FILE.POSITION_INFORMATION),
            .Position,
        )) {
            .SUCCESS => break,
            .CANCELLED => try syscall.checkCancel(),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .PIPE_NOT_AVAILABLE => return syscall.fail(error.Unseekable),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
        info.CurrentByteOffset = @bitCast((if (offset >= 0) std.math.add(
            u64,
            @bitCast(info.CurrentByteOffset),
            @intCast(offset),
        ) else std.math.sub(
            u64,
            @bitCast(info.CurrentByteOffset),
            @intCast(-offset),
        )) catch |err| switch (err) {
            error.Overflow => return syscall.fail(error.Unseekable),
        });
        while (true) switch (windows.ntdll.NtSetInformationFile(
            file.handle,
            &iosb,
            &info,
            @sizeOf(windows.FILE.POSITION_INFORMATION),
            .Position,
        )) {
            .SUCCESS => return syscall.finish(),
            .CANCELLED => try syscall.checkCancel(),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .PIPE_NOT_AVAILABLE => return syscall.fail(error.Unseekable),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    if (native_os == .wasi and !builtin.link_libc) {
        var new_offset: std.os.wasi.filesize_t = undefined;
        const syscall: Syscall = try .start();
        while (true) {
            switch (std.os.wasi.fd_seek(file.handle, offset, .CUR, &new_offset)) {
                .SUCCESS => {
                    syscall.finish();
                    return;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => return error.Unseekable,
                        .OVERFLOW => return error.Unseekable,
                        .SPIPE => return error.Unseekable,
                        .NXIO => return error.Unseekable,
                        .NOTCAPABLE => return error.AccessDenied,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    if (posix.SEEK == void) return error.Unseekable;

    if (native_os == .linux and !builtin.link_libc and @sizeOf(usize) == 4) {
        var result: u64 = undefined;
        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(posix.system.llseek(file.handle, @bitCast(offset), &result, posix.SEEK.CUR))) {
                .SUCCESS => {
                    syscall.finish();
                    return;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => return error.Unseekable,
                        .OVERFLOW => return error.Unseekable,
                        .SPIPE => return error.Unseekable,
                        .NXIO => return error.Unseekable,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(lseek_sym(file.handle, offset, posix.SEEK.CUR))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .INVAL => return error.Unseekable,
                    .OVERFLOW => return error.Unseekable,
                    .SPIPE => return error.Unseekable,
                    .NXIO => return error.Unseekable,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileSeekTo(userdata: ?*anyopaque, file: File, offset: u64) File.SeekError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        var iosb: windows.IO_STATUS_BLOCK = undefined;
        var info: windows.FILE.POSITION_INFORMATION = .{ .CurrentByteOffset = @bitCast(offset) };
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtSetInformationFile(
            file.handle,
            &iosb,
            &info,
            @sizeOf(windows.FILE.POSITION_INFORMATION),
            .Position,
        )) {
            .SUCCESS => return syscall.finish(),
            .CANCELLED => try syscall.checkCancel(),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .PIPE_NOT_AVAILABLE => return syscall.fail(error.Unseekable),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    if (native_os == .wasi and !builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            var new_offset: std.os.wasi.filesize_t = undefined;
            switch (std.os.wasi.fd_seek(file.handle, @bitCast(offset), .SET, &new_offset)) {
                .SUCCESS => {
                    syscall.finish();
                    return;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => return error.Unseekable,
                        .OVERFLOW => return error.Unseekable,
                        .SPIPE => return error.Unseekable,
                        .NXIO => return error.Unseekable,
                        .NOTCAPABLE => return error.AccessDenied,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    if (posix.SEEK == void) return error.Unseekable;

    return posixSeekTo(file.handle, offset);
}

fn posixSeekTo(fd: posix.fd_t, offset: u64) File.SeekError!void {
    if (native_os == .linux and !builtin.link_libc and @sizeOf(usize) == 4) {
        const syscall: Syscall = try .start();
        while (true) {
            var result: u64 = undefined;
            switch (posix.errno(posix.system.llseek(fd, offset, &result, posix.SEEK.SET))) {
                .SUCCESS => {
                    syscall.finish();
                    return;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .INVAL => return error.Unseekable,
                        .OVERFLOW => return error.Unseekable,
                        .SPIPE => return error.Unseekable,
                        .NXIO => return error.Unseekable,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(lseek_sym(fd, @bitCast(offset), posix.SEEK.SET))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .INVAL => return error.Unseekable,
                    .OVERFLOW => return error.Unseekable,
                    .SPIPE => return error.Unseekable,
                    .NXIO => return error.Unseekable,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn processExecutableOpen(userdata: ?*anyopaque, flags: Dir.OpenFileOptions) process.OpenExecutableError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    switch (native_os) {
        .wasi => return error.OperationUnsupported,
        .linux, .serenity => return dirOpenFilePosix(t, .{ .handle = posix.AT.FDCWD }, "/proc/self/exe", flags),
        .windows => {
            // If ImagePathName is a symlink, then it will contain the path of the symlink,
            // not the path that the symlink points to. However, because we are opening
            // the file, we can let the openFileW call follow the symlink for us.
            const image_path_name = windows.peb().ProcessParameters.ImagePathName.sliceZ();
            const prefixed_path_w = try wToPrefixedFileW(null, image_path_name, .{});
            return dirOpenFileWtf16(null, prefixed_path_w.span(), flags);
        },
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        => {
            // _NSGetExecutablePath() returns a path that might be a symlink to
            // the executable. Here it does not matter since we open it.
            var symlink_path_buf: [posix.PATH_MAX + 1]u8 = undefined;
            var n: u32 = symlink_path_buf.len;
            const rc = std.c._NSGetExecutablePath(&symlink_path_buf, &n);
            if (rc != 0) return error.NameTooLong;
            const symlink_path = std.mem.sliceTo(&symlink_path_buf, 0);
            return dirOpenFilePosix(t, .cwd(), symlink_path, flags);
        },
        else => {
            var buffer: [Dir.max_path_bytes]u8 = undefined;
            const n = try processExecutablePath(t, &buffer);
            buffer[n] = 0;
            const executable_path = buffer[0..n :0];
            return dirOpenFilePosix(t, .cwd(), executable_path, flags);
        },
    }
}

fn processExecutablePath(userdata: ?*anyopaque, out_buffer: []u8) process.ExecutablePathError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    switch (native_os) {
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        => {
            // _NSGetExecutablePath() returns a path that might be a symlink to
            // the executable.
            var symlink_path_buf: [posix.PATH_MAX + 1]u8 = undefined;
            var n: u32 = symlink_path_buf.len;
            const rc = std.c._NSGetExecutablePath(&symlink_path_buf, &n);
            if (rc != 0) return error.NameTooLong;
            const symlink_path = std.mem.sliceTo(&symlink_path_buf, 0);
            return Io.Dir.realPathFileAbsolute(io(t), symlink_path, out_buffer) catch |err| switch (err) {
                error.NetworkNotFound => unreachable, // Windows-only
                error.FileBusy => unreachable, // Windows-only
                else => |e| return e,
            };
        },
        .linux, .serenity => return Io.Dir.readLinkAbsolute(io(t), "/proc/self/exe", out_buffer) catch |err| switch (err) {
            error.UnsupportedReparsePointType => unreachable, // Windows-only
            error.NetworkNotFound => unreachable, // Windows-only
            error.FileBusy => unreachable, // Windows-only
            else => |e| return e,
        },
        .illumos => return Io.Dir.readLinkAbsolute(io(t), "/proc/self/path/a.out", out_buffer) catch |err| switch (err) {
            error.UnsupportedReparsePointType => unreachable, // Windows-only
            error.NetworkNotFound => unreachable, // Windows-only
            error.FileBusy => unreachable, // Windows-only
            else => |e| return e,
        },
        .freebsd, .dragonfly => {
            var mib: [4]c_int = .{ posix.CTL.KERN, posix.KERN.PROC, posix.KERN.PROC_PATHNAME, -1 };
            var out_len: usize = out_buffer.len;
            const syscall: Syscall = try .start();
            while (true) switch (posix.errno(posix.system.sysctl(&mib, mib.len, out_buffer.ptr, &out_len, null, 0))) {
                .SUCCESS => {
                    syscall.finish();
                    return out_len - 1; // discard terminating NUL
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .PERM => return syscall.fail(error.PermissionDenied),
                .NOMEM => return syscall.fail(error.SystemResources),
                .FAULT => |err| return syscall.errnoBug(err),
                .NOENT => |err| return syscall.errnoBug(err),
                else => |err| return syscall.unexpectedErrno(err),
            };
        },
        .netbsd => {
            var mib = [4]c_int{ posix.CTL.KERN, posix.KERN.PROC_ARGS, -1, posix.KERN.PROC_PATHNAME };
            var out_len: usize = out_buffer.len;
            const syscall: Syscall = try .start();
            while (true) {
                switch (posix.errno(posix.system.sysctl(&mib, mib.len, out_buffer.ptr, &out_len, null, 0))) {
                    .SUCCESS => {
                        syscall.finish();
                        return out_len - 1; // discard terminating NUL
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    .PERM => return syscall.fail(error.PermissionDenied),
                    .NOMEM => return syscall.fail(error.SystemResources),
                    .FAULT => |err| return syscall.errnoBug(err),
                    .NOENT => |err| return syscall.errnoBug(err),
                    else => |err| return syscall.unexpectedErrno(err),
                }
            }
        },
        .openbsd, .haiku => {
            // The best we can do on these operating systems is check based on
            // the first process argument.
            const argv0 = std.mem.span(t.argv0.value orelse return error.OperationUnsupported);
            if (std.mem.findScalar(u8, argv0, '/') != null) {
                // argv[0] is a path (relative or absolute): use realpath(3) directly
                var resolved_buf: [std.c.PATH_MAX]u8 = undefined;
                const syscall: Syscall = try .start();
                while (true) {
                    if (std.c.realpath(argv0, &resolved_buf)) |p| {
                        assert(p == &resolved_buf);
                        break syscall.finish();
                    } else switch (@as(std.c.E, @enumFromInt(std.c._errno().*))) {
                        .INTR => {
                            try syscall.checkCancel();
                            continue;
                        },
                        else => |e| {
                            syscall.finish();
                            switch (e) {
                                .ACCES => return error.AccessDenied,
                                .INVAL => |err| return errnoBug(err), // the pathname argument is a null pointer
                                .IO => return error.InputOutput,
                                .LOOP => return error.SymLinkLoop,
                                .NAMETOOLONG => return error.NameTooLong,
                                .NOENT => return error.FileNotFound,
                                .NOTDIR => return error.NotDir,
                                .NOMEM => |err| return errnoBug(err), // sufficient storage space is unavailable for allocation
                                else => |err| return posix.unexpectedErrno(err),
                            }
                        },
                    }
                }
                const resolved = std.mem.sliceTo(&resolved_buf, 0);
                if (resolved.len > out_buffer.len)
                    return error.NameTooLong;
                @memcpy(out_buffer[0..resolved.len], resolved);
                return resolved.len;
            } else if (argv0.len != 0) {
                // argv[0] is not empty (and not a path): search PATH
                t.scanEnviron();
                const PATH = t.environ.string.PATH orelse return error.FileNotFound;
                var it = std.mem.tokenizeScalar(u8, PATH, ':');
                it: while (it.next()) |dir| {
                    var resolved_path_buf: [std.c.PATH_MAX]u8 = undefined;
                    const resolved_path = std.fmt.bufPrintSentinel(&resolved_path_buf, "{s}/{s}", .{
                        dir, argv0,
                    }, 0) catch continue;

                    var resolved_buf: [std.c.PATH_MAX]u8 = undefined;
                    const syscall: Syscall = try .start();
                    while (true) {
                        if (std.c.realpath(resolved_path, &resolved_buf)) |p| {
                            assert(p == &resolved_buf);
                            break syscall.finish();
                        } else switch (@as(std.c.E, @enumFromInt(std.c._errno().*))) {
                            .INTR => {
                                try syscall.checkCancel();
                                continue;
                            },
                            .NAMETOOLONG => {
                                syscall.finish();
                                return error.NameTooLong;
                            },
                            .NOMEM => {
                                syscall.finish();
                                return error.SystemResources;
                            },
                            .IO => {
                                syscall.finish();
                                return error.InputOutput;
                            },
                            .ACCES, .LOOP, .NOENT, .NOTDIR => {
                                syscall.finish();
                                continue :it;
                            },
                            else => |err| {
                                syscall.finish();
                                return posix.unexpectedErrno(err);
                            },
                        }
                    }
                    const resolved = std.mem.sliceTo(&resolved_buf, 0);
                    if (resolved.len > out_buffer.len)
                        return error.NameTooLong;
                    @memcpy(out_buffer[0..resolved.len], resolved);
                    return resolved.len;
                }
            }
            return error.FileNotFound;
        },
        .windows => {
            // If ImagePathName is a symlink, then it will contain the path of the
            // symlink, not the path that the symlink points to. We want the path
            // that the symlink points to, though, so we need to get the realpath.
            var path_name_w_buf = try wToPrefixedFileW(
                null,
                windows.peb().ProcessParameters.ImagePathName.sliceZ(),
                .{},
            );

            const h_file = handle: {
                if (OpenFile(path_name_w_buf.span(), .{
                    .dir = null,
                    .access_mask = .{
                        .GENERIC = .{ .READ = true },
                        .STANDARD = .{ .SYNCHRONIZE = true },
                    },
                    .creation = .OPEN,
                    .filter = .any,
                })) |handle| {
                    break :handle handle;
                } else |err| switch (err) {
                    error.WouldBlock => unreachable,
                    error.FileBusy => unreachable,
                    else => |e| return e,
                }
            };
            defer windows.CloseHandle(h_file);

            const wide_slice = try GetFinalPathNameByHandle(h_file, .{}, &path_name_w_buf.data);

            const len = std.unicode.calcWtf8Len(wide_slice);
            if (len > out_buffer.len)
                return error.NameTooLong;

            const end_index = std.unicode.wtf16LeToWtf8(out_buffer, wide_slice);
            return end_index;
        },
        else => return error.OperationUnsupported,
    }
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) File.WritePositionalError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        if (header.len != 0) {
            return writeFilePositionalWindows(file, header, offset);
        }
        for (data[0 .. data.len - 1]) |buf| {
            if (buf.len == 0) continue;
            return writeFilePositionalWindows(file, buf, offset);
        }
        const pattern = data[data.len - 1];
        if (pattern.len == 0 or splat == 0) return 0;
        return writeFilePositionalWindows(file, pattern, offset);
    }

    var iovecs: [max_iovecs_len]posix.iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    addBuf(&iovecs, &iovlen, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(&iovecs, &iovlen, bytes);
    const pattern = data[data.len - 1];

    var splat_backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0) switch (splat) {
        0 => {},
        1 => addBuf(&iovecs, &iovlen, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &splat_backup_buffer;
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

    if (iovlen == 0) return 0;

    if (native_os == .wasi and !builtin.link_libc) {
        var n_written: usize = undefined;
        const syscall: Syscall = try .start();
        while (true) {
            switch (std.os.wasi.fd_pwrite(file.handle, &iovecs, iovlen, offset, &n_written)) {
                .SUCCESS => {
                    syscall.finish();
                    return n_written;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .INVAL => |err| return errnoBug(err),
                        .FAULT => |err| return errnoBug(err),
                        .AGAIN => |err| return errnoBug(err),
                        .BADF => return error.NotOpenForWriting,
                        .DESTADDRREQ => |err| return errnoBug(err), // `connect` was never called.
                        .DQUOT => return error.DiskQuota,
                        .FBIG => return error.FileTooBig,
                        .IO => return error.InputOutput,
                        .NOSPC => return error.NoSpaceLeft,
                        .PERM => return error.PermissionDenied,
                        .PIPE => return error.BrokenPipe,
                        .NOTCAPABLE => return error.AccessDenied,
                        .NXIO => return error.Unseekable,
                        .SPIPE => return error.Unseekable,
                        .OVERFLOW => return error.Unseekable,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = pwritev_sym(file.handle, &iovecs, @intCast(iovlen), @bitCast(offset));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return @intCast(rc);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .INVAL => |err| return syscall.errnoBug(err),
            .FAULT => |err| return syscall.errnoBug(err),
            .DESTADDRREQ => |err| return syscall.errnoBug(err), // `connect` was never called.
            .CONNRESET => |err| return syscall.errnoBug(err), // Not a socket handle.
            .BADF => return syscall.fail(error.NotOpenForWriting),
            .AGAIN => return syscall.fail(error.WouldBlock),
            .DQUOT => return syscall.fail(error.DiskQuota),
            .FBIG => return syscall.fail(error.FileTooBig),
            .IO => return syscall.fail(error.InputOutput),
            .NOSPC => return syscall.fail(error.NoSpaceLeft),
            .PERM => return syscall.fail(error.PermissionDenied),
            .PIPE => return syscall.fail(error.BrokenPipe),
            .BUSY => return syscall.fail(error.DeviceBusy),
            .TXTBSY => return syscall.fail(error.FileBusy),
            .NXIO => return syscall.fail(error.Unseekable),
            .SPIPE => return syscall.fail(error.Unseekable),
            .OVERFLOW => return syscall.fail(error.Unseekable),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn writeFilePositionalWindows(file: File, buffer: []const u8, offset: u64) File.WritePositionalError!usize {
    assert(buffer.len != 0);
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    const short_buffer_len = std.math.lossyCast(u32, buffer.len);
    const signed_offset: windows.LARGE_INTEGER = @intCast(offset);
    if (file.flags.nonblocking) {
        var done: bool = false;
        switch (windows.ntdll.NtWriteFile(
            file.handle,
            null, // event
            flagApc,
            &done, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            &signed_offset,
            null, // key
        )) {
            // We must wait for the APC routine.
            .PENDING, .SUCCESS => while (!done) {
                // Once we get here we must not return from the function until the
                // operation completes, thereby releasing reference to the iosb.
                const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                    error.Canceled => |e| {
                        var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
                        _ = windows.ntdll.NtCancelIoFileEx(file.handle, &iosb, &cancel_iosb);
                        while (!done) waitForApcOrAlert();
                        return e;
                    },
                };
                waitForApcOrAlert();
                alertable_syscall.finish();
            },
            else => |status| iosb.u.Status = status,
        }
    } else {
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtWriteFile(
            file.handle,
            null, // event
            null, // APC routine
            null, // APC context
            &iosb,
            buffer.ptr,
            short_buffer_len,
            &signed_offset,
            null, // key
        )) {
            .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
            .CANCELLED => try syscall.checkCancel(),
            else => |status| {
                syscall.finish();
                iosb.u.Status = status;
                return ntWriteFileResult(&iosb);
            },
        };
    }
    return ntWriteFileResult(&iosb);
}

fn fileWriteStreaming(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) File.Writer.Error!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (is_windows) {
        const buffer = windowsWriteBuffer(header, data, splat);
        if (buffer.len == 0) return 0;
        return fileWriteStreamingWindows(file, buffer);
    }

    var iovecs: [max_iovecs_len]posix.iovec_const = undefined;
    var iovlen: iovlen_t = 0;
    addBuf(&iovecs, &iovlen, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(&iovecs, &iovlen, bytes);
    const pattern = data[data.len - 1];

    var splat_backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - iovlen != 0) switch (splat) {
        0 => {},
        1 => addBuf(&iovecs, &iovlen, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &splat_backup_buffer;
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

    if (iovlen == 0) return 0;

    if (native_os == .wasi and !builtin.link_libc) {
        var n_written: usize = undefined;
        const syscall: Syscall = try .start();
        while (true) {
            switch (std.os.wasi.fd_write(file.handle, &iovecs, iovlen, &n_written)) {
                .SUCCESS => {
                    syscall.finish();
                    return n_written;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .INVAL => |err| return errnoBug(err),
                        .FAULT => |err| return errnoBug(err),
                        .AGAIN => |err| return errnoBug(err),
                        .BADF => return error.NotOpenForWriting, // can be a race condition.
                        .DESTADDRREQ => |err| return errnoBug(err), // `connect` was never called.
                        .DQUOT => return error.DiskQuota,
                        .FBIG => return error.FileTooBig,
                        .IO => return error.InputOutput,
                        .NOSPC => return error.NoSpaceLeft,
                        .PERM => return error.PermissionDenied,
                        .PIPE => return error.BrokenPipe,
                        .NOTCAPABLE => return error.AccessDenied,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.writev(file.handle, &iovecs, @intCast(iovlen));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return @intCast(rc);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
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
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn fileWriteStreamingWindows(file: File, buffer: []const u8) File.Writer.Error!usize {
    assert(buffer.len != 0);
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    if (file.flags.nonblocking) {
        var done: bool = false;
        switch (windows.ntdll.NtWriteFile(
            file.handle,
            null, // event
            flagApc,
            &done, // APC context
            &iosb,
            buffer.ptr,
            @intCast(buffer.len),
            null, // byte offset
            null, // key
        )) {
            // We must wait for the APC routine.
            .PENDING, .SUCCESS => while (!done) {
                // Once we get here we must not return from the function until the
                // operation completes, thereby releasing reference to io_status_block.
                const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                    error.Canceled => |e| {
                        var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
                        _ = windows.ntdll.NtCancelIoFileEx(file.handle, &iosb, &cancel_iosb);
                        while (!done) waitForApcOrAlert();
                        return e;
                    },
                };
                waitForApcOrAlert();
                alertable_syscall.finish();
            },
            else => |status| iosb.u.Status = status,
        }
    } else {
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtWriteFile(
            file.handle,
            null, // event
            null, // APC routine
            null, // APC context
            &iosb,
            buffer.ptr,
            @intCast(buffer.len),
            null, // byte offset
            null, // key
        )) {
            .PENDING => unreachable, // unrecoverable: wrong File nonblocking flag
            .CANCELLED => try syscall.checkCancel(),
            else => |status| {
                syscall.finish();
                iosb.u.Status = status;
                break;
            },
        };
    }
    return ntWriteFileResult(&iosb);
}

fn fileWriteFileStreaming(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) File.Writer.WriteFileError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @intFromEnum(limit)) {
        const n = try fileWriteStreaming(t, file, header, &.{limit.slice(reader_buffered)}, 1);
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    const file_limit = @intFromEnum(limit) - reader_buffered.len;
    const out_fd = file.handle;
    const in_fd = file_reader.file.handle;

    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWriteStreaming(t, file, header, &.{limit.slice(reader_buffered)}, 1);
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }

    if (native_os == .freebsd) sf: {
        // Try using sendfile on FreeBSD.
        if (@atomicLoad(UseSendfile, &t.use_sendfile, .monotonic) == .disabled) break :sf;
        const offset = std.math.cast(std.c.off_t, file_reader.pos) orelse break :sf;
        var hdtr_data: std.c.sf_hdtr = undefined;
        var headers: [2]posix.iovec_const = undefined;
        var headers_i: u8 = 0;
        if (header.len != 0) {
            headers[headers_i] = .{ .base = header.ptr, .len = header.len };
            headers_i += 1;
        }
        if (reader_buffered.len != 0) {
            headers[headers_i] = .{ .base = reader_buffered.ptr, .len = reader_buffered.len };
            headers_i += 1;
        }
        const hdtr: ?*std.c.sf_hdtr = if (headers_i == 0) null else b: {
            hdtr_data = .{
                .headers = &headers,
                .hdr_cnt = headers_i,
                .trailers = null,
                .trl_cnt = 0,
            };
            break :b &hdtr_data;
        };
        var sbytes: std.c.off_t = 0;
        const nbytes: usize = @min(file_limit, std.math.maxInt(usize));
        const flags = 0;

        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(std.c.sendfile(in_fd, out_fd, offset, nbytes, hdtr, &sbytes, flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INVAL, .OPNOTSUPP, .NOTSOCK, .NOSYS => {
                    // Give calling code chance to observe before trying
                    // something else.
                    syscall.finish();
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
                .INTR, .BUSY => {
                    if (sbytes == 0) {
                        try syscall.checkCancel();
                        continue;
                    } else {
                        // Even if we are being canceled, there have been side
                        // effects, so it is better to report those side
                        // effects to the caller.
                        syscall.finish();
                        break;
                    }
                },
                .AGAIN => {
                    syscall.finish();
                    if (sbytes == 0) return error.WouldBlock;
                    break;
                },
                else => |e| {
                    syscall.finish();
                    assert(error.Unexpected == switch (e) {
                        .NOTCONN => return error.BrokenPipe,
                        .IO => return error.InputOutput,
                        .PIPE => return error.BrokenPipe,
                        .NOBUFS => return error.SystemResources,
                        .BADF => |err| errnoBug(err),
                        .FAULT => |err| errnoBug(err),
                        else => |err| posix.unexpectedErrno(err),
                    });
                    // Give calling code chance to observe the error before trying
                    // something else.
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
            }
        }
        if (sbytes == 0) {
            file_reader.size = file_reader.pos;
            return error.EndOfStream;
        }
        const ubytes: usize = @intCast(sbytes);
        file_reader.interface.toss(ubytes -| header.len);
        return ubytes;
    }

    if (is_darwin) sf: {
        // Try using sendfile on macOS.
        if (@atomicLoad(UseSendfile, &t.use_sendfile, .monotonic) == .disabled) break :sf;
        const offset = std.math.cast(std.c.off_t, file_reader.pos) orelse break :sf;
        var hdtr_data: std.c.sf_hdtr = undefined;
        var headers: [2]posix.iovec_const = undefined;
        var headers_i: u8 = 0;
        if (header.len != 0) {
            headers[headers_i] = .{ .base = header.ptr, .len = header.len };
            headers_i += 1;
        }
        if (reader_buffered.len != 0) {
            headers[headers_i] = .{ .base = reader_buffered.ptr, .len = reader_buffered.len };
            headers_i += 1;
        }
        const hdtr: ?*std.c.sf_hdtr = if (headers_i == 0) null else b: {
            hdtr_data = .{
                .headers = &headers,
                .hdr_cnt = headers_i,
                .trailers = null,
                .trl_cnt = 0,
            };
            break :b &hdtr_data;
        };
        const max_count = std.math.maxInt(i32); // Avoid EINVAL.
        var len: std.c.off_t = @min(file_limit, max_count);
        const flags = 0;
        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.errno(std.c.sendfile(in_fd, out_fd, offset, &len, hdtr, flags))) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .OPNOTSUPP, .NOTSOCK, .NOSYS => {
                    // Give calling code chance to observe before trying
                    // something else.
                    syscall.finish();
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
                .INTR => {
                    if (len == 0) {
                        try syscall.checkCancel();
                        continue;
                    } else {
                        // Even if we are being canceled, there have been side
                        // effects, so it is better to report those side
                        // effects to the caller.
                        syscall.finish();
                        break;
                    }
                },
                .AGAIN => {
                    syscall.finish();
                    if (len == 0) return error.WouldBlock;
                    break;
                },
                else => |e| {
                    syscall.finish();
                    assert(error.Unexpected == switch (e) {
                        .NOTCONN => return error.BrokenPipe,
                        .IO => return error.InputOutput,
                        .PIPE => return error.BrokenPipe,
                        .BADF => |err| errnoBug(err),
                        .FAULT => |err| errnoBug(err),
                        .INVAL => |err| errnoBug(err),
                        else => |err| posix.unexpectedErrno(err),
                    });
                    // Give calling code chance to observe the error before trying
                    // something else.
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
            }
        }
        if (len == 0) {
            file_reader.size = file_reader.pos;
            return error.EndOfStream;
        }
        const u_len: usize = @bitCast(len);
        file_reader.interface.toss(u_len -| header.len);
        return u_len;
    }

    if (native_os == .linux) sf: {
        // Try using sendfile on Linux.
        if (@atomicLoad(UseSendfile, &t.use_sendfile, .monotonic) == .disabled) break :sf;
        // Linux sendfile does not support headers.
        if (header.len != 0 or reader_buffered.len != 0) {
            const n = try fileWriteStreaming(t, file, header, &.{limit.slice(reader_buffered)}, 1);
            file_reader.interface.toss(n -| header.len);
            return n;
        }
        const max_count = 0x7ffff000; // Avoid EINVAL.
        var off: std.os.linux.off_t = undefined;
        const off_ptr: ?*std.os.linux.off_t, const count: usize = switch (file_reader.mode) {
            .positional => o: {
                const size = file_reader.getSize() catch return 0;
                off = std.math.cast(std.os.linux.off_t, file_reader.pos) orelse return error.ReadFailed;
                break :o .{ &off, @min(@intFromEnum(limit), size - file_reader.pos, max_count) };
            },
            .streaming => .{ null, limit.minInt(max_count) },
            .streaming_simple, .positional_simple => break :sf,
            .failure => return error.ReadFailed,
        };
        const syscall: Syscall = try .start();
        const n: usize = while (true) {
            const rc = sendfile_sym(out_fd, in_fd, off_ptr, count);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break @intCast(rc);
                },
                .NOSYS, .INVAL => {
                    // Give calling code chance to observe before trying
                    // something else.
                    syscall.finish();
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    assert(error.Unexpected == switch (e) {
                        .NOTCONN => return error.BrokenPipe, // `out_fd` is an unconnected socket
                        .AGAIN => return error.WouldBlock,
                        .IO => return error.InputOutput,
                        .PIPE => return error.BrokenPipe,
                        .NOMEM => return error.SystemResources,
                        .NXIO, .SPIPE => {
                            file_reader.mode = file_reader.mode.toStreaming();
                            const pos = file_reader.pos;
                            if (pos != 0) {
                                file_reader.pos = 0;
                                file_reader.seekBy(@intCast(pos)) catch {
                                    file_reader.mode = .failure;
                                    return error.ReadFailed;
                                };
                            }
                            return 0;
                        },
                        .BADF => |err| errnoBug(err), // Always a race condition.
                        .FAULT => |err| errnoBug(err), // Segmentation fault.
                        .OVERFLOW => |err| errnoBug(err), // We avoid passing too large of a `count`.
                        else => |err| posix.unexpectedErrno(err),
                    });
                    // Give calling code chance to observe the error before trying
                    // something else.
                    @atomicStore(UseSendfile, &t.use_sendfile, .disabled, .monotonic);
                    return 0;
                },
            }
        };
        if (n == 0) {
            file_reader.size = file_reader.pos;
            return error.EndOfStream;
        }
        file_reader.pos += n;
        return n;
    }

    if (have_copy_file_range) cfr: {
        if (@atomicLoad(UseCopyFileRange, &t.use_copy_file_range, .monotonic) == .disabled) break :cfr;
        if (header.len != 0 or reader_buffered.len != 0) {
            const n = try fileWriteStreaming(t, file, header, &.{limit.slice(reader_buffered)}, 1);
            file_reader.interface.toss(n -| header.len);
            return n;
        }
        var len: usize = @intFromEnum(limit);
        var off_in: i64 = undefined;
        const off_in_ptr: ?*i64 = switch (file_reader.mode) {
            .positional_simple, .streaming_simple => return error.Unimplemented,
            .positional => p: {
                len = @min(len, std.math.maxInt(usize) - file_reader.pos);
                off_in = @intCast(file_reader.pos);
                break :p &off_in;
            },
            .streaming => null,
            .failure => return error.ReadFailed,
        };
        const n: usize = switch (native_os) {
            .linux => n: {
                const syscall: Syscall = try .start();
                while (true) {
                    const rc = linux_copy_file_range_sys.copy_file_range(in_fd, off_in_ptr, out_fd, null, len, 0);
                    switch (linux_copy_file_range_sys.errno(rc)) {
                        .SUCCESS => {
                            syscall.finish();
                            break :n @intCast(rc);
                        },
                        .INTR => {
                            try syscall.checkCancel();
                            continue;
                        },
                        .OPNOTSUPP, .INVAL, .NOSYS => {
                            // Give calling code chance to observe before trying
                            // something else.
                            syscall.finish();
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                        else => |e| {
                            syscall.finish();
                            assert(error.Unexpected == switch (e) {
                                .FBIG => return error.FileTooBig,
                                .IO => return error.InputOutput,
                                .NOMEM => return error.SystemResources,
                                .NOSPC => return error.NoSpaceLeft,
                                .OVERFLOW => |err| errnoBug(err), // We avoid passing too large a count.
                                .PERM => return error.PermissionDenied,
                                .BUSY => return error.DeviceBusy,
                                .TXTBSY => return error.FileBusy,
                                // copy_file_range can still work but not on
                                // this pair of file descriptors.
                                .XDEV => return error.Unimplemented,
                                .ISDIR => |err| errnoBug(err),
                                .BADF => |err| errnoBug(err),
                                else => |err| posix.unexpectedErrno(err),
                            });
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                    }
                }
            },
            .freebsd => n: {
                const syscall: Syscall = try .start();
                while (true) {
                    const rc = std.c.copy_file_range(in_fd, off_in_ptr, out_fd, null, @intFromEnum(limit), 0);
                    switch (std.c.errno(rc)) {
                        .SUCCESS => {
                            syscall.finish();
                            break :n @intCast(rc);
                        },
                        .INTR => {
                            try syscall.checkCancel();
                            continue;
                        },
                        .OPNOTSUPP, .INVAL, .NOSYS => {
                            // Give calling code chance to observe before trying
                            // something else.
                            syscall.finish();
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                        else => |e| {
                            syscall.finish();
                            assert(error.Unexpected == switch (e) {
                                .FBIG => return error.FileTooBig,
                                .IO => return error.InputOutput,
                                .INTEGRITY => return error.CorruptedData,
                                .NOSPC => return error.NoSpaceLeft,
                                .ISDIR => |err| errnoBug(err),
                                .BADF => |err| errnoBug(err),
                                else => |err| posix.unexpectedErrno(err),
                            });
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                    }
                }
            },
            else => comptime unreachable,
        };
        if (n == 0) {
            file_reader.size = file_reader.pos;
            return error.EndOfStream;
        }
        file_reader.pos += n;
        return n;
    }

    return error.Unimplemented;
}

fn netWriteFile(
    userdata: ?*anyopaque,
    socket_handle: net.Socket.Handle,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
) net.Stream.Writer.WriteFileError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    _ = socket_handle;
    _ = header;
    _ = file_reader;
    _ = limit;
    @panic("TODO implement netWriteFile");
}

fn fileWriteFilePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    file_reader: *File.Reader,
    limit: Io.Limit,
    offset: u64,
) File.WriteFilePositionalError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const reader_buffered = file_reader.interface.buffered();
    if (reader_buffered.len >= @intFromEnum(limit)) {
        const n = try fileWritePositional(t, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
        file_reader.interface.toss(n -| header.len);
        return n;
    }
    const out_fd = file.handle;
    const in_fd = file_reader.file.handle;

    if (file_reader.size) |size| {
        if (size - file_reader.pos == 0) {
            if (reader_buffered.len != 0) {
                const n = try fileWritePositional(t, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
                file_reader.interface.toss(n -| header.len);
                return n;
            } else {
                return error.EndOfStream;
            }
        }
    }

    if (have_copy_file_range) cfr: {
        if (@atomicLoad(UseCopyFileRange, &t.use_copy_file_range, .monotonic) == .disabled) break :cfr;
        if (header.len != 0 or reader_buffered.len != 0) {
            const n = try fileWritePositional(t, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
            file_reader.interface.toss(n -| header.len);
            return n;
        }
        var len: usize = @min(@intFromEnum(limit), std.math.maxInt(usize) - offset);
        var off_in: i64 = undefined;
        const off_in_ptr: ?*i64 = switch (file_reader.mode) {
            .positional_simple, .streaming_simple => return error.Unimplemented,
            .positional => p: {
                len = @min(len, std.math.maxInt(usize) - file_reader.pos);
                off_in = @intCast(file_reader.pos);
                break :p &off_in;
            },
            .streaming => null,
            .failure => return error.ReadFailed,
        };
        var off_out: i64 = @intCast(offset);
        const n: usize = switch (native_os) {
            .linux => n: {
                const syscall: Syscall = try .start();
                while (true) {
                    const rc = linux_copy_file_range_sys.copy_file_range(in_fd, off_in_ptr, out_fd, &off_out, len, 0);
                    switch (linux_copy_file_range_sys.errno(rc)) {
                        .SUCCESS => {
                            syscall.finish();
                            break :n @intCast(rc);
                        },
                        .INTR => {
                            try syscall.checkCancel();
                            continue;
                        },
                        .OPNOTSUPP, .INVAL, .NOSYS => {
                            // Give calling code chance to observe before trying
                            // something else.
                            syscall.finish();
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                        else => |e| {
                            syscall.finish();
                            assert(error.Unexpected == switch (e) {
                                .FBIG => return error.FileTooBig,
                                .IO => return error.InputOutput,
                                .NOMEM => return error.SystemResources,
                                .NOSPC => return error.NoSpaceLeft,
                                .OVERFLOW => |err| errnoBug(err), // We avoid passing too large a count.
                                .NXIO => return error.Unseekable,
                                .SPIPE => return error.Unseekable,
                                .PERM => return error.PermissionDenied,
                                .TXTBSY => return error.FileBusy,
                                // copy_file_range can still work but not on
                                // this pair of file descriptors.
                                .XDEV => return error.Unimplemented,
                                .ISDIR => |err| errnoBug(err),
                                .BADF => |err| errnoBug(err),
                                else => |err| posix.unexpectedErrno(err),
                            });
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                    }
                }
            },
            .freebsd => n: {
                const syscall: Syscall = try .start();
                while (true) {
                    const rc = std.c.copy_file_range(in_fd, off_in_ptr, out_fd, &off_out, @intFromEnum(limit), 0);
                    switch (std.c.errno(rc)) {
                        .SUCCESS => {
                            syscall.finish();
                            break :n @intCast(rc);
                        },
                        .INTR => {
                            try syscall.checkCancel();
                            continue;
                        },
                        .OPNOTSUPP, .INVAL, .NOSYS => {
                            // Give calling code chance to observe before trying
                            // something else.
                            syscall.finish();
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                        else => |e| {
                            syscall.finish();
                            assert(error.Unexpected == switch (e) {
                                .FBIG => return error.FileTooBig,
                                .IO => return error.InputOutput,
                                .INTEGRITY => return error.CorruptedData,
                                .NOSPC => return error.NoSpaceLeft,
                                .OVERFLOW => return error.Unseekable,
                                .NXIO => return error.Unseekable,
                                .SPIPE => return error.Unseekable,
                                .ISDIR => |err| errnoBug(err),
                                .BADF => |err| errnoBug(err),
                                else => |err| posix.unexpectedErrno(err),
                            });
                            @atomicStore(UseCopyFileRange, &t.use_copy_file_range, .disabled, .monotonic);
                            return 0;
                        },
                    }
                }
            },
            else => comptime unreachable,
        };
        if (n == 0) {
            file_reader.size = file_reader.pos;
            return error.EndOfStream;
        }
        file_reader.pos += n;
        return n;
    }

    if (is_darwin) fcf: {
        if (@atomicLoad(UseFcopyfile, &t.use_fcopyfile, .monotonic) == .disabled) break :fcf;
        if (file_reader.pos != 0) break :fcf;
        if (offset != 0) break :fcf;
        if (limit != .unlimited) break :fcf;
        const size = file_reader.getSize() catch break :fcf;
        if (header.len != 0 or reader_buffered.len != 0) {
            const n = try fileWritePositional(t, file, header, &.{limit.slice(reader_buffered)}, 1, offset);
            file_reader.interface.toss(n -| header.len);
            return n;
        }
        const syscall: Syscall = try .start();
        while (true) {
            const rc = std.c.fcopyfile(in_fd, out_fd, null, .{ .DATA = true });
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .OPNOTSUPP => {
                    // Give calling code chance to observe before trying
                    // something else.
                    syscall.finish();
                    @atomicStore(UseFcopyfile, &t.use_fcopyfile, .disabled, .monotonic);
                    return 0;
                },
                else => |e| {
                    syscall.finish();
                    assert(error.Unexpected == switch (e) {
                        .NOMEM => return error.SystemResources,
                        .INVAL => |err| errnoBug(err),
                        else => |err| posix.unexpectedErrno(err),
                    });
                    return 0;
                },
            }
        }
        file_reader.pos = size;
        return size;
    }

    return error.Unimplemented;
}

fn nowPosix(clock: Io.Clock) Io.Timestamp {
    const clock_id: posix.clockid_t = clockToPosix(clock);
    var timespec: posix.timespec = undefined;
    switch (posix.errno(posix.system.clock_gettime(clock_id, &timespec))) {
        .SUCCESS => return timestampFromPosix(&timespec),
        else => return .zero,
    }
}

fn now(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return switch (native_os) {
        .windows => nowWindows(clock),
        .wasi => nowWasi(clock),
        else => nowPosix(clock),
    };
}

fn clockResolution(userdata: ?*anyopaque, clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    return switch (native_os) {
        .windows => switch (clock) {
            .awake, .boot, .real => {
                // We don't need to cache QPF as it's internally just a memory read to KUSER_SHARED_DATA
                // (a read-only page of info updated and mapped by the kernel to all processes):
                // https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/ns-ntddk-kuser_shared_data
                // https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntexapi_x/kuser_shared_data/index.htm
                var qpf: windows.LARGE_INTEGER = undefined;
                if (!windows.ntdll.RtlQueryPerformanceFrequency(&qpf).toBool()) {
                    recoverableOsBugDetected();
                    return .zero;
                }
                // 10Mhz (1 qpc tick every 100ns) is a common enough QPF value that we can optimize on it.
                // https://github.com/microsoft/STL/blob/785143a0c73f030238ef618890fd4d6ae2b3a3a0/stl/inc/chrono#L694-L701
                const common_qpf = 10_000_000;
                if (qpf == common_qpf) return .fromNanoseconds(std.time.ns_per_s / common_qpf);

                // Convert to ns using fixed point.
                const scale = @as(u64, std.time.ns_per_s << 32) / @as(u32, @intCast(qpf));
                const result = scale >> 32;
                return .fromNanoseconds(result);
            },
            .cpu_process, .cpu_thread => return error.ClockUnavailable,
        },
        .wasi => {
            if (builtin.link_libc) return clockResolutionPosix(clock);
            var ns: std.os.wasi.timestamp_t = undefined;
            return switch (std.os.wasi.clock_res_get(clockToWasi(clock), &ns)) {
                .SUCCESS => .fromNanoseconds(ns),
                .INVAL => return error.ClockUnavailable,
                else => |err| return posix.unexpectedErrno(err),
            };
        },
        else => return clockResolutionPosix(clock),
    };
}

fn clockResolutionPosix(clock: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    const clock_id: posix.clockid_t = clockToPosix(clock);
    var timespec: posix.timespec = undefined;
    return switch (posix.errno(posix.system.clock_getres(clock_id, &timespec))) {
        .SUCCESS => .fromNanoseconds(nanosecondsFromPosix(&timespec)),
        .INVAL => return error.ClockUnavailable,
        else => |err| return posix.unexpectedErrno(err),
    };
}

fn nowWindows(clock: Io.Clock) Io.Timestamp {
    switch (clock) {
        .real => {
            // RtlGetSystemTimePrecise() has a granularity of 100 nanoseconds
            // and uses the NTFS/Windows epoch, which is 1601-01-01.
            const epoch_ns = std.time.epoch.windows * std.time.ns_per_s;
            return .{ .nanoseconds = @as(i96, windows.ntdll.RtlGetSystemTimePrecise()) * 100 + epoch_ns };
        },
        .awake, .boot => {
            // We don't need to cache QPF as it's internally just a memory read to KUSER_SHARED_DATA
            // (a read-only page of info updated and mapped by the kernel to all processes):
            // https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/ns-ntddk-kuser_shared_data
            // https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntexapi_x/kuser_shared_data/index.htm
            const qpf: u64 = qpf: {
                var qpf: windows.LARGE_INTEGER = undefined;
                assert(windows.ntdll.RtlQueryPerformanceFrequency(&qpf).toBool());
                break :qpf @bitCast(qpf);
            };

            // QPC on windows doesn't fail on >= XP/2000 and includes time suspended.
            const qpc: u64 = qpc: {
                var qpc: windows.LARGE_INTEGER = undefined;
                assert(windows.ntdll.RtlQueryPerformanceCounter(&qpc).toBool());
                break :qpc @bitCast(qpc);
            };

            // 10Mhz (1 qpc tick every 100ns) is a common enough QPF value that we can optimize on it.
            // https://github.com/microsoft/STL/blob/785143a0c73f030238ef618890fd4d6ae2b3a3a0/stl/inc/chrono#L694-L701
            const common_qpf = 10_000_000;
            if (qpf == common_qpf) return .{ .nanoseconds = qpc * (std.time.ns_per_s / common_qpf) };

            // Convert to ns using fixed point.
            const scale = @as(u64, std.time.ns_per_s << 32) / @as(u32, @intCast(qpf));
            const result = (@as(u96, qpc) * scale) >> 32;
            return .{ .nanoseconds = @intCast(result) };
        },
        .cpu_process => {
            const handle = windows.GetCurrentProcess();
            var times: windows.KERNEL_USER_TIMES = undefined;

            // https://github.com/reactos/reactos/blob/master/ntoskrnl/ps/query.c#L442-L485
            if (windows.ntdll.NtQueryInformationProcess(
                handle,
                .Times,
                &times,
                @sizeOf(windows.KERNEL_USER_TIMES),
                null,
            ) != .SUCCESS) return .zero;

            const sum = @as(i96, times.UserTime) + @as(i96, times.KernelTime);
            return .{ .nanoseconds = sum * 100 };
        },
        .cpu_thread => {
            const handle = windows.GetCurrentThread();
            var times: windows.KERNEL_USER_TIMES = undefined;

            // https://github.com/reactos/reactos/blob/master/ntoskrnl/ps/query.c#L2971-L3019
            if (windows.ntdll.NtQueryInformationThread(
                handle,
                .Times,
                &times,
                @sizeOf(windows.KERNEL_USER_TIMES),
                null,
            ) != .SUCCESS) return .zero;

            const sum = @as(i96, times.UserTime) + @as(i96, times.KernelTime);
            return .{ .nanoseconds = sum * 100 };
        },
    }
}

fn nowWasi(clock: Io.Clock) Io.Timestamp {
    var ns: std.os.wasi.timestamp_t = undefined;
    const err = std.os.wasi.clock_time_get(clockToWasi(clock), 1, &ns);
    if (err != .SUCCESS) return .zero;
    return .fromNanoseconds(ns);
}

fn sleep(userdata: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (timeout == .none) return;
    if (use_parking_sleep) return parking_sleep.sleep(timeout);
    if (native_os == .wasi) return sleepWasi(t, timeout);
    if (@TypeOf(posix.system.clock_nanosleep) != void) return sleepPosix(timeout);
    return sleepNanosleep(t, timeout);
}

fn sleepPosix(timeout: Io.Timeout) Io.Cancelable!void {
    const clock_id: posix.clockid_t = clockToPosix(switch (timeout) {
        .none => .awake,
        .duration => |d| d.clock,
        .deadline => |d| d.clock,
    });
    const deadline_nanoseconds: i96 = switch (timeout) {
        .none => std.math.maxInt(i96),
        .duration => |duration| duration.raw.nanoseconds,
        .deadline => |deadline| deadline.raw.nanoseconds,
    };
    var timespec: posix.timespec = timestampToPosix(deadline_nanoseconds);
    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.clock_nanosleep(clock_id, .{ .ABSTIME = switch (timeout) {
            .none, .duration => false,
            .deadline => true,
        } }, &timespec, &timespec);
        // POSIX-standard libc clock_nanosleep() returns *positive* errno values directly
        switch (if (builtin.link_libc) @as(posix.E, @enumFromInt(rc)) else posix.errno(rc)) {
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            // Handles SUCCESS as well as clock not available and unexpected
            // errors. The user had a chance to check clock resolution before
            // getting here, which would have reported 0, making this a legal
            // amount of time to sleep.
            else => {
                syscall.finish();
                return;
            },
        }
    }
}

fn sleepWasi(t: *Threaded, timeout: Io.Timeout) Io.Cancelable!void {
    const t_io = io(t);
    const w = std.os.wasi;

    const clock: w.subscription_clock_t = if (timeout.toDurationFromNow(t_io)) |d| .{
        .id = clockToWasi(d.clock),
        .timeout = std.math.lossyCast(u64, d.raw.nanoseconds),
        .precision = 0,
        .flags = 0,
    } else .{
        .id = .MONOTONIC,
        .timeout = std.math.maxInt(u64),
        .precision = 0,
        .flags = 0,
    };
    const in: w.subscription_t = .{
        .userdata = 0,
        .u = .{
            .tag = .CLOCK,
            .u = .{ .clock = clock },
        },
    };
    var event: w.event_t = undefined;
    var nevents: usize = undefined;
    const syscall: Syscall = try .start();
    _ = w.poll_oneoff(&in, &event, 1, &nevents);
    syscall.finish();
}

fn sleepNanosleep(t: *Threaded, timeout: Io.Timeout) Io.Cancelable!void {
    const t_io = io(t);
    const sec_type = @typeInfo(posix.timespec).@"struct".fields[0].type;
    const nsec_type = @typeInfo(posix.timespec).@"struct".fields[1].type;

    var timespec: posix.timespec = t: {
        const d = timeout.toDurationFromNow(t_io) orelse break :t .{
            .sec = std.math.maxInt(sec_type),
            .nsec = std.math.maxInt(nsec_type),
        };
        break :t timestampToPosix(d.raw.toNanoseconds());
    };
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.nanosleep(&timespec, &timespec))) {
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            // This prong handles success as well as unexpected errors.
            else => return syscall.finish(),
        }
    }
}

fn netListenIpPosix(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.ListenOptions,
) IpAddress.ListenError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_fd = try openSocketPosix(family, .{ .mode = options.mode, .protocol = options.protocol });
    errdefer closeFd(socket_fd);

    if (options.reuse_address) {
        try setSocketOptionPosix(socket_fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, 1);
        if (@hasDecl(posix.SO, "REUSEPORT"))
            try setSocketOptionPosix(socket_fd, posix.SOL.SOCKET, posix.SO.REUSEPORT, 1);
    }

    var storage: PosixAddress = undefined;
    var addr_len = addressToPosix(address, &storage);
    try posixBind(socket_fd, &storage.any, addr_len);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.listen(socket_fd, options.kernel_backlog))) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ADDRINUSE => return syscall.fail(error.AddressInUse),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            else => |err| return syscall.unexpectedErrno(err),
        }
    }

    try posixGetSockName(socket_fd, &storage.any, &addr_len);
    return .{ .handle = socket_fd, .address = addressFromPosix(&storage) };
}

fn netListenIpWindows(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.ListenOptions,
) IpAddress.ListenError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_handle = try openSocketAfd(family, .{ .mode = options.mode, .protocol = options.protocol });
    errdefer windows.CloseHandle(socket_handle);
    if (options.reuse_address) try setSocketOptionAfd(socket_handle, ws2_32.SOL.SOCKET, ws2_32.SO.REUSEADDR, true);
    const bound_address = try bindSocketIpAfd(socket_handle, address, .Passive);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.START_LISTEN,
        .in = @ptrCast(&windows.AFD.LISTEN_INFO{
            .UseSAN = .FALSE,
            .MaximumConnectionQueue = options.kernel_backlog,
            .UseDelayedAcceptance = .FALSE,
        }),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    return .{ .handle = socket_handle, .address = bound_address };
}

fn netListenUnixPosix(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
    options: net.UnixAddress.ListenOptions,
) net.UnixAddress.ListenError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const socket_fd = openSocketPosix(posix.AF.UNIX, .{ .mode = .stream }) catch |err| switch (err) {
        error.ProtocolUnsupportedBySystem => return error.AddressFamilyUnsupported,
        error.ProtocolUnsupportedByAddressFamily => return error.AddressFamilyUnsupported,
        error.SocketModeUnsupported => return error.AddressFamilyUnsupported,
        error.OptionUnsupported => return error.Unexpected,
        else => |e| return e,
    };
    errdefer closeFd(socket_fd);

    var storage: UnixAddress = undefined;
    const addr_len = addressUnixToPosix(address, &storage);
    try posixBindUnix(socket_fd, &storage.any, addr_len);

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.listen(socket_fd, options.kernel_backlog))) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ADDRINUSE => return syscall.fail(error.AddressInUse),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            else => |err| return syscall.unexpectedErrno(err),
        }
    }

    return socket_fd;
}

fn netListenUnixWindows(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
    options: net.UnixAddress.ListenOptions,
) net.UnixAddress.ListenError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const is_abstract = address.isAbstract();
    const wps = if (!is_abstract) sliceToPrefixedFileW(null, address.path, .{
        .allow_relative = false,
    }) catch |err| switch (err) {
        error.NameTooLong, error.BadPathName => return error.AddressUnavailable,
        else => |e| return e,
    } else undefined;
    const socket_handle = openSocketAfd(ws2_32.AF.UNIX, .{ .mode = .stream }) catch |err| switch (err) {
        error.ProtocolUnsupportedByAddressFamily => return error.AddressFamilyUnsupported,
        else => |e| return e,
    };
    errdefer windows.CloseHandle(socket_handle);
    if (!is_abstract) try socketOptionAfd(socket_handle, .special, 0, ws2_32.SO.UNIX_PATH, @constCast(
        @as([]const u8, @ptrCast(&windows.AFD.SOCKOPT_INFO.UNIX_PATH{
            .Path = wps.data,
        }))[0 .. @offsetOf(windows.AFD.SOCKOPT_INFO.UNIX_PATH, "Path") + @sizeOf(windows.WCHAR) * wps.len],
    ));
    try bindSocketUnixAfd(socket_handle, address);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.START_LISTEN,
        .in = @ptrCast(&windows.AFD.LISTEN_INFO{
            .UseSAN = .FALSE,
            .MaximumConnectionQueue = options.kernel_backlog,
            .UseDelayedAcceptance = .FALSE,
        }),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    return socket_handle;
}

fn posixBindUnix(
    fd: posix.socket_t,
    addr: *const posix.sockaddr,
    addr_len: posix.socklen_t,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.bind(fd, addr, addr_len))) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => return error.AccessDenied,
                    .ADDRINUSE => return error.AddressInUse,
                    .AFNOSUPPORT => return error.AddressFamilyUnsupported,
                    .ADDRNOTAVAIL => return error.AddressUnavailable,
                    .NOMEM => return error.SystemResources,

                    .LOOP => return error.SymLinkLoop,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.NotDir,
                    .ROFS => return error.ReadOnlyFileSystem,
                    .PERM => return error.PermissionDenied,

                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOTSOCK => |err| return errnoBug(err), // invalid `sockfd`
                    .FAULT => |err| return errnoBug(err), // invalid `addr` pointer
                    .NAMETOOLONG => |err| return errnoBug(err),
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn posixBind(
    socket_fd: posix.socket_t,
    addr: *const posix.sockaddr,
    addr_len: posix.socklen_t,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.bind(socket_fd, addr, addr_len))) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ADDRINUSE => return error.AddressInUse,
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOTSOCK => |err| return errnoBug(err), // invalid `sockfd`
                    .AFNOSUPPORT => return error.AddressFamilyUnsupported,
                    .ADDRNOTAVAIL => return error.AddressUnavailable,
                    .FAULT => |err| return errnoBug(err), // invalid `addr` pointer
                    .NOMEM => return error.SystemResources,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn posixConnect(
    socket_fd: posix.socket_t,
    addr: *const posix.sockaddr,
    addr_len: posix.socklen_t,
) !void {
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.connect(socket_fd, addr, addr_len))) {
        .SUCCESS => {
            syscall.finish();
            return;
        },
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ADDRNOTAVAIL => return syscall.fail(error.AddressUnavailable),
        .AFNOSUPPORT => return syscall.fail(error.AddressFamilyUnsupported),
        .AGAIN, .INPROGRESS => return syscall.fail(error.WouldBlock),
        .ALREADY => return syscall.fail(error.ConnectionPending),
        .CONNREFUSED => return syscall.fail(error.ConnectionRefused),
        .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
        .HOSTUNREACH => return syscall.fail(error.HostUnreachable),
        .NETUNREACH => return syscall.fail(error.NetworkUnreachable),
        .TIMEDOUT => return syscall.fail(error.Timeout),
        .ACCES => return syscall.fail(error.AccessDenied),
        .NETDOWN => return syscall.fail(error.NetworkDown),
        .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
        .CONNABORTED => |err| return syscall.errnoBug(err),
        .FAULT => |err| return syscall.errnoBug(err),
        .ISCONN => |err| return syscall.errnoBug(err),
        .NOENT => |err| return syscall.errnoBug(err),
        .NOTSOCK => |err| return syscall.errnoBug(err),
        .PERM => |err| return syscall.errnoBug(err),
        .PROTOTYPE => |err| return syscall.errnoBug(err),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn posixConnectUnix(
    fd: posix.socket_t,
    addr: *const posix.sockaddr,
    addr_len: posix.socklen_t,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.connect(fd, addr, addr_len))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .AFNOSUPPORT => return error.AddressFamilyUnsupported,
                    .AGAIN => return error.WouldBlock,
                    .INPROGRESS => return error.WouldBlock,
                    .ACCES => return error.AccessDenied,

                    .LOOP => return error.SymLinkLoop,
                    .NOENT => return error.FileNotFound,
                    .NOTDIR => return error.NotDir,
                    .ROFS => return error.ReadOnlyFileSystem,
                    .PERM => return error.PermissionDenied,

                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .CONNABORTED => |err| return errnoBug(err),
                    .FAULT => |err| return errnoBug(err),
                    .ISCONN => |err| return errnoBug(err),
                    .NOTSOCK => |err| return errnoBug(err),
                    .PROTOTYPE => |err| return errnoBug(err),
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn posixGetSockName(
    socket_fd: posix.fd_t,
    addr: *posix.sockaddr,
    addr_len: *posix.socklen_t,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.getsockname(socket_fd, addr, addr_len))) {
            .SUCCESS => {
                syscall.finish();
                break;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err), // invalid parameters
                    .NOTSOCK => |err| return errnoBug(err), // always a race condition
                    .NOBUFS => return error.SystemResources,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn setSocketOptionPosix(fd: posix.fd_t, level: i32, opt_name: u32, option: u32) !void {
    const o: []const u8 = @ptrCast(&option);
    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.setsockopt(fd, level, opt_name, o.ptr, @intCast(o.len)))) {
            .SUCCESS => {
                syscall.finish();
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOTSOCK => |err| return errnoBug(err),
                    .INVAL => |err| return errnoBug(err),
                    .FAULT => |err| return errnoBug(err),
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn setSocketOptionAfd(socket: net.Socket.Handle, level: i32, opt_name: u32, opt_val: anytype) !void {
    try socketOptionAfd(socket, .set, level, opt_name, @ptrCast(@constCast(&opt_val)));
}

fn socketOptionAfd(socket: net.Socket.Handle, mode: windows.AFD.SOCKOPT_INFO.Mode, level: i32, opt_name: u32, opt_val: []u8) !void {
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.SOCKOPT,
        .in = @ptrCast(&windows.AFD.SOCKOPT_INFO{
            .mode = mode,
            .level = level,
            .optname = opt_name,
            .optval = opt_val.ptr,
            .optlen = opt_val.len,
        }),
    })).u.Status) {
        .SUCCESS => return,
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netConnectIpPosix(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.ConnectOptions,
) IpAddress.ConnectError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    if (options.timeout != .none) @panic("TODO implement netConnectIpPosix with timeout");
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_fd = try openSocketPosix(family, .{ .mode = options.mode, .protocol = options.protocol });
    errdefer closeFd(socket_fd);
    var storage: PosixAddress = undefined;
    var addr_len = addressToPosix(address, &storage);
    try posixConnect(socket_fd, &storage.any, addr_len);
    try posixGetSockName(socket_fd, &storage.any, &addr_len);
    return .{ .handle = socket_fd, .address = addressFromPosix(&storage) };
}

fn netConnectIpWindows(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.ConnectOptions,
) IpAddress.ConnectError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    if (options.timeout != .none) @panic("TODO implement netConnectIpWindows with timeout");
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_handle = try openSocketAfd(family, .{ .mode = options.mode, .protocol = options.protocol });
    errdefer windows.CloseHandle(socket_handle);
    try setSocketOptionAfd(socket_handle, ws2_32.SOL.SOCKET, ws2_32.SO.REUSE_UNICASTPORT, true);
    const bound_address = bindSocketIpAfd(socket_handle, &switch (address.*) {
        .ip4 => .{ .ip4 = .unspecified(0) },
        .ip6 => .{ .ip6 = .unspecified(0) },
    }, .Active) catch |err| switch (err) {
        error.AddressInUse => return error.Unexpected,
        else => |e| return e,
    };
    const Storage = extern struct { Reserved0: [3]usize = @splat(0), Address: PosixAddress };
    var storage: Storage = .{ .Address = undefined };
    const addr_len = addressToPosix(address, &storage.Address);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.CONNECT,
        .in = @as([]const u8, @ptrCast(&storage))[0 .. @offsetOf(Storage, "Address") + addr_len],
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    return .{ .handle = socket_handle, .address = bound_address };
}

fn netConnectUnixPosix(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
) net.UnixAddress.ConnectError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const socket_fd = openSocketPosix(posix.AF.UNIX, .{ .mode = .stream }) catch |err| switch (err) {
        error.ProtocolUnsupportedByAddressFamily => return error.AddressFamilyUnsupported,
        error.OptionUnsupported => return error.Unexpected,
        else => |e| return e,
    };
    errdefer closeFd(socket_fd);
    var storage: UnixAddress = undefined;
    const addr_len = addressUnixToPosix(address, &storage);
    try posixConnectUnix(socket_fd, &storage.any, addr_len);
    return socket_fd;
}

fn netConnectUnixWindows(
    userdata: ?*anyopaque,
    address: *const net.UnixAddress,
) net.UnixAddress.ConnectError!net.Socket.Handle {
    if (!net.has_unix_sockets) return error.AddressFamilyUnsupported;
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const is_abstract = address.isAbstract();
    const wps = if (!is_abstract) sliceToPrefixedFileW(null, address.path, .{
        .allow_relative = false,
    }) catch |err| switch (err) {
        error.NameTooLong, error.BadPathName => return error.FileNotFound,
        else => |e| return e,
    } else undefined;
    const socket_handle = openSocketAfd(ws2_32.AF.UNIX, .{ .mode = .stream }) catch |err| switch (err) {
        error.ProtocolUnsupportedByAddressFamily => return error.AddressFamilyUnsupported,
        else => |e| return e,
    };
    errdefer windows.CloseHandle(socket_handle);
    if (!is_abstract) try socketOptionAfd(socket_handle, .special, 0, ws2_32.SO.UNIX_PATH, @constCast(
        @as([]const u8, @ptrCast(&windows.AFD.SOCKOPT_INFO.UNIX_PATH{
            .Path = wps.data,
        }))[0 .. @offsetOf(windows.AFD.SOCKOPT_INFO.UNIX_PATH, "Path") + @sizeOf(windows.WCHAR) * wps.len],
    ));
    bindSocketUnixAfd(socket_handle, &(net.UnixAddress.init("") catch |err| switch (err) {
        error.NameTooLong => unreachable,
    })) catch |err| switch (err) {
        error.AddressInUse => return error.Unexpected,
        else => |e| return e,
    };
    const Storage = extern struct { Reserved0: [3]usize = @splat(0), Address: UnixAddress };
    var storage: Storage = .{ .Address = undefined };
    const addr_len = addressUnixToPosix(address, &storage.Address);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.CONNECT,
        .in = @as([]const u8, @ptrCast(&storage))[0 .. @offsetOf(Storage, "Address") + addr_len],
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    return socket_handle;
}

fn netBindIpPosix(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.BindOptions,
) IpAddress.BindError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_fd = try openSocketPosix(family, options);
    errdefer closeFd(socket_fd);
    var storage: PosixAddress = undefined;
    var addr_len = addressToPosix(address, &storage);
    try posixBind(socket_fd, &storage.any, addr_len);
    if (options.allow_broadcast) try setSocketOptionPosix(socket_fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, 1);
    try posixGetSockName(socket_fd, &storage.any, &addr_len);
    return .{ .handle = socket_fd, .address = addressFromPosix(&storage) };
}

fn netBindIpWindows(
    userdata: ?*anyopaque,
    address: *const IpAddress,
    options: IpAddress.BindOptions,
) IpAddress.BindError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const family = posixAddressFamily(address);
    const socket_handle = try openSocketAfd(family, options);
    errdefer windows.CloseHandle(socket_handle);
    const bound_address = try bindSocketIpAfd(socket_handle, address, .Active);
    if (options.allow_broadcast) try setSocketOptionAfd(socket_handle, ws2_32.SOL.SOCKET, ws2_32.SO.BROADCAST, true);
    return .{ .handle = socket_handle, .address = bound_address };
}

fn openSocketPosix(
    family: posix.sa_family_t,
    options: IpAddress.BindOptions,
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
}!posix.socket_t {
    const mode, const protocol = try posixSocketModeProtocol(family, options.mode, options.protocol);
    const flags: u32 = mode | if (socket_flags_unsupported) 0 else posix.SOCK.CLOEXEC;
    const syscall: Syscall = try .start();
    const socket_fd = while (true) {
        const rc = posix.system.socket(family, flags, protocol);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const fd: posix.fd_t = @intCast(rc);
                errdefer closeFd(fd);
                if (socket_flags_unsupported) try setCloexec(fd);
                break fd;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .AFNOSUPPORT => return syscall.fail(error.AddressFamilyUnsupported),
            .INVAL => return syscall.fail(error.ProtocolUnsupportedBySystem),
            .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
            .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .PROTONOSUPPORT => return syscall.fail(error.ProtocolUnsupportedByAddressFamily),
            .PROTOTYPE => return syscall.fail(error.SocketModeUnsupported),
            else => |err| return syscall.unexpectedErrno(err),
        }
    };
    errdefer closeFd(socket_fd);

    if (options.ip6_only) {
        if (posix.IPV6 == void) return error.OptionUnsupported;
        try setSocketOptionPosix(socket_fd, posix.IPPROTO.IPV6, posix.IPV6.V6ONLY, 0);
    }

    return socket_fd;
}

fn setCloexec(fd: posix.fd_t) error{ Canceled, Unexpected }!void {
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC)))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn netSocketCreatePair(
    userdata: ?*anyopaque,
    options: net.Socket.CreatePairOptions,
) net.Socket.CreatePairError![2]net.Socket {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    if (!have_networking) return error.OperationUnsupported;
    if (@TypeOf(posix.system.socketpair) == void) return error.OperationUnsupported;
    if (native_os == .haiku) @panic("TODO");

    const family: posix.sa_family_t = switch (options.family) {
        .ip4 => posix.AF.INET,
        .ip6 => posix.AF.INET6,
    };
    const mode, const protocol = try posixSocketModeProtocol(family, options.mode, options.protocol);
    const flags: u32 = mode | if (socket_flags_unsupported) 0 else posix.SOCK.CLOEXEC;

    var sockets: [2]posix.socket_t = undefined;
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.socketpair(family, flags, protocol, &sockets))) {
        .SUCCESS => {
            syscall.finish();
            errdefer {
                closeFd(sockets[0]);
                closeFd(sockets[1]);
            }
            if (socket_flags_unsupported) {
                try setCloexec(sockets[0]);
                try setCloexec(sockets[1]);
            }
            var storages: [2]PosixAddress = undefined;
            var addr_lens: [2]posix.socklen_t = .{ @sizeOf(PosixAddress), @sizeOf(PosixAddress) };
            try posixGetSockName(sockets[0], &storages[0].any, &addr_lens[0]);
            try posixGetSockName(sockets[1], &storages[1].any, &addr_lens[1]);
            return .{
                .{ .handle = sockets[0], .address = addressFromPosix(&storages[0]) },
                .{ .handle = sockets[1], .address = addressFromPosix(&storages[1]) },
            };
        },
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ACCES => return syscall.fail(error.AccessDenied),
        .AFNOSUPPORT => return syscall.fail(error.AddressFamilyUnsupported),
        .INVAL => return syscall.fail(error.ProtocolUnsupportedBySystem),
        .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
        .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
        .NOBUFS => return syscall.fail(error.SystemResources),
        .NOMEM => return syscall.fail(error.SystemResources),
        .PROTONOSUPPORT => return syscall.fail(error.ProtocolUnsupportedByAddressFamily),
        .PROTOTYPE => return syscall.fail(error.SocketModeUnsupported),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn openSocketAfd(family: ws2_32.ADDRESS_FAMILY, options: IpAddress.BindOptions) !net.Socket.Handle {
    const mode, const protocol = try posixSocketModeProtocol(family, options.mode, options.protocol);
    var handle: windows.HANDLE = undefined;
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtCreateFile(
        &handle,
        .{
            .STANDARD = .{ .RIGHTS = .{ .WRITE_DAC = true }, .SYNCHRONIZE = true },
            .GENERIC = .{ .WRITE = true, .READ = true },
        },
        &.{
            .ObjectName = @constCast(&windows.UNICODE_STRING.init(
                windows.AFD.DEVICE_NAME ++ .{ '\\', 'E', 'n', 'd', 'p', 'o', 'i', 'n', 't' },
            )),
        },
        &iosb,
        null,
        .{},
        .{ .READ = true, .WRITE = true },
        .OPEN_IF,
        .{ .IO = .ASYNCHRONOUS },
        &windows.AFD.OPEN_PACKET.FULL_EA_INFORMATION{ .Value = .{
            .EndpointType = .{
                .CONNECTIONLESS = switch (options.mode) {
                    .stream, .seqpacket, .rdm => false,
                    .dgram, .raw => true,
                },
                .MESSAGEMODE = options.mode != .stream,
                .RAW = options.mode == .raw,
            },
            .GroupID = 0,
            .AddressFamily = family,
            .SocketType = @bitCast(mode),
            .Protocol = @bitCast(protocol),
            .TransportDeviceNameLength = 0,
            .TransportDeviceName = undefined,
        } },
        @sizeOf(windows.AFD.OPEN_PACKET.FULL_EA_INFORMATION),
    )) {
        .SUCCESS => {
            syscall.finish();
            return handle;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .PROTOCOL_NOT_SUPPORTED => return syscall.fail(error.AddressFamilyUnsupported),
        .NO_SUCH_FILE => return syscall.fail(error.ProtocolUnsupportedByAddressFamily),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
}

fn bindSocketIpAfd(socket_handle: net.Socket.Handle, address: *const IpAddress, mode: windows.AFD.BIND_INFO.MODE) !IpAddress {
    const Storage = extern struct { Info: windows.AFD.BIND_INFO, Address: PosixAddress };
    var storage: Storage = .{ .Info = .{ .Mode = mode }, .Address = undefined };
    const addr_len = addressToPosix(address, &storage.Address);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.BIND,
        .in = @as([]const u8, @ptrCast(&storage))[0 .. @offsetOf(Storage, "Address") + addr_len],
        .out = @as([]u8, @ptrCast(&storage.Address))[0..addr_len],
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        .SHARING_VIOLATION => return error.AddressInUse,
        else => |status| return windows.unexpectedStatus(status),
    }
    return addressFromPosix(&storage.Address);
}

fn bindSocketUnixAfd(socket_handle: net.Socket.Handle, address: *const net.UnixAddress) !void {
    const Storage = extern struct { Info: windows.AFD.BIND_INFO, Address: UnixAddress };
    var storage: Storage = .{ .Info = .{ .Mode = .Unix }, .Address = undefined };
    const addr_len = addressUnixToPosix(address, &storage.Address);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.BIND,
        .in = @as([]const u8, @ptrCast(&storage))[0 .. @offsetOf(Storage, "Address") + addr_len],
        .out = @ptrCast(&storage.Address),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        .ADDRESS_ALREADY_EXISTS => return error.AddressInUse,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netAcceptPosix(userdata: ?*anyopaque, listen_fd: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    options;
    var storage: PosixAddress = undefined;
    var addr_len: posix.socklen_t = @sizeOf(PosixAddress);
    const syscall: Syscall = try .start();
    const fd = while (true) {
        const rc = if (have_accept4)
            posix.system.accept4(listen_fd, &storage.any, &addr_len, posix.SOCK.CLOEXEC)
        else
            posix.system.accept(listen_fd, &storage.any, &addr_len);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const fd: posix.fd_t = @intCast(rc);
                errdefer closeFd(fd);
                if (!have_accept4) try setCloexec(fd);
                break fd;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .AGAIN => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .CONNABORTED => return error.ConnectionAborted,
                    .FAULT => |err| return errnoBug(err),
                    .INVAL => return error.SocketNotListening,
                    .NOTSOCK => |err| return errnoBug(err),
                    .MFILE => return error.ProcessFdQuotaExceeded,
                    .NFILE => return error.SystemFdQuotaExceeded,
                    .NOBUFS => return error.SystemResources,
                    .NOMEM => return error.SystemResources,
                    .OPNOTSUPP => |err| return errnoBug(err),
                    .PROTO => return error.ProtocolFailure,
                    .PERM => return error.BlockedByFirewall,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    };
    return .{ .handle = fd, .address = addressFromPosix(&storage) };
}

fn netAcceptWindows(userdata: ?*anyopaque, listen_handle: net.Socket.Handle, options: net.Server.AcceptOptions) net.Server.AcceptError!net.Socket {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const Storage = extern struct {
        Info: windows.AFD.LISTEN_RESPONSE_INFO,
        RemoteAddress: extern union { posix: PosixAddress, unix: UnixAddress },
    };
    var storage: Storage = undefined;
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = listen_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.WAIT_FOR_LISTEN,
        .out = @ptrCast(&storage),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    errdefer t.deferAcceptAfd(listen_handle, storage.Info);
    const accept_handle = openSocketAfd(
        storage.RemoteAddress.posix.any.family,
        .{ .mode = options.mode, .protocol = options.protocol },
    ) catch |err| switch (err) {
        error.AddressFamilyUnsupported => return error.Unexpected,
        error.ProtocolUnsupportedByAddressFamily => return error.Unexpected,
        else => |e| return e,
    };
    errdefer windows.CloseHandle(accept_handle);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = listen_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.ACCEPT,
        .in = @ptrCast(&windows.AFD.ACCEPT_INFO{
            .UseSAN = .FALSE,
            .Sequence = storage.Info.Sequence,
            .AcceptHandle = accept_handle,
        }),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
    return .{ .handle = accept_handle, .address = addressFromPosix(&storage.RemoteAddress.posix) };
}

fn deferAcceptAfd(t: *Threaded, listen_handle: net.Socket.Handle, info: windows.AFD.LISTEN_RESPONSE_INFO) void {
    const cancel_protection = swapCancelProtection(t, .blocked);
    defer _ = swapCancelProtection(t, cancel_protection);
    switch ((deviceIoControl(&.{
        .file = .{ .handle = listen_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.DEFER_ACCEPT,
        .in = @ptrCast(&windows.AFD.DEFER_ACCEPT_INFO{
            .Sequence = info.Sequence,
            .Reject = .FALSE,
        }),
    }) catch |err| switch (err) {
        error.Canceled => unreachable, // blocked
    }).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        else => |status| windows.unexpectedStatus(status) catch {},
    }
}

fn netReadPosix(userdata: ?*anyopaque, fd: net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!usize {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var iovecs_buffer: [max_iovecs_len]posix.iovec = undefined;
    var i: usize = 0;
    for (data) |buf| {
        if (iovecs_buffer.len - i == 0) break;
        if (buf.len != 0) {
            iovecs_buffer[i] = .{ .base = buf.ptr, .len = buf.len };
            i += 1;
        }
    }
    const dest = iovecs_buffer[0..i];
    assert(dest[0].len > 0);

    if (native_os == .wasi and !builtin.link_libc) {
        const syscall: Syscall = try .start();
        while (true) {
            var n: usize = undefined;
            switch (std.os.wasi.fd_read(fd, dest.ptr, dest.len, &n)) {
                .SUCCESS => {
                    syscall.finish();
                    return n;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .INVAL => |err| return errnoBug(err),
                        .FAULT => |err| return errnoBug(err),
                        .AGAIN => |err| return errnoBug(err),
                        .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                        .NOBUFS => return error.SystemResources,
                        .NOMEM => return error.SystemResources,
                        .NOTCONN => return error.SocketUnconnected,
                        .CONNRESET => return error.ConnectionResetByPeer,
                        .TIMEDOUT => return error.Timeout,
                        .NOTCAPABLE => return error.AccessDenied,
                        else => |err| return posix.unexpectedErrno(err),
                    }
                },
            }
        }
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.readv(fd, dest.ptr, @intCast(dest.len));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return @intCast(rc);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .INVAL => |err| return errnoBug(err),
                    .FAULT => |err| return errnoBug(err),
                    .AGAIN => |err| return errnoBug(err),
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .NOBUFS => return error.SystemResources,
                    .NOMEM => return error.SystemResources,
                    .NOTCONN => return error.SocketUnconnected,
                    .CONNRESET => return error.ConnectionResetByPeer,
                    .TIMEDOUT => return error.Timeout,
                    .PIPE => return error.SocketUnconnected,
                    .NETDOWN => return error.NetworkDown,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn netReadWindows(userdata: ?*anyopaque, socket_handle: net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!usize {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var iovecs: [max_iovecs_len]windows.AFD.WSABUF(.@"var") = undefined;
    var len: u32 = 0;
    for (data) |buf| {
        if (iovecs.len - len == 0) break;
        addAfdBuf(.@"var", &iovecs, &len, buf);
    }

    const iosb = try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.RECEIVE,
        .in = @ptrCast(&windows.AFD.RECV_INFO{
            .BufferArray = &iovecs,
            .BufferCount = len,
            .AfdFlags = .{ .NO_FAST_IO = true, .OVERLAPPED = true },
            .TdiFlags = .{ .NORMAL = true },
        }),
    });
    switch (iosb.u.Status) {
        .SUCCESS => return iosb.Information,
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netSendPosix(
    userdata: ?*anyopaque,
    socket_handle: net.Socket.Handle,
    messages: []net.OutgoingMessage,
    flags: net.SendFlags,
) struct { ?net.Socket.SendError, usize } {
    if (!have_networking) return .{ error.NetworkDown, 0 };
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    const posix_flags: u32 =
        @as(u32, if (@hasDecl(posix.MSG, "CONFIRM") and flags.confirm) posix.MSG.CONFIRM else 0) |
        @as(u32, if (@hasDecl(posix.MSG, "DONTROUTE") and flags.dont_route) posix.MSG.DONTROUTE else 0) |
        @as(u32, if (@hasDecl(posix.MSG, "EOR") and flags.eor) posix.MSG.EOR else 0) |
        @as(u32, if (@hasDecl(posix.MSG, "OOB") and flags.oob) posix.MSG.OOB else 0) |
        @as(u32, if (@hasDecl(posix.MSG, "FASTOPEN") and flags.fastopen) posix.MSG.FASTOPEN else 0) |
        posix.MSG.NOSIGNAL;

    var i: usize = 0;
    while (messages.len - i != 0) {
        if (have_sendmmsg) {
            i += netSendManyPosix(socket_handle, messages[i..], posix_flags) catch |err| return .{ err, i };
            continue;
        }
        t.netSendOnePosix(socket_handle, &messages[i], posix_flags) catch |err| return .{ err, i };
        i += 1;
    }
    return .{ null, i };
}

fn netSendWindows(
    userdata: ?*anyopaque,
    socket_handle: net.Socket.Handle,
    messages: []net.OutgoingMessage,
    flags: net.SendFlags,
) struct { ?net.Socket.SendError, usize } {
    if (!have_networking) return .{ error.NetworkDown, 0 };
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    for (messages, 0..) |*m, i| {
        t.netSendOneWindows(socket_handle, m, flags) catch |err| return .{ err, i };
    }
    return .{ null, messages.len };
}

fn netSendOneWindows(
    t: *Threaded,
    socket_handle: net.Socket.Handle,
    message: *net.OutgoingMessage,
    flags: net.SendFlags,
) net.Socket.SendError!void {
    _ = t;
    _ = flags;
    const iovecs: [1]windows.AFD.WSABUF(.@"const") = .{.{
        .buf = message.data_ptr,
        .len = std.math.cast(std.os.windows.ULONG, message.data_len) orelse
            return error.MessageOversize,
    }};
    var storage: PosixAddress = undefined;
    const addr_len = addressToPosix(message.address, &storage);
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.SEND_DATAGRAM,
        .in = @ptrCast(&windows.AFD.SEND_DATAGRAM_INFO{
            .BufferArray = &iovecs,
            .BufferCount = iovecs.len,
            .AfdFlags = .{ .NO_FAST_IO = true, .OVERLAPPED = true },
            .TdiRequest = undefined,
            .TdiConnInfo = .{
                .UserDataLength = undefined,
                .UserData = undefined,
                .OptionsLength = undefined,
                .Options = undefined,
                .RemoteAddressLength = @bitCast(addr_len),
                .RemoteAddress = &storage,
            },
        }),
    })).u.Status) {
        .SUCCESS => return,
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netSendOnePosix(
    t: *Threaded,
    socket_handle: net.Socket.Handle,
    message: *net.OutgoingMessage,
    flags: u32,
) net.Socket.SendError!void {
    _ = t;
    var addr: PosixAddress = undefined;
    var iovec: posix.iovec_const = .{ .base = @constCast(message.data_ptr), .len = message.data_len };
    const msg: posix.msghdr_const = .{
        .name = &addr.any,
        .namelen = addressToPosix(message.address, &addr),
        .iov = (&iovec)[0..1],
        .iovlen = 1,
        // OS returns EINVAL if this pointer is invalid even if controllen is zero.
        .control = if (message.control.len == 0) null else @constCast(message.control.ptr),
        .controllen = @intCast(message.control.len),
        .flags = 0,
    };
    var syscall: if (is_windows) AlertableSyscall else Syscall = try .start();
    while (true) {
        const rc = posix.system.sendmsg(socket_handle, &msg, flags);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                message.data_len = @intCast(rc);
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ACCES => return syscall.fail(error.AccessDenied),
            .ALREADY => return syscall.fail(error.FastOpenAlreadyInProgress),
            .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
            .MSGSIZE => return syscall.fail(error.MessageOversize),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .PIPE => return syscall.fail(error.SocketUnconnected),
            .AFNOSUPPORT => return syscall.fail(error.AddressFamilyUnsupported),
            .HOSTUNREACH => return syscall.fail(error.HostUnreachable),
            .NETUNREACH => return syscall.fail(error.NetworkUnreachable),
            .NOTCONN => return syscall.fail(error.SocketUnconnected),
            .NETDOWN => return syscall.fail(error.NetworkDown),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            .DESTADDRREQ => |err| return syscall.errnoBug(err),
            .FAULT => |err| return syscall.errnoBug(err),
            .INVAL => |err| return syscall.errnoBug(err),
            .ISCONN => |err| return syscall.errnoBug(err),
            .NOTSOCK => |err| return syscall.errnoBug(err),
            .OPNOTSUPP => |err| return syscall.errnoBug(err),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn netSendManyPosix(
    socket_handle: net.Socket.Handle,
    messages: []net.OutgoingMessage,
    flags: u32,
) net.Socket.SendError!usize {
    var msg_buffer: [64]posix.system.mmsghdr = undefined;
    var addr_buffer: [msg_buffer.len]PosixAddress = undefined;
    var iovecs_buffer: [msg_buffer.len]posix.iovec = undefined;
    const min_len: usize = @min(messages.len, msg_buffer.len);
    const clamped_messages = messages[0..min_len];
    const clamped_msgs = (&msg_buffer)[0..min_len];
    const clamped_addrs = (&addr_buffer)[0..min_len];
    const clamped_iovecs = (&iovecs_buffer)[0..min_len];

    for (clamped_messages, clamped_msgs, clamped_addrs, clamped_iovecs) |*message, *msg, *addr, *iovec| {
        iovec.* = .{ .base = @constCast(message.data_ptr), .len = message.data_len };
        msg.* = .{
            .hdr = .{
                .name = &addr.any,
                .namelen = addressToPosix(message.address, addr),
                .iov = iovec[0..1],
                .iovlen = 1,
                .control = @constCast(message.control.ptr),
                .controllen = message.control.len,
                .flags = 0,
            },
            .len = undefined, // Populated by calling sendmmsg below.
        };
    }

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.sendmmsg(socket_handle, clamped_msgs.ptr, @intCast(clamped_msgs.len), flags);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const n: usize = @intCast(rc);
                for (clamped_messages[0..n], clamped_msgs[0..n]) |*message, *msg| {
                    message.data_len = msg.len;
                }
                return n;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ACCES => return syscall.fail(error.AccessDenied),
            .ALREADY => return syscall.fail(error.FastOpenAlreadyInProgress),
            .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
            .MSGSIZE => return syscall.fail(error.MessageOversize),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .PIPE => return syscall.fail(error.SocketUnconnected),
            .AFNOSUPPORT => return syscall.fail(error.AddressFamilyUnsupported),
            .HOSTUNREACH => return syscall.fail(error.HostUnreachable),
            .NETUNREACH => return syscall.fail(error.NetworkUnreachable),
            .NOTCONN => return syscall.fail(error.SocketUnconnected),
            .NETDOWN => return syscall.fail(error.NetworkDown),

            .AGAIN => |err| return syscall.errnoBug(err),
            .BADF => |err| return syscall.errnoBug(err), // File descriptor used after closed.
            .DESTADDRREQ => |err| return syscall.errnoBug(err), // The socket is not connection-mode, and no peer address is set.
            .FAULT => |err| return syscall.errnoBug(err), // An invalid user space address was specified for an argument.
            .INVAL => |err| return syscall.errnoBug(err), // Invalid argument passed.
            .ISCONN => |err| return syscall.errnoBug(err), // connection-mode socket was connected already but a recipient was specified
            .NOTSOCK => |err| return syscall.errnoBug(err), // The file descriptor sockfd does not refer to a socket.
            .OPNOTSUPP => |err| return syscall.errnoBug(err), // Some bit in the flags argument is inappropriate for the socket type.

            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn netReceivePosix(
    socket_handle: net.Socket.Handle,
    message: *net.IncomingMessage,
    data_buffer: []u8,
    flags: net.ReceiveFlags,
    nonblocking: bool,
) (net.Socket.ReceiveError || error{WouldBlock})!void {
    // recvmmsg is useless, here's why:
    // * [timeout bug](https://bugzilla.kernel.org/show_bug.cgi?id=75371)
    // * it wants iovecs for each message but we have a better API: one data
    //   buffer to handle all the messages. The better API cannot be lowered to
    //   the split vectors though because reducing the buffer size might make
    //   some messages unreceivable.
    const posix_flags: u32 =
        @as(u32, if (flags.oob) posix.MSG.OOB else 0) |
        @as(u32, if (flags.peek) posix.MSG.PEEK else 0) |
        @as(u32, if (flags.trunc) posix.MSG.TRUNC else 0) |
        posix.MSG.NOSIGNAL |
        @as(u32, if (nonblocking) posix.MSG.DONTWAIT else 0);

    var storage: PosixAddress = undefined;
    var iov: posix.iovec = .{ .base = data_buffer.ptr, .len = data_buffer.len };
    var msg: posix.msghdr = .{
        .name = &storage.any,
        .namelen = @sizeOf(PosixAddress),
        .iov = (&iov)[0..1],
        .iovlen = 1,
        .control = message.control.ptr,
        .controllen = @intCast(message.control.len),
        .flags = undefined,
    };

    const syscall = try Syscall.start();
    while (true) {
        const rc = posix.system.recvmsg(socket_handle, &msg, posix_flags);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const data = data_buffer[0..@intCast(rc)];
                message.* = .{
                    .from = addressFromPosix(&storage),
                    .data = data,
                    .control = if (msg.control) |ptr| @as([*]u8, @ptrCast(ptr))[0..msg.controllen] else message.control,
                    .flags = .{
                        .eor = (msg.flags & posix.MSG.EOR) != 0,
                        .trunc = (msg.flags & posix.MSG.TRUNC) != 0,
                        .ctrunc = (msg.flags & posix.MSG.CTRUNC) != 0,
                        .oob = (msg.flags & posix.MSG.OOB) != 0,
                        .errqueue = if (@hasDecl(posix.MSG, "ERRQUEUE")) (msg.flags & posix.MSG.ERRQUEUE) != 0 else false,
                    },
                };
                return;
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
            .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
            .NOBUFS => return syscall.fail(error.SystemResources),
            .NOMEM => return syscall.fail(error.SystemResources),
            .NOTCONN => return syscall.fail(error.SocketUnconnected),
            .MSGSIZE => return syscall.fail(error.MessageOversize),
            .PIPE => return syscall.fail(error.SocketUnconnected),
            .CONNRESET => return syscall.fail(error.ConnectionResetByPeer),
            .NETDOWN => return syscall.fail(error.NetworkDown),
            .AGAIN => return syscall.fail(error.WouldBlock),
            .BADF => |err| return syscall.errnoBug(err),
            .FAULT => |err| return syscall.errnoBug(err),
            .INVAL => |err| return syscall.errnoBug(err),
            .NOTSOCK => |err| return syscall.errnoBug(err),
            .OPNOTSUPP => |err| return syscall.errnoBug(err),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn netReceiveWindows(
    t: *Threaded,
    socket_handle: net.Socket.Handle,
    message_buffer: []net.IncomingMessage,
    data_buffer: []u8,
    flags: net.ReceiveFlags,
) struct { ?net.Socket.ReceiveError, usize } {
    t.netReceiveOneWindows(socket_handle, &message_buffer[0], data_buffer, flags) catch |err|
        return .{ err, 0 };
    return .{ null, 1 };
}

fn netReceiveOneWindows(
    t: *Threaded,
    socket_handle: net.Socket.Handle,
    message: *net.IncomingMessage,
    data_buffer: []u8,
    flags: net.ReceiveFlags,
) net.Socket.ReceiveError!void {
    if (!have_networking) return error.NetworkDown;
    _ = t;
    const iovecs: [1]windows.AFD.WSABUF(.@"var") = .{.{
        .buf = data_buffer.ptr,
        .len = std.math.cast(std.os.windows.ULONG, data_buffer.len) orelse return error.MessageOversize,
    }};
    var storage: PosixAddress = undefined;
    var addr_len: windows.ULONG = @sizeOf(PosixAddress);
    const iosb = try deviceIoControl(&.{
        .file = .{ .handle = socket_handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.RECEIVE_DATAGRAM,
        .in = @ptrCast(&windows.AFD.RECV_DATAGRAM_INFO{
            .BufferArray = &iovecs,
            .BufferCount = iovecs.len,
            .AfdFlags = .{ .NO_FAST_IO = true, .OVERLAPPED = true },
            .TdiFlags = .{ .NORMAL = !flags.oob, .EXPEDITED = flags.oob, .PEEK = flags.peek },
            .Address = &storage,
            .AddressLength = &addr_len,
        }),
    });
    switch (iosb.u.Status) {
        .SUCCESS, .RECEIVE_EXPEDITED => |status| message.* = .{
            .from = addressFromPosix(&storage),
            .data = data_buffer[0..iosb.Information],
            .control = &.{},
            .flags = .{
                .eor = false,
                .trunc = false,
                .ctrunc = false,
                .oob = switch (status) {
                    else => unreachable,
                    .SUCCESS, .RECEIVE_PARTIAL, .BUFFER_OVERFLOW => false,
                    .RECEIVE_EXPEDITED, .RECEIVE_PARTIAL_EXPEDITED => true,
                },
                .errqueue = false,
            },
        },
        .RECEIVE_PARTIAL,
        .RECEIVE_PARTIAL_EXPEDITED,
        => |status| return windows.unexpectedStatus(status), // TdiFlags.PARTIAL = false
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        .BUFFER_OVERFLOW => return error.MessageOversize,
        .PORT_UNREACHABLE => return error.PortUnreachable,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netWritePosix(
    userdata: ?*anyopaque,
    fd: net.Socket.Handle,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) net.Stream.Writer.Error!usize {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var iovecs: [max_iovecs_len]posix.iovec_const = undefined;
    var msg: posix.msghdr_const = .{
        .name = null,
        .namelen = 0,
        .iov = &iovecs,
        .iovlen = 0,
        .control = null,
        .controllen = 0,
        .flags = 0,
    };
    addBuf(&iovecs, &msg.iovlen, header);
    for (data[0 .. data.len - 1]) |bytes| addBuf(&iovecs, &msg.iovlen, bytes);
    const pattern = data[data.len - 1];

    var splat_backup_buffer: [splat_buffer_size]u8 = undefined;
    if (iovecs.len - msg.iovlen != 0) switch (splat) {
        0 => {},
        1 => addBuf(&iovecs, &msg.iovlen, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &splat_backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addBuf(&iovecs, &msg.iovlen, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and iovecs.len - msg.iovlen != 0) {
                    assert(buf.len == splat_buffer.len);
                    addBuf(&iovecs, &msg.iovlen, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addBuf(&iovecs, &msg.iovlen, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - msg.iovlen)) |_| {
                addBuf(&iovecs, &msg.iovlen, pattern);
            },
        },
    };
    const flags = posix.MSG.NOSIGNAL;

    const syscall: Syscall = try .start();
    while (true) {
        const rc = posix.system.sendmsg(fd, &msg, flags);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                return @intCast(rc);
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .ACCES => |err| return errnoBug(err),
                    .AGAIN => |err| return errnoBug(err),
                    .ALREADY => return error.FastOpenAlreadyInProgress,
                    .BADF => |err| return errnoBug(err), // File descriptor used after closed.
                    .CONNRESET => return error.ConnectionResetByPeer,
                    .DESTADDRREQ => |err| return errnoBug(err), // The socket is not connection-mode, and no peer address is set.
                    .FAULT => |err| return errnoBug(err), // An invalid user space address was specified for an argument.
                    .INVAL => |err| return errnoBug(err), // Invalid argument passed.
                    .ISCONN => |err| return errnoBug(err), // connection-mode socket was connected already but a recipient was specified
                    .MSGSIZE => |err| return errnoBug(err),
                    .NOBUFS => return error.SystemResources,
                    .NOMEM => return error.SystemResources,
                    .NOTSOCK => |err| return errnoBug(err), // The file descriptor sockfd does not refer to a socket.
                    .OPNOTSUPP => |err| return errnoBug(err), // Some bit in the flags argument is inappropriate for the socket type.
                    .PIPE => return error.SocketUnconnected,
                    .AFNOSUPPORT => return error.AddressFamilyUnsupported,
                    .HOSTUNREACH => return error.HostUnreachable,
                    .NETUNREACH => return error.NetworkUnreachable,
                    .NOTCONN => return error.SocketUnconnected,
                    .NETDOWN => return error.NetworkDown,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn netWriteWindows(
    userdata: ?*anyopaque,
    handle: net.Socket.Handle,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) net.Stream.Writer.Error!usize {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    var iovecs: [max_iovecs_len]windows.AFD.WSABUF(.@"const") = undefined;
    var len: u32 = 0;
    addAfdBuf(.@"const", &iovecs, &len, header);
    for (data[0 .. data.len - 1]) |bytes| addAfdBuf(.@"const", &iovecs, &len, bytes);
    const pattern = data[data.len - 1];
    var backup_buffer: [64]u8 = undefined;
    if (iovecs.len - len != 0) switch (splat) {
        0 => {},
        1 => addAfdBuf(.@"const", &iovecs, &len, pattern),
        else => switch (pattern.len) {
            0 => {},
            1 => {
                const splat_buffer = &backup_buffer;
                const memset_len = @min(splat_buffer.len, splat);
                const buf = splat_buffer[0..memset_len];
                @memset(buf, pattern[0]);
                addAfdBuf(.@"const", &iovecs, &len, buf);
                var remaining_splat = splat - buf.len;
                while (remaining_splat > splat_buffer.len and len < iovecs.len) {
                    addAfdBuf(.@"const", &iovecs, &len, splat_buffer);
                    remaining_splat -= splat_buffer.len;
                }
                addAfdBuf(.@"const", &iovecs, &len, splat_buffer[0..@min(remaining_splat, splat_buffer.len)]);
            },
            else => for (0..@min(splat, iovecs.len - len)) |_| {
                addAfdBuf(.@"const", &iovecs, &len, pattern);
            },
        },
    };

    const iosb = try deviceIoControl(&.{
        .file = .{ .handle = handle, .flags = .{ .nonblocking = true } },
        .code = windows.IOCTL.AFD.SEND,
        .in = @ptrCast(&windows.AFD.SEND_INFO{
            .BufferArray = &iovecs,
            .BufferCount = len,
            .AfdFlags = .{ .NO_FAST_IO = true, .OVERLAPPED = true },
            .TdiFlags = .{},
        }),
    });
    switch (iosb.u.Status) {
        .SUCCESS => return iosb.Information,
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn addAfdBuf(
    comptime mutability: windows.AFD.Mutability,
    iovecs: []windows.AFD.WSABUF(mutability),
    len: *u32,
    bytes: switch (mutability) {
        .@"const" => []const u8,
        .@"var" => []u8,
    },
) void {
    if (bytes.len == 0) return;
    const cap = std.math.maxInt(u32);
    var remaining = bytes;
    while (remaining.len > cap) {
        if (iovecs.len - len.* == 0) return;
        iovecs[len.*] = .{ .buf = remaining.ptr, .len = cap };
        len.* += 1;
        remaining = remaining[cap..];
    } else {
        @branchHint(.likely);
        if (iovecs.len - len.* == 0) return;
        iovecs[len.*] = .{ .buf = remaining.ptr, .len = @intCast(remaining.len) };
        len.* += 1;
    }
}

/// This is either usize or u32. Since, either is fine, let's use the same
/// `addBuf` function for both writing to a file and sending network messages.
const iovlen_t = switch (native_os) {
    .wasi => u32,
    else => @FieldType(posix.msghdr_const, "iovlen"),
};

fn addBuf(v: []posix.iovec_const, i: *iovlen_t, bytes: []const u8) void {
    // OS checks ptr addr before length so zero length vectors must be omitted.
    if (bytes.len == 0) return;
    if (v.len - i.* == 0) return;
    v[i.*] = .{ .base = bytes.ptr, .len = bytes.len };
    i.* += 1;
}

fn netClose(userdata: ?*anyopaque, handles: []const net.Socket.Handle) void {
    if (!have_networking) unreachable;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    for (handles) |handle| switch (native_os) {
        .windows => windows.CloseHandle(handle),
        else => closeFd(handle),
    };
}

fn netShutdownPosix(userdata: ?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    const posix_how: i32 = switch (how) {
        .recv => posix.SHUT.RD,
        .send => posix.SHUT.WR,
        .both => posix.SHUT.RDWR,
    };

    const syscall: Syscall = try .start();
    while (true) {
        switch (posix.errno(posix.system.shutdown(handle, posix_how))) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => |e| {
                syscall.finish();
                switch (e) {
                    .BADF, .NOTSOCK, .INVAL => |err| return errnoBug(err),
                    .NOTCONN => return error.SocketUnconnected,
                    .NOBUFS => return error.SystemResources,
                    else => |err| return posix.unexpectedErrno(err),
                }
            },
        }
    }
}

fn netShutdownWindows(userdata: ?*anyopaque, handle: net.Socket.Handle, how: net.ShutdownHow) net.ShutdownError!void {
    if (!have_networking) return error.NetworkDown;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    // shutdown does not support apcs at all
    switch ((try deviceIoControl(&.{
        .file = .{ .handle = handle, .flags = .{ .nonblocking = false } },
        .code = windows.IOCTL.AFD.PARTIAL_DISCONNECT,
        .in = @ptrCast(&windows.AFD.PARTIAL_DISCONNECT_INFO{
            .DisconnectMode = .{ .SEND = how != .recv, .RECEIVE = how != .send },
            .Timeout = -1,
        }),
    })).u.Status) {
        .SUCCESS => {},
        .CANCELLED => unreachable,
        .INSUFFICIENT_RESOURCES => return error.SystemResources,
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn netInterfaceNameResolve(
    userdata: ?*anyopaque,
    name: *const net.Interface.Name,
) net.Interface.Name.ResolveError!net.Interface {
    if (!have_networking) return error.InterfaceNotFound;
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    if (native_os == .linux) {
        const sock_fd = openSocketPosix(posix.AF.UNIX, .{ .mode = .dgram }) catch |err| switch (err) {
            error.ProcessFdQuotaExceeded => return error.SystemResources,
            error.SystemFdQuotaExceeded => return error.SystemResources,
            error.AddressFamilyUnsupported => return error.Unexpected,
            error.ProtocolUnsupportedBySystem => return error.Unexpected,
            error.ProtocolUnsupportedByAddressFamily => return error.Unexpected,
            error.SocketModeUnsupported => return error.Unexpected,
            error.OptionUnsupported => return error.Unexpected,
            else => |e| return e,
        };
        defer closeFd(sock_fd);

        var ifr: posix.ifreq = .{
            .ifrn = .{ .name = @bitCast(name.bytes) },
            .ifru = undefined,
        };

        const syscall: Syscall = try .start();
        while (true) switch (posix.errno(posix.system.ioctl(sock_fd, posix.SIOCGIFINDEX, @intFromPtr(&ifr)))) {
            .SUCCESS => {
                syscall.finish();
                return .{ .index = @bitCast(ifr.ifru.ivalue) };
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .NODEV => return syscall.fail(error.InterfaceNotFound),
            else => |err| return syscall.unexpectedErrno(err),
        };
    }

    if (is_windows) {
        var ConvertInterfaceNameToLuidW = t.dl.ConvertInterfaceNameToLuidW.load(.acquire);
        var ConvertInterfaceLuidToIndex = t.dl.ConvertInterfaceLuidToIndex.load(.acquire);
        if (ConvertInterfaceNameToLuidW == null or ConvertInterfaceLuidToIndex == null) {
            const iphlpapi_dll = t.dl.iphlpapi_dll.load(.acquire) orelse iphlpapi_dll: {
                try Thread.checkCancel();
                var iphlpapi_dll: *anyopaque = undefined;
                switch (windows.ntdll.LdrLoadDll(null, null, &.init(
                    &.{ 'I', 'P', 'H', 'L', 'P', 'A', 'P', 'I', '.', 'D', 'L', 'L' },
                ), &iphlpapi_dll)) {
                    .SUCCESS => {},
                    .DLL_NOT_FOUND => return error.Unexpected,
                    else => |status| return windows.unexpectedStatus(status),
                }
                const handle = t.dl.iphlpapi_dll.cmpxchgStrong(null, iphlpapi_dll, .release, .monotonic) orelse
                    break :iphlpapi_dll iphlpapi_dll;
                switch (windows.ntdll.LdrUnloadDll(iphlpapi_dll)) {
                    .SUCCESS => break :iphlpapi_dll handle.?,
                    else => |status| return windows.unexpectedStatus(status),
                }
            };
            switch (windows.ntdll.LdrGetProcedureAddress(iphlpapi_dll, &.init(
                &.{
                    'C', 'o', 'n', 'v', 'e', 'r', 't', 'I', 'n', 't', 'e', 'r', 'f', 'a', 'c', 'e',
                    'N', 'a', 'm', 'e', 'T', 'o', 'L', 'u', 'i', 'd', 'W',
                },
            ), 0, @ptrCast(&ConvertInterfaceNameToLuidW))) {
                .SUCCESS => t.dl.ConvertInterfaceNameToLuidW.store(ConvertInterfaceNameToLuidW, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
            switch (windows.ntdll.LdrGetProcedureAddress(iphlpapi_dll, &.init(
                &.{
                    'C', 'o', 'n', 'v', 'e', 'r', 't', 'I', 'n', 't', 'e', 'r', 'f', 'a', 'c', 'e',
                    'L', 'u', 'i', 'd', 'T', 'o', 'I', 'n', 'd', 'e', 'x',
                },
            ), 0, @ptrCast(&ConvertInterfaceLuidToIndex))) {
                .SUCCESS => t.dl.ConvertInterfaceLuidToIndex.store(ConvertInterfaceLuidToIndex, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
        }
        try Thread.checkCancel();
        var name_w: [net.Interface.Name.max_len:0]windows.WCHAR = undefined;
        name_w[
            std.unicode.wtf8ToWtf16Le(&name_w, name.toSlice()) catch |err| switch (err) {
                error.InvalidWtf8 => return error.InterfaceNotFound,
            }
        ] = 0;
        var luid: windows.NET.LUID = undefined;
        switch (ConvertInterfaceNameToLuidW.?(&name_w, &luid)) {
            .SUCCESS => {},
            .INVALID_NAME => return error.InterfaceNotFound,
            .INVALID_PARAMETER => unreachable,
            else => |err| return windows.unexpectedError(err),
        }
        var index: windows.NET.IFINDEX = undefined;
        switch (ConvertInterfaceLuidToIndex.?(&luid, &index)) {
            .SUCCESS => {},
            .INVALID_PARAMETER => unreachable,
            else => |err| return windows.unexpectedError(err),
        }
        return .{ .index = @intFromEnum(index) };
    }

    if (builtin.link_libc) {
        try Thread.checkCancel();
        const index = std.c.if_nametoindex(&name.bytes);
        if (index == 0) return error.InterfaceNotFound;
        return .{ .index = @bitCast(index) };
    }

    @panic("unimplemented");
}

fn netInterfaceName(userdata: ?*anyopaque, interface: net.Interface) net.Interface.NameError!net.Interface.Name {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    if (native_os == .linux) {
        try Thread.checkCancel();
        @panic("TODO implement netInterfaceName for linux");
    }

    if (is_windows) {
        var ConvertInterfaceIndexToLuid = t.dl.ConvertInterfaceIndexToLuid.load(.acquire);
        var ConvertInterfaceLuidToNameW = t.dl.ConvertInterfaceLuidToNameW.load(.acquire);
        if (ConvertInterfaceIndexToLuid == null or ConvertInterfaceLuidToNameW == null) {
            const iphlpapi_dll = t.dl.iphlpapi_dll.load(.acquire) orelse iphlpapi_dll: {
                try Thread.checkCancel();
                var iphlpapi_dll: *anyopaque = undefined;
                switch (windows.ntdll.LdrLoadDll(null, null, &.init(
                    &.{ 'I', 'P', 'H', 'L', 'P', 'A', 'P', 'I', '.', 'D', 'L', 'L' },
                ), &iphlpapi_dll)) {
                    .SUCCESS => {},
                    .DLL_NOT_FOUND => return error.Unexpected,
                    else => |status| return windows.unexpectedStatus(status),
                }
                const handle = t.dl.iphlpapi_dll.cmpxchgStrong(null, iphlpapi_dll, .release, .monotonic) orelse
                    break :iphlpapi_dll iphlpapi_dll;
                switch (windows.ntdll.LdrUnloadDll(iphlpapi_dll)) {
                    .SUCCESS => break :iphlpapi_dll handle.?,
                    else => |status| return windows.unexpectedStatus(status),
                }
            };
            switch (windows.ntdll.LdrGetProcedureAddress(iphlpapi_dll, &.init(
                &.{
                    'C', 'o', 'n', 'v', 'e', 'r', 't', 'I', 'n', 't', 'e', 'r', 'f', 'a', 'c', 'e',
                    'I', 'n', 'd', 'e', 'x', 'T', 'o', 'L', 'u', 'i', 'd',
                },
            ), 0, @ptrCast(&ConvertInterfaceIndexToLuid))) {
                .SUCCESS => t.dl.ConvertInterfaceIndexToLuid.store(ConvertInterfaceIndexToLuid, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
            switch (windows.ntdll.LdrGetProcedureAddress(iphlpapi_dll, &.init(
                &.{
                    'C', 'o', 'n', 'v', 'e', 'r', 't', 'I', 'n', 't', 'e', 'r', 'f', 'a', 'c', 'e',
                    'L', 'u', 'i', 'd', 'T', 'o', 'N', 'a', 'm', 'e', 'W',
                },
            ), 0, @ptrCast(&ConvertInterfaceLuidToNameW))) {
                .SUCCESS => t.dl.ConvertInterfaceLuidToNameW.store(ConvertInterfaceLuidToNameW, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
        }
        try Thread.checkCancel();
        var luid: windows.NET.LUID = undefined;
        switch (ConvertInterfaceIndexToLuid.?(@enumFromInt(interface.index), &luid)) {
            .SUCCESS => {},
            .FILE_NOT_FOUND => return error.InterfaceNotFound,
            .INVALID_PARAMETER => unreachable,
            else => |err| return windows.unexpectedError(err),
        }
        var name_w: [net.Interface.Name.max_len:0]windows.WCHAR = undefined;
        switch (ConvertInterfaceLuidToNameW.?(&luid, &name_w, name_w.len)) {
            .SUCCESS => {},
            .INVALID_PARAMETER => unreachable,
            .NOT_ENOUGH_MEMORY => return error.NameTooLong,
            else => |err| return windows.unexpectedError(err),
        }
        var name: [3 * net.Interface.Name.max_len]u8 = undefined;
        return .fromSlice(name[0..std.unicode.wtf16LeToWtf8(&name, std.mem.sliceTo(&name_w, 0))]);
    }

    if (builtin.link_libc) {
        try Thread.checkCancel();
        @panic("TODO implement netInterfaceName for libc");
    }

    @panic("unimplemented");
}

fn netLookup(
    userdata: ?*anyopaque,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) net.HostName.LookupError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    defer resolved.close(io(t));
    t.netLookupFallible(host_name, resolved, options) catch |err| switch (err) {
        error.Closed => unreachable, // `resolved` must not be closed until `netLookup` returns
        else => |e| return e,
    };
}

fn netLookupFallible(
    t: *Threaded,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) (net.HostName.LookupError || Io.QueueClosedError)!void {
    if (!have_networking) return error.NetworkDown;

    const t_io = t.io();
    const name = host_name.bytes;
    assert(name.len <= HostName.max_len);

    // On Linux, glibc provides getaddrinfo_a which is capable of supporting our semantics.
    // However, musl's POSIX-compliant getaddrinfo is not, so we bypass it.

    if (builtin.target.isGnuLibC()) {
        // TODO use getaddrinfo_a / gai_cancel
    }

    if (native_os == .linux or is_windows) {
        if (IpAddress.parseIp6(name, options.port)) |addr| {
            if (options.family == .ip4) return error.UnknownHostName;
            if (copyCanon(options.canonical_name_buffer, name)) |canon| {
                try resolved.putAll(t_io, &.{
                    .{ .address = addr },
                    .{ .canonical_name = canon },
                });
            } else {
                try resolved.putOne(t_io, .{ .address = addr });
            }
            return;
        } else |_| {}

        if (IpAddress.parseIp4(name, options.port)) |addr| {
            if (options.family == .ip6) return error.UnknownHostName;
            if (copyCanon(options.canonical_name_buffer, name)) |canon| {
                try resolved.putAll(t_io, &.{
                    .{ .address = addr },
                    .{ .canonical_name = canon },
                });
            } else {
                try resolved.putOne(t_io, .{ .address = addr });
            }
            return;
        } else |_| {}

        if (t.lookupHosts(host_name, resolved, options)) return else |err| switch (err) {
            error.UnknownHostName => {},
            else => |e| return e,
        }

        // RFC 6761 Section 6.3.3
        // Name resolution APIs and libraries SHOULD recognize
        // localhost names as special and SHOULD always return the IP
        // loopback address for address queries and negative responses
        // for all other query types.

        // Check for equal to "localhost(.)" or ends in ".localhost(.)"
        const localhost = if (name[name.len - 1] == '.') "localhost." else "localhost";
        if (std.mem.endsWith(u8, name, localhost) and
            (name.len == localhost.len or name[name.len - localhost.len] == '.'))
        {
            var results_buffer: [3]HostName.LookupResult = undefined;
            var results_index: usize = 0;
            if (options.family != .ip4) {
                results_buffer[results_index] = .{ .address = .{ .ip6 = .loopback(options.port) } };
                results_index += 1;
            }
            if (options.family != .ip6) {
                results_buffer[results_index] = .{ .address = .{ .ip4 = .loopback(options.port) } };
                results_index += 1;
            }
            if (options.canonical_name_buffer) |buf| {
                const canon_name = "localhost";
                const canon_name_dest = buf[0..canon_name.len];
                canon_name_dest.* = canon_name.*;
                results_buffer[results_index] = .{ .canonical_name = .{ .bytes = canon_name_dest } };
                results_index += 1;
            }
            try resolved.putAll(t_io, results_buffer[0..results_index]);
            return;
        }

        if (native_os == .linux) return t.lookupDnsSearch(host_name, resolved, options);

        comptime assert(is_windows);
        var DnsQueryEx = t.dl.DnsQueryEx.load(.acquire);
        //var DnsCancelQuery = t.dl.DnsCancelQuery.load(.acquire);
        var DnsFree = t.dl.DnsFree.load(.acquire);
        if (DnsQueryEx == null or
            //DnsCancelQuery == null or
            DnsFree == null)
        {
            const dnsapi_dll = t.dl.dnsapi_dll.load(.acquire) orelse dnsapi_dll: {
                try Thread.checkCancel();
                var dnsapi_dll: *anyopaque = undefined;
                switch (windows.ntdll.LdrLoadDll(null, null, &.init(
                    &.{ 'd', 'n', 's', 'a', 'p', 'i', '.', 'd', 'l', 'l' },
                ), &dnsapi_dll)) {
                    .SUCCESS => {},
                    .DLL_NOT_FOUND => return error.Unexpected,
                    else => |status| return windows.unexpectedStatus(status),
                }
                const handle = t.dl.dnsapi_dll.cmpxchgStrong(null, dnsapi_dll, .release, .monotonic) orelse
                    break :dnsapi_dll dnsapi_dll;
                switch (windows.ntdll.LdrUnloadDll(dnsapi_dll)) {
                    .SUCCESS => break :dnsapi_dll handle.?,
                    else => |status| return windows.unexpectedStatus(status),
                }
            };
            switch (windows.ntdll.LdrGetProcedureAddress(dnsapi_dll, &.init(
                &.{ 'D', 'n', 's', 'Q', 'u', 'e', 'r', 'y', 'E', 'x' },
            ), 0, @ptrCast(&DnsQueryEx))) {
                .SUCCESS => t.dl.DnsQueryEx.store(DnsQueryEx, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
            //switch (windows.ntdll.LdrGetProcedureAddress(dnsapi_dll, &.init(
            //    &.{ 'D', 'n', 's', 'C', 'a', 'n', 'c', 'e', 'l', 'Q', 'u', 'e', 'r', 'y' },
            //), 0, @ptrCast(&DnsCancelQuery))) {
            //    .SUCCESS => t.dl.DnsCancelQuery.store(DnsCancelQuery, .release),
            //    else => |status| return windows.unexpectedStatus(status),
            //}
            switch (windows.ntdll.LdrGetProcedureAddress(dnsapi_dll, &.init(
                &.{ 'D', 'n', 's', 'F', 'r', 'e', 'e' },
            ), 0, @ptrCast(&DnsFree))) {
                .SUCCESS => t.dl.DnsFree.store(DnsFree, .release),
                else => |status| return windows.unexpectedStatus(status),
            }
        }
        try Thread.checkCancel();
        const current_thread = Thread.current;
        var lookup_dns: LookupDnsWindows = .{
            .threaded = t,
            .thread = if (current_thread) |thread| thread.handle else undefined,
            .resolved = resolved,
            .options = options,
            .results = .{
                .Version = 1,
                .QueryStatus = undefined,
                .QueryOptions = undefined,
                .pQueryRecords = undefined,
                .Reserved = undefined,
            },
            .done = false,
        };
        var host_name_w: [HostName.max_len:0]windows.WCHAR = undefined;
        host_name_w[
            std.unicode.wtf8ToWtf16Le(&host_name_w, name) catch |err| switch (err) {
                error.InvalidWtf8 => return error.UnknownHostName,
            }
        ] = 0;
        //var cancel_token: windows.DNS.QUERY.CANCEL = undefined;
        // Workaround various bugs by attempting a synchronous non-wire query first
        switch (DnsQueryEx.?(&.{
            .Version = 1,
            .QueryName = &host_name_w,
            .QueryType = if (options.family == .ip4) .A else .AAAA,
            .QueryOptions = .{
                .NO_WIRE_QUERY = true,
                .NO_HOSTS_FILE = true, // handled above
                .ADDRCONFIG = true,
                .DUAL_ADDR = options.family == null,
            },
        }, &lookup_dns.results, null)) {
            .SUCCESS => try lookup_dns.completedFallible(),
            // We must wait for the APC routine.
            .DNS_REQUEST_PENDING => unreachable, // `pQueryCompletionCallback` was `null`
            .DNS_ERROR_RECORD_DOES_NOT_EXIST => switch (DnsQueryEx.?(&.{
                .Version = 1,
                .QueryName = &host_name_w,
                .QueryType = if (options.family == .ip4) .A else .AAAA,
                .QueryOptions = .{
                    .NO_HOSTS_FILE = true, // handled above
                    .ADDRCONFIG = true,
                    .DUAL_ADDR = options.family == null,
                    .MULTICAST_WAIT = true,
                },
                .pQueryCompletionCallback = if (current_thread) |_| &LookupDnsWindows.completed else null,
            }, &lookup_dns.results,
                //&cancel_token,
                null)) {
                .SUCCESS => try lookup_dns.completedFallible(),
                // We must wait for the APC routine.
                .DNS_REQUEST_PENDING => {
                    assert(current_thread != null); // `pQueryCompletionCallback` was `null`
                    while (!@atomicLoad(bool, &lookup_dns.done, .acquire)) {
                        // Once we get here we must not return from the function until the
                        // operation completes, thereby releasing references to `host_name_w`,
                        // `lookup_dns.results`, and `cancel_token`.
                        const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                            error.Canceled => |e| {
                                //_ = DnsCancelQuery.?(&cancel_token);
                                while (!@atomicLoad(bool, &lookup_dns.done, .acquire)) waitForApcOrAlert();
                                return e;
                            },
                        };
                        waitForApcOrAlert();
                        alertable_syscall.finish();
                    }
                },
                else => |status| lookup_dns.results.QueryStatus = status,
            },
            else => |status| lookup_dns.results.QueryStatus = status,
        }
        switch (lookup_dns.results.QueryStatus) {
            .SUCCESS => return,
            .DNS_REQUEST_PENDING => unreachable, // already handled
            .INVALID_NAME,
            .DNS_ERROR_RCODE_NAME_ERROR,
            .DNS_INFO_NO_RECORDS,
            .DNS_ERROR_INVALID_NAME_CHAR,
            .DNS_ERROR_RECORD_DOES_NOT_EXIST,
            => return error.UnknownHostName,
            else => |err| return windows.unexpectedError(err),
        }
    }

    if (native_os == .openbsd) {
        // TODO use getaddrinfo_async / asr_abort
    }

    if (native_os == .freebsd) {
        // TODO use dnsres_getaddrinfo
    }

    if (is_darwin) {
        // TODO use CFHostStartInfoResolution / CFHostCancelInfoResolution
    }

    if (builtin.link_libc) {
        // This operating system lacks a way to resolve asynchronously. We are
        // stuck with getaddrinfo.
        var name_buffer: [HostName.max_len:0]u8 = undefined;
        @memcpy(name_buffer[0..name.len], name);
        name_buffer[name.len] = 0;
        const name_c = name_buffer[0..name.len :0];

        var port_buffer: [8]u8 = undefined;
        const port_c = std.fmt.bufPrintZ(&port_buffer, "{d}", .{options.port}) catch unreachable;

        const hints: posix.addrinfo = .{
            .flags = .{ .CANONNAME = options.canonical_name_buffer != null, .NUMERICSERV = true },
            .family = posix.AF.UNSPEC,
            .socktype = posix.SOCK.STREAM,
            .protocol = posix.IPPROTO.TCP,
            .canonname = null,
            .addr = null,
            .addrlen = 0,
            .next = null,
        };
        var res: ?*posix.addrinfo = null;
        const syscall: Syscall = try .start();
        while (true) {
            switch (posix.system.getaddrinfo(name_c.ptr, port_c.ptr, &hints, &res)) {
                @as(posix.system.EAI, @enumFromInt(0)) => {
                    syscall.finish();
                    break;
                },
                .SYSTEM => switch (posix.errno(-1)) {
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => |e| {
                        syscall.finish();
                        return posix.unexpectedErrno(e);
                    },
                },
                else => |e| {
                    syscall.finish();
                    switch (e) {
                        .ADDRFAMILY => return error.AddressFamilyUnsupported,
                        .AGAIN => return error.NameServerFailure,
                        .FAIL => return error.NameServerFailure,
                        .FAMILY => return error.AddressFamilyUnsupported,
                        .MEMORY => return error.SystemResources,
                        .NODATA => return error.UnknownHostName,
                        .NONAME => return error.UnknownHostName,
                        else => return error.Unexpected,
                    }
                },
            }
        }
        defer if (res) |some| posix.system.freeaddrinfo(some);

        var it = res;
        var canon_name: ?[*:0]const u8 = null;
        while (it) |info| : (it = info.next) {
            const addr = info.addr orelse continue;
            try resolved.putOne(t_io, .{ .address = addressFromPosix(@alignCast(@fieldParentPtr("any", addr))) });

            if (info.canonname) |n| {
                if (canon_name == null) {
                    canon_name = n;
                }
            }
        }
        if (canon_name) |n| {
            if (copyCanon(options.canonical_name_buffer, std.mem.sliceTo(n, 0))) |canon| {
                try resolved.putOne(t_io, .{ .canonical_name = canon });
            }
        }
        return;
    }

    return error.OptionUnsupported;
}

fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const current_thread_id = Thread.currentId();

    if (@atomicLoad(std.Thread.Id, &t.stderr_mutex_locker, .unordered) != current_thread_id) {
        mutexLock(&t.stderr_mutex);
        assert(t.stderr_mutex_lock_count == 0);
        @atomicStore(std.Thread.Id, &t.stderr_mutex_locker, current_thread_id, .unordered);
    }
    t.stderr_mutex_lock_count += 1;

    return initLockedStderr(t, terminal_mode);
}

fn tryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!?Io.LockedStderr {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const current_thread_id = Thread.currentId();

    if (@atomicLoad(std.Thread.Id, &t.stderr_mutex_locker, .unordered) != current_thread_id) {
        if (!t.stderr_mutex.tryLock()) return null;
        assert(t.stderr_mutex_lock_count == 0);
        @atomicStore(std.Thread.Id, &t.stderr_mutex_locker, current_thread_id, .unordered);
    }
    t.stderr_mutex_lock_count += 1;

    return try initLockedStderr(t, terminal_mode);
}

fn initLockedStderr(t: *Threaded, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    if (!t.stderr_writer_initialized) {
        const io_t = io(t);
        if (is_windows) t.stderr_writer.file = .stderr();
        t.stderr_writer.io = io_t;
        t.stderr_writer_initialized = true;
        t.scanEnviron();
        const NO_COLOR = t.environ.exist.NO_COLOR;
        const CLICOLOR_FORCE = t.environ.exist.CLICOLOR_FORCE;
        t.stderr_mode = terminal_mode orelse try .detect(io_t, t.stderr_writer.file, NO_COLOR, CLICOLOR_FORCE);
    }
    return .{
        .file_writer = &t.stderr_writer,
        .terminal_mode = terminal_mode orelse t.stderr_mode,
    };
}

fn unlockStderr(userdata: ?*anyopaque) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (t.stderr_writer.err == null) t.stderr_writer.interface.flush() catch {};
    if (t.stderr_writer.err) |err| {
        switch (err) {
            error.Canceled => recancelInner(),
            else => {},
        }
        t.stderr_writer.err = null;
    }
    t.stderr_writer.interface.end = 0;
    t.stderr_writer.interface.buffer = &.{};

    t.stderr_mutex_lock_count -= 1;
    if (t.stderr_mutex_lock_count == 0) {
        @atomicStore(std.Thread.Id, &t.stderr_mutex_locker, Thread.invalid_id, .unordered);
        mutexUnlock(&t.stderr_mutex);
    }
}

fn processCurrentPath(userdata: ?*anyopaque, buffer: []u8) process.CurrentPathError!usize {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    if (is_windows) {
        var wtf16le_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
        const n = windows.ntdll.RtlGetCurrentDirectory_U(wtf16le_buf.len * 2 + 2, &wtf16le_buf) / 2;
        if (n == 0) return error.Unexpected;
        assert(n <= wtf16le_buf.len);
        const wtf16le_slice = wtf16le_buf[0..n];
        var end_index: usize = 0;
        var it = std.unicode.Wtf16LeIterator.init(wtf16le_slice);
        while (it.nextCodepoint()) |codepoint| {
            const seq_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            if (end_index + seq_len >= buffer.len)
                return error.NameTooLong;
            end_index += std.unicode.wtf8Encode(codepoint, buffer[end_index..]) catch unreachable;
        }
        return end_index;
    } else if (native_os == .wasi and !builtin.link_libc) {
        if (buffer.len == 0) return error.NameTooLong;
        buffer[0] = '.';
        return 1;
    }

    const err: posix.E = if (builtin.link_libc) err: {
        const c_err = if (std.c.getcwd(buffer.ptr, buffer.len)) |_| 0 else std.c._errno().*;
        break :err @enumFromInt(c_err);
    } else err: {
        break :err posix.errno(posix.system.getcwd(buffer.ptr, buffer.len));
    };
    switch (err) {
        .SUCCESS => return std.mem.findScalar(u8, buffer, 0).?,
        .NOENT => return error.CurrentDirUnlinked,
        .RANGE => return error.NameTooLong,
        .FAULT => |e| return errnoBug(e),
        .INVAL => |e| return errnoBug(e),
        else => return posix.unexpectedErrno(err),
    }
}

fn processSetCurrentDir(userdata: ?*anyopaque, dir: Dir) process.SetCurrentDirError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (native_os == .wasi) return error.OperationUnsupported;

    if (is_windows) {
        var dir_path_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
        const dir_path = try GetFinalPathNameByHandle(dir.handle, .{}, &dir_path_buf);
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.RtlSetCurrentDirectory_U(&.init(dir_path))) {
            .SUCCESS => return syscall.finish(),
            .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
            .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
            .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .OBJECT_PATH_SYNTAX_BAD => |err| return syscall.ntstatusBug(err),
            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    return fchdir(dir.handle);
}

fn processSetCurrentPath(userdata: ?*anyopaque, path: []const u8) process.SetCurrentPathError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;

    if (native_os == .wasi) return error.OperationUnsupported;

    if (is_windows) {
        var path_w_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
        const len = std.unicode.calcWtf16LeLen(path) catch return error.InvalidWtf8;
        if (len > path_w_buf.len) return error.NameTooLong;
        const path_w_len = std.unicode.wtf8ToWtf16Le(&path_w_buf, path) catch |err| switch (err) {
            error.InvalidWtf8 => unreachable, // already validated
        };
        const path_w = path_w_buf[0..path_w_len];

        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.RtlSetCurrentDirectory_U(&.init(path_w))) {
            .SUCCESS => return syscall.finish(),
            .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
            .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
            .INVALID_PARAMETER => |err| return syscall.ntstatusBug(err),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .OBJECT_PATH_SYNTAX_BAD => |err| return syscall.ntstatusBug(err),
            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            else => |status| return syscall.unexpectedNtstatus(status),
        };
    }

    return chdir(path);
}

pub const PosixAddress = extern union {
    any: posix.sockaddr,
    in: posix.sockaddr.in,
    in6: posix.sockaddr.in6,
};

const UnixAddress = extern union {
    any: posix.sockaddr,
    un: posix.sockaddr.un,
};

pub fn posixAddressFamily(a: *const IpAddress) posix.sa_family_t {
    return switch (a.*) {
        .ip4 => posix.AF.INET,
        .ip6 => posix.AF.INET6,
    };
}

pub fn addressFromPosix(posix_address: *const PosixAddress) IpAddress {
    return switch (posix_address.any.family) {
        posix.AF.INET => .{ .ip4 = address4FromPosix(&posix_address.in) },
        posix.AF.INET6 => .{ .ip6 = address6FromPosix(&posix_address.in6) },
        else => .{ .ip4 = .loopback(0) },
    };
}

pub fn addressToPosix(a: *const IpAddress, storage: *PosixAddress) posix.socklen_t {
    return switch (a.*) {
        .ip4 => |ip4| {
            storage.in = address4ToPosix(ip4);
            return @sizeOf(posix.sockaddr.in);
        },
        .ip6 => |*ip6| {
            storage.in6 = address6ToPosix(ip6);
            return @sizeOf(posix.sockaddr.in6);
        },
    };
}

fn addressUnixToPosix(a: *const net.UnixAddress, storage: *UnixAddress) posix.socklen_t {
    storage.un.family = posix.AF.UNIX;
    var path_len = switch (native_os) {
        .windows => @min(a.path.len, storage.un.path.len),
        else => a.path.len,
    };
    // With the AFD API, `sockaddr.un` is purely informational, so
    // use a suffix which is usually the most relevant part of a path.
    @memcpy(storage.un.path[0..path_len], a.path[a.path.len - path_len ..]);
    if (storage.un.path.len - path_len > 0) {
        @branchHint(.likely);
        storage.un.path[path_len] = 0;
        path_len += 1;
    }
    switch (native_os) {
        .windows => {
            if (storage.un.path[0] == 0) @memset(storage.un.path[path_len..], 0);
            return @sizeOf(posix.sockaddr.un);
        },
        else => return @intCast(@offsetOf(posix.sockaddr.un, "path") + path_len),
    }
}

fn address4FromPosix(in: *const posix.sockaddr.in) net.Ip4Address {
    return .{
        .port = std.mem.bigToNative(u16, in.port),
        .bytes = @bitCast(in.addr),
    };
}

fn address6FromPosix(in6: *const posix.sockaddr.in6) net.Ip6Address {
    return .{
        .port = std.mem.bigToNative(u16, in6.port),
        .bytes = in6.addr,
        .flow = in6.flowinfo,
        .interface = .{ .index = in6.scope_id },
    };
}

fn address4ToPosix(a: net.Ip4Address) posix.sockaddr.in {
    return .{
        .port = std.mem.nativeToBig(u16, a.port),
        .addr = @bitCast(a.bytes),
    };
}

fn address6ToPosix(a: *const net.Ip6Address) posix.sockaddr.in6 {
    return .{
        .port = std.mem.nativeToBig(u16, a.port),
        .flowinfo = a.flow,
        .addr = a.bytes,
        .scope_id = a.interface.index,
    };
}

pub fn errnoBug(err: posix.E) Io.UnexpectedError {
    if (is_debug) std.debug.panic("programmer bug caused syscall error: {t}", .{err});
    return error.Unexpected;
}

pub fn posixSocketModeProtocol(family: posix.sa_family_t, mode: net.Socket.Mode, protocol: ?net.Protocol) !struct { u32, u32 } {
    return .{
        switch (mode) {
            .stream => posix.SOCK.STREAM,
            .dgram => posix.SOCK.DGRAM,
            .seqpacket => posix.SOCK.SEQPACKET,
            .raw => posix.SOCK.RAW,
            .rdm => posix.SOCK.RDM,
        },
        if (protocol) |p| @intFromEnum(p) else if (is_windows) switch (family) {
            posix.AF.UNIX => switch (mode) {
                .stream => 0,
                else => return error.ProtocolUnsupportedByAddressFamily,
            },
            posix.AF.INET, posix.AF.INET6 => @intFromEnum(@as(net.Protocol, switch (mode) {
                .stream => .tcp,
                .dgram => .udp,
                else => return error.ProtocolUnsupportedByAddressFamily,
            })),
            else => return error.ProtocolUnsupportedByAddressFamily,
        } else 0,
    };
}

pub fn recoverableOsBugDetected() void {
    if (is_debug) unreachable;
}

pub fn clockToPosix(clock: Io.Clock) posix.clockid_t {
    return switch (clock) {
        .real => posix.CLOCK.REALTIME,
        .awake => switch (native_os) {
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => posix.CLOCK.UPTIME_RAW,
            else => posix.CLOCK.MONOTONIC,
        },
        .boot => switch (native_os) {
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => posix.CLOCK.MONOTONIC_RAW,
            // On freebsd derivatives, use MONOTONIC_FAST as currently there's
            // no precision tradeoff.
            .freebsd, .dragonfly => posix.CLOCK.MONOTONIC_FAST,
            // On linux, use BOOTTIME instead of MONOTONIC as it ticks while
            // suspended.
            .linux => posix.CLOCK.BOOTTIME,
            // On other posix systems, MONOTONIC is generally the fastest and
            // ticks while suspended.
            else => posix.CLOCK.MONOTONIC,
        },
        .cpu_process => posix.CLOCK.PROCESS_CPUTIME_ID,
        .cpu_thread => posix.CLOCK.THREAD_CPUTIME_ID,
    };
}

fn clockToWasi(clock: Io.Clock) std.os.wasi.clockid_t {
    return switch (clock) {
        .real => .REALTIME,
        .awake => .MONOTONIC,
        .boot => .MONOTONIC,
        .cpu_process => .PROCESS_CPUTIME_ID,
        .cpu_thread => .THREAD_CPUTIME_ID,
    };
}

pub const linux_statx_request: std.os.linux.STATX = .{
    .TYPE = true,
    .MODE = true,
    .ATIME = true,
    .MTIME = true,
    .CTIME = true,
    .INO = true,
    .SIZE = true,
    .NLINK = true,
    .BLOCKS = true,
};

pub const linux_statx_check: std.os.linux.STATX = .{
    .TYPE = true,
    .MODE = true,
    .ATIME = false,
    .MTIME = true,
    .CTIME = true,
    .INO = true,
    .SIZE = true,
    .NLINK = true,
    .BLOCKS = false,
};

pub fn statFromLinux(stx: *const std.os.linux.Statx) Io.UnexpectedError!File.Stat {
    const actual_mask_int: u32 = @bitCast(stx.mask);
    const wanted_mask_int: u32 = @bitCast(linux_statx_check);
    if ((actual_mask_int | wanted_mask_int) != actual_mask_int) return error.Unexpected;

    return .{
        .inode = stx.ino,
        .nlink = stx.nlink,
        .size = stx.size,
        .permissions = .fromMode(stx.mode),
        .kind = statxKind(stx.mode),
        .atime = if (!stx.mask.ATIME) null else .{
            .nanoseconds = @intCast(@as(i128, stx.atime.sec) * std.time.ns_per_s + stx.atime.nsec),
        },
        .mtime = .{ .nanoseconds = @intCast(@as(i128, stx.mtime.sec) * std.time.ns_per_s + stx.mtime.nsec) },
        .ctime = .{ .nanoseconds = @intCast(@as(i128, stx.ctime.sec) * std.time.ns_per_s + stx.ctime.nsec) },
        .block_size = if (stx.mask.BLOCKS) stx.blksize else 1,
    };
}

pub fn statxKind(stx_mode: u16) File.Kind {
    return switch (stx_mode & std.os.linux.S.IFMT) {
        std.os.linux.S.IFDIR => .directory,
        std.os.linux.S.IFCHR => .character_device,
        std.os.linux.S.IFBLK => .block_device,
        std.os.linux.S.IFREG => .file,
        std.os.linux.S.IFIFO => .named_pipe,
        std.os.linux.S.IFLNK => .sym_link,
        std.os.linux.S.IFSOCK => .unix_domain_socket,
        else => .unknown,
    };
}

pub fn statFromPosix(st: *const posix.Stat) File.Stat {
    const atime = st.atime();
    const mtime = st.mtime();
    const ctime = st.ctime();
    return .{
        .inode = st.ino,
        .nlink = st.nlink,
        .size = @bitCast(st.size),
        .permissions = .fromMode(st.mode),
        .kind = k: {
            const m = st.mode & posix.S.IFMT;
            switch (m) {
                posix.S.IFBLK => break :k .block_device,
                posix.S.IFCHR => break :k .character_device,
                posix.S.IFDIR => break :k .directory,
                posix.S.IFIFO => break :k .named_pipe,
                posix.S.IFLNK => break :k .sym_link,
                posix.S.IFREG => break :k .file,
                posix.S.IFSOCK => break :k .unix_domain_socket,
                else => {},
            }
            if (native_os == .illumos) switch (m) {
                posix.S.IFDOOR => break :k .door,
                posix.S.IFPORT => break :k .event_port,
                else => {},
            };

            break :k .unknown;
        },
        .atime = timestampFromPosix(&atime),
        .mtime = timestampFromPosix(&mtime),
        .ctime = timestampFromPosix(&ctime),
        .block_size = @intCast(st.blksize),
    };
}

fn statFromWasi(st: *const std.os.wasi.filestat_t) File.Stat {
    return .{
        .inode = st.ino,
        .nlink = st.nlink,
        .size = @bitCast(st.size),
        .permissions = .default_file,
        .kind = switch (st.filetype) {
            .BLOCK_DEVICE => .block_device,
            .CHARACTER_DEVICE => .character_device,
            .DIRECTORY => .directory,
            .SYMBOLIC_LINK => .sym_link,
            .REGULAR_FILE => .file,
            .SOCKET_STREAM, .SOCKET_DGRAM => .unix_domain_socket,
            else => .unknown,
        },
        .atime = .fromNanoseconds(st.atim),
        .mtime = .fromNanoseconds(st.mtim),
        .ctime = .fromNanoseconds(st.ctim),
        .block_size = 1,
    };
}

pub fn timestampFromPosix(timespec: *const posix.timespec) Io.Timestamp {
    return .{ .nanoseconds = nanosecondsFromPosix(timespec) };
}

pub fn nanosecondsFromPosix(timespec: *const posix.timespec) i96 {
    return @intCast(@as(i128, timespec.sec) * std.time.ns_per_s + timespec.nsec);
}

fn timestampToPosix(nanoseconds: i96) posix.timespec {
    if (builtin.zig_backend == .stage2_wasm) {
        // Workaround for https://codeberg.org/ziglang/zig/issues/30575
        return .{
            .sec = @intCast(@divTrunc(nanoseconds, std.time.ns_per_s)),
            .nsec = @intCast(@rem(nanoseconds, std.time.ns_per_s)),
        };
    }
    return .{
        .sec = @intCast(@divFloor(nanoseconds, std.time.ns_per_s)),
        .nsec = @intCast(@mod(nanoseconds, std.time.ns_per_s)),
    };
}

pub fn setTimestampToPosix(set_ts: File.SetTimestamp) posix.timespec {
    return switch (set_ts) {
        .unchanged => posix.UTIME.OMIT,
        .now => posix.UTIME.NOW,
        .new => |t| timestampToPosix(t.nanoseconds),
    };
}

pub fn pathToPosix(file_path: []const u8, buffer: *[posix.PATH_MAX]u8) Dir.PathNameError![:0]u8 {
    if (std.mem.containsAtLeastScalar2(u8, file_path, 0, 1)) return error.BadPathName;
    // >= rather than > to make room for the null byte
    if (file_path.len >= buffer.len) return error.NameTooLong;
    @memcpy(buffer[0..file_path.len], file_path);
    buffer[file_path.len] = 0;
    return buffer[0..file_path.len :0];
}

fn lookupDnsSearch(
    t: *Threaded,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) (HostName.LookupError || Io.QueueClosedError)!void {
    const t_io = io(t);
    const rc = HostName.ResolvConf.init(t_io) catch return error.ResolvConfParseFailed;

    // Count dots, suppress search when >=ndots or name ends in
    // a dot, which is an explicit request for global scope.
    const dots = std.mem.countScalar(u8, host_name.bytes, '.');
    const search_len = if (dots >= rc.ndots or std.mem.endsWith(u8, host_name.bytes, ".")) 0 else rc.search_len;
    const search = rc.search_buffer[0..search_len];

    var canon_name = host_name.bytes;

    // Strip final dot for canon, fail if multiple trailing dots.
    if (std.mem.endsWith(u8, canon_name, ".")) canon_name.len -= 1;
    if (std.mem.endsWith(u8, canon_name, ".")) return error.UnknownHostName;

    // Name with search domain appended is set up in `canon_name`. This
    // both provides the desired default canonical name (if the requested
    // name is not a CNAME record) and serves as a buffer for passing the
    // full requested name to `lookupDns`.
    var local_buf: [HostName.max_len]u8 = undefined;
    const canon_buf = options.canonical_name_buffer orelse &local_buf;
    @memcpy(canon_buf[0..canon_name.len], canon_name);
    canon_buf[canon_name.len] = '.';
    var it = std.mem.tokenizeAny(u8, search, " \t");
    while (it.next()) |token| {
        @memcpy(canon_buf[canon_name.len + 1 ..][0..token.len], token);
        const lookup_canon_name = canon_buf[0 .. canon_name.len + 1 + token.len];
        if (t.lookupDns(lookup_canon_name, &rc, resolved, options)) |result| {
            return result;
        } else |err| switch (err) {
            error.UnknownHostName, error.NoAddressReturned => continue,
            else => |e| return e,
        }
    }

    const lookup_canon_name = canon_buf[0..canon_name.len];
    return t.lookupDns(lookup_canon_name, &rc, resolved, options);
}

fn lookupDns(
    t: *Threaded,
    lookup_canon_name: []const u8,
    rc: *const HostName.ResolvConf,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) (HostName.LookupError || Io.QueueClosedError)!void {
    const t_io = io(t);
    const family_records: [2]struct { af: IpAddress.Family, rr: HostName.DnsRecord } = .{
        .{ .af = .ip6, .rr = .A },
        .{ .af = .ip4, .rr = .AAAA },
    };
    var query_buffers: [2][280]u8 = undefined;
    var answer_buffer: [2 * 512]u8 = undefined;
    var queries_buffer: [2][]const u8 = undefined;
    var answers_buffer: [2][]const u8 = undefined;
    var nq: usize = 0;
    var answer_buffer_i: usize = 0;

    for (family_records) |fr| {
        if (options.family != fr.af) {
            var entropy: [2]u8 = undefined;
            random(t, &entropy);
            const len = writeResolutionQuery(&query_buffers[nq], 0, lookup_canon_name, 1, fr.rr, entropy);
            queries_buffer[nq] = query_buffers[nq][0..len];
            nq += 1;
        }
    }

    var ip4_mapped_buffer: [HostName.ResolvConf.max_nameservers]IpAddress = undefined;
    const ip4_mapped = ip4_mapped_buffer[0..rc.nameservers_len];
    var any_ip6 = false;
    for (rc.nameservers(), ip4_mapped) |*ns, *m| {
        m.* = .{ .ip6 = .fromAny(ns.*) };
        any_ip6 = any_ip6 or ns.* == .ip6;
    }
    var socket = s: {
        if (any_ip6) ip6: {
            const ip6_addr: IpAddress = .{ .ip6 = .unspecified(0) };
            const socket = ip6_addr.bind(t_io, .{ .ip6_only = true, .mode = .dgram }) catch |err| switch (err) {
                error.AddressFamilyUnsupported => break :ip6,
                else => |e| return e,
            };
            break :s socket;
        }
        any_ip6 = false;
        const ip4_addr: IpAddress = .{ .ip4 = .unspecified(0) };
        const socket = try ip4_addr.bind(t_io, .{ .mode = .dgram });
        break :s socket;
    };
    defer socket.close(t_io);

    const mapped_nameservers = if (any_ip6) ip4_mapped else rc.nameservers();
    const queries = queries_buffer[0..nq];
    const answers = answers_buffer[0..queries.len];
    var answers_remaining = answers.len;
    for (answers) |*answer| answer.len = 0;

    // boot clock is chosen because time the computer is suspended should count
    // against time spent waiting for external messages to arrive.
    const clock: Io.Clock = .boot;
    var now_ts = clock.now(t_io);
    const final_ts = now_ts.addDuration(.fromSeconds(rc.timeout_seconds));
    const attempt_duration: Io.Duration = .{
        .nanoseconds = (std.time.ns_per_s / rc.attempts) * @as(i96, rc.timeout_seconds),
    };

    send: while (now_ts.nanoseconds < final_ts.nanoseconds) : (now_ts = clock.now(t_io)) {
        const max_messages = queries_buffer.len * HostName.ResolvConf.max_nameservers;
        {
            var message_buffer: [max_messages]net.OutgoingMessage = undefined;
            var message_i: usize = 0;
            for (queries, answers) |query, *answer| {
                if (answer.len != 0) continue;
                for (mapped_nameservers) |*ns| {
                    message_buffer[message_i] = .{
                        .address = ns,
                        .data_ptr = query.ptr,
                        .data_len = query.len,
                    };
                    message_i += 1;
                }
            }
            _ = netSendPosix(t, socket.handle, message_buffer[0..message_i], .{});
        }

        const timeout: Io.Timeout = .{ .deadline = .{
            .raw = now_ts.addDuration(attempt_duration),
            .clock = clock,
        } };

        while (true) {
            var message_buffer: [max_messages]net.IncomingMessage = @splat(.init);
            const buf = answer_buffer[answer_buffer_i..];
            const recv_err, const recv_n = socket.receiveManyTimeout(t_io, &message_buffer, buf, .{}, timeout);
            for (message_buffer[0..recv_n]) |*received_message| {
                const reply = received_message.data;
                // Ignore non-identifiable packets.
                if (reply.len < 4) continue;

                // Ignore replies from addresses we didn't send to.
                const ns = for (mapped_nameservers) |*ns| {
                    if (received_message.from.eql(ns)) break ns;
                } else {
                    continue;
                };

                // Find which query this answer goes with, if any.
                const query, const answer = for (queries, answers) |query, *answer| {
                    if (reply[0] == query[0] and reply[1] == query[1]) break .{ query, answer };
                } else {
                    continue;
                };
                if (answer.len != 0) continue;

                // Only accept positive or negative responses; retry immediately on
                // server failure, and ignore all other codes such as refusal.
                switch (reply[3] & 15) {
                    0, 3 => {
                        answer.* = reply;
                        answer_buffer_i += reply.len;
                        answers_remaining -= 1;
                        if (answer_buffer.len - answer_buffer_i == 0) break :send;
                        if (answers_remaining == 0) break :send;
                    },
                    2 => {
                        var retry_message: net.OutgoingMessage = .{
                            .address = ns,
                            .data_ptr = query.ptr,
                            .data_len = query.len,
                        };
                        _ = netSendPosix(t, socket.handle, (&retry_message)[0..1], .{});
                        continue;
                    },
                    else => continue,
                }
            }
            if (recv_err) |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.Timeout => continue :send,
                else => continue,
            };
        }
    } else {
        return error.NameServerFailure;
    }

    var addresses_len: usize = 0;
    var canonical_name: ?HostName = null;

    for (answers) |answer| {
        var it = HostName.DnsResponse.init(answer) catch {
            // Here we could potentially add diagnostics to the results queue.
            continue;
        };
        while (it.next() catch {
            // Here we could potentially add diagnostics to the results queue.
            continue;
        }) |record| switch (record.rr) {
            .A => {
                const data = record.packet[record.data_off..][0..record.data_len];
                if (data.len != 4) return error.InvalidDnsARecord;
                try resolved.putOne(t_io, .{ .address = .{ .ip4 = .{
                    .bytes = data[0..4].*,
                    .port = options.port,
                } } });
                addresses_len += 1;
            },
            .AAAA => {
                const data = record.packet[record.data_off..][0..record.data_len];
                if (data.len != 16) return error.InvalidDnsAAAARecord;
                try resolved.putOne(t_io, .{ .address = .{ .ip6 = .{
                    .bytes = data[0..16].*,
                    .port = options.port,
                } } });
                addresses_len += 1;
            },
            .CNAME => {
                if (options.canonical_name_buffer) |buf| {
                    _, canonical_name = HostName.expand(
                        record.packet,
                        record.data_off,
                        buf,
                    ) catch return error.InvalidDnsCnameRecord;
                }
            },
            _ => continue,
        };
    }

    if (options.canonical_name_buffer != null) {
        try resolved.putOne(t_io, .{
            .canonical_name = canonical_name orelse .{ .bytes = lookup_canon_name },
        });
    }
    if (addresses_len == 0) return error.NoAddressReturned;
}

fn lookupHosts(
    t: *Threaded,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
) !void {
    const path_w = if (is_windows) path_w: {
        var path_w_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
        const system_dir = windows.getSystemDirectoryWtf16Le();
        const suffix = [_]u16{
            '\\', 'd', 'r', 'i', 'v', 'e', 'r', 's', '\\', 'e', 't', 'c', '\\', 'h', 'o', 's', 't', 's',
        };
        @memcpy(path_w_buf[0..system_dir.len], system_dir);
        @memcpy(path_w_buf[system_dir.len..][0..suffix.len], &suffix);
        path_w_buf[system_dir.len + suffix.len] = 0;
        break :path_w wToPrefixedFileW(null, &path_w_buf, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.AccessDenied,
            => return error.UnknownHostName,

            error.Canceled => |e| return e,

            else => {
                // Here we could add more detailed diagnostics to the results queue.
                return error.DetectingNetworkConfigurationFailed;
            },
        };
    };
    const file = (if (is_windows)
        dirOpenFileWtf16(null, path_w.span(), .{})
    else
        dirOpenFile(t, .cwd(), "/etc/hosts", .{})) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => return error.UnknownHostName,

        error.Canceled => |e| return e,

        else => {
            // Here we could add more detailed diagnostics to the results queue.
            return error.DetectingNetworkConfigurationFailed;
        },
    };
    defer fileClose(t, &.{file});

    var line_buf: [512]u8 = undefined;
    var file_reader = file.reader(t.io(), &line_buf);
    return t.lookupHostsReader(host_name, resolved, options, &file_reader.interface) catch |err| switch (err) {
        error.ReadFailed => switch (file_reader.err.?) {
            error.Canceled => |e| return e,
            else => {
                // Here we could add more detailed diagnostics to the results queue.
                return error.DetectingNetworkConfigurationFailed;
            },
        },
        error.Canceled,
        error.Closed,
        error.UnknownHostName,
        => |e| return e,
    };
}

fn lookupHostsReader(
    t: *Threaded,
    host_name: HostName,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
    reader: *Io.Reader,
) error{ ReadFailed, Canceled, UnknownHostName, Closed }!void {
    const t_io = io(t);
    var addresses_len: usize = 0;
    var canonical_name: ?HostName = null;
    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                // Skip lines that are too long.
                _ = reader.discardDelimiterInclusive('\n') catch |e| switch (e) {
                    error.EndOfStream => break,
                    error.ReadFailed => return error.ReadFailed,
                };
                continue;
            },
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => break,
        };
        reader.toss(@min(1, reader.bufferedLen()));
        var split_it = std.mem.splitScalar(u8, if (is_windows and std.mem.endsWith(u8, line, "\r"))
            line[0 .. line.len - 1]
        else
            line, '#');
        const no_comment_line = split_it.first();

        var line_it = std.mem.tokenizeAny(u8, no_comment_line, " \t");
        const ip_text = line_it.next() orelse continue;
        var first_name_text: ?[]const u8 = null;
        while (line_it.next()) |name_text| {
            if (std.ascii.eqlIgnoreCase(name_text, host_name.bytes)) {
                if (first_name_text == null) first_name_text = name_text;
                break;
            }
        } else continue;

        if (canonical_name == null) {
            if (options.canonical_name_buffer) |buf| {
                if (HostName.init(first_name_text.?)) |name_text| {
                    if (name_text.bytes.len <= buf.len) {
                        const canonical_name_dest = buf[0..name_text.bytes.len];
                        @memcpy(canonical_name_dest, name_text.bytes);
                        canonical_name = .{ .bytes = canonical_name_dest };
                    }
                } else |_| {}
            }
        }

        if (options.family != .ip6) {
            if (IpAddress.parseIp4(ip_text, options.port)) |addr| {
                try resolved.putOne(t_io, .{ .address = addr });
                addresses_len += 1;
            } else |_| {}
        }
        if (options.family != .ip4) {
            if (IpAddress.parseIp6(ip_text, options.port)) |addr| {
                try resolved.putOne(t_io, .{ .address = addr });
                addresses_len += 1;
            } else |_| {}
        }
    }

    if (canonical_name) |canon_name| try resolved.putOne(t_io, .{ .canonical_name = canon_name });
    if (addresses_len == 0) return error.UnknownHostName;
}

/// Writes DNS resolution query packet data to `w`; at most 280 bytes.
fn writeResolutionQuery(q: *[280]u8, op: u4, dname: []const u8, class: u8, ty: HostName.DnsRecord, entropy: [2]u8) usize {
    // This implementation is ported from musl libc.
    // A more idiomatic "ziggy" implementation would be welcome.
    var name = dname;
    if (std.mem.endsWith(u8, name, ".")) name.len -= 1;
    assert(name.len <= 253);
    const n = 17 + name.len + @intFromBool(name.len != 0);

    // Construct query template - ID will be filled later
    q[0..2].* = entropy;
    @memset(q[2..n], 0);
    q[2] = @as(u8, op) * 8 + 1;
    q[5] = 1;
    @memcpy(q[13..][0..name.len], name);
    var i: usize = 13;
    var j: usize = undefined;
    while (q[i] != 0) : (i = j + 1) {
        j = i;
        while (q[j] != 0 and q[j] != '.') : (j += 1) {}
        // TODO determine the circumstances for this and whether or
        // not this should be an error.
        if (j - i - 1 > 62) unreachable;
        q[i - 1] = @intCast(j - i);
    }
    q[i + 1] = @intFromEnum(ty);
    q[i + 3] = class;
    return n;
}

const LookupDnsWindows = struct {
    threaded: *Threaded,
    thread: Thread.Handle,
    resolved: *Io.Queue(HostName.LookupResult),
    options: HostName.LookupOptions,
    results: windows.DNS.QUERY.RESULT,
    done: bool,

    fn completed(
        pQueryContext: ?*anyopaque,
        pQueryResults: *windows.DNS.QUERY.RESULT,
    ) callconv(.winapi) void {
        _ = pQueryContext;
        const lookup_dns: *LookupDnsWindows = @fieldParentPtr("results", pQueryResults);
        lookup_dns.completedFallible() catch |err| switch (err) {
            error.Closed => unreachable, // `resolved` must not be closed until `netLookup` returns
            error.Canceled => unreachable, // called from an uncancelable thread
        };
        @atomicStore(bool, &lookup_dns.done, true, .release);
        _ = windows.ntdll.NtAlertThread(lookup_dns.thread);
    }
    fn completedFallible(lookup_dns: *LookupDnsWindows) (Io.QueueClosedError || Io.Cancelable)!void {
        assert(!lookup_dns.done);
        const t = lookup_dns.threaded;
        defer t.dl.DnsFree.raw.?(lookup_dns.results.pQueryRecords, .RecordList);
        if (lookup_dns.results.QueryStatus != .SUCCESS) return;
        const t_io = t.io();
        var record_it = lookup_dns.results.pQueryRecords;
        while (record_it) |record| : (record_it = record.pNext) switch (record.wType) {
            else => {},
            .A => try lookup_dns.resolved.putOne(t_io, .{
                .address = .{ .ip4 = .{ .bytes = record.Data.A, .port = lookup_dns.options.port } },
            }),
            .AAAA => {
                const ip6: net.Ip6Address = .{
                    .bytes = record.Data.AAAA,
                    .port = lookup_dns.options.port,
                };
                try lookup_dns.resolved.putOne(t_io, .{
                    .address = if (lookup_dns.options.family) |_| .{ .ip6 = ip6 } else .fromIp6(ip6),
                });
            },
        };
        if (lookup_dns.results.pQueryRecords) |record| {
            if (lookup_dns.options.canonical_name_buffer) |buf| {
                const name_wtf16 = std.mem.span(
                    @as([*:0]const windows.WCHAR, @ptrCast(@alignCast(record.pName))),
                );
                const len = std.unicode.wtf16LeToWtf8(buf, name_wtf16);
                try lookup_dns.resolved.putOne(t_io, .{
                    .canonical_name = .{ .bytes = buf[0..len] },
                });
            }
        }
    }
};

fn copyCanon(canonical_name_buffer: ?*[HostName.max_len]u8, name: []const u8) ?HostName {
    const buf = canonical_name_buffer orelse return null;
    const dest = buf[0..name.len];
    @memcpy(dest, name);
    return .{ .bytes = dest };
}

/// Darwin XNU 7195.50.7.100.1 introduced __ulock_wait2 and migrated code paths (notably pthread_cond_t) towards it:
/// https://github.com/apple/darwin-xnu/commit/d4061fb0260b3ed486147341b72468f836ed6c8f#diff-08f993cc40af475663274687b7c326cc6c3031e0db3ac8de7b24624610616be6
///
/// This XNU version appears to correspond to 11.0.1:
/// https://kernelshaman.blogspot.com/2021/01/building-xnu-for-macos-big-sur-1101.html
///
/// ulock_wait() uses 32-bit micro-second timeouts where 0 = INFINITE or no-timeout
/// ulock_wait2() uses 64-bit nano-second timeouts (with the same convention)
const darwin_supports_ulock_wait2 = builtin.os.version_range.semver.min.major >= 11;

fn doNothingSignalHandler(_: posix.SIG) callconv(.c) void {}

const WindowsEnvironStrings = struct {
    PATH: ?[:0]const u16 = null,
    PATHEXT: ?[:0]const u16 = null,

    fn scan() WindowsEnvironStrings {
        const peb = windows.peb();
        assert(windows.ntdll.RtlEnterCriticalSection(peb.FastPebLock) == .SUCCESS);
        defer assert(windows.ntdll.RtlLeaveCriticalSection(peb.FastPebLock) == .SUCCESS);
        const ptr = peb.ProcessParameters.Environment;

        var result: WindowsEnvironStrings = .{};
        var i: usize = 0;
        while (ptr[i] != 0) {
            const key_start = i;

            // There are some special environment variables that start with =,
            // so we need a special case to not treat = as a key/value separator
            // if it's the first character.
            // https://devblogs.microsoft.com/oldnewthing/20100506-00/?p=14133
            if (ptr[key_start] == '=') i += 1;

            while (ptr[i] != 0 and ptr[i] != '=') : (i += 1) {}
            const key_w = ptr[key_start..i];

            if (ptr[i] == '=') i += 1;

            const value_start = i;
            while (ptr[i] != 0) : (i += 1) {}
            const value_w = ptr[value_start..i :0];

            i += 1; // skip over null byte

            inline for (@typeInfo(WindowsEnvironStrings).@"struct".fields) |field| {
                const field_name_w = comptime std.unicode.wtf8ToWtf16LeStringLiteral(field.name);
                if (windows.eqlIgnoreCaseWtf16(key_w, field_name_w)) @field(result, field.name) = value_w;
            }
        }

        return result;
    }
};

fn scanEnviron(t: *Threaded) void {
    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);
    if (t.environ_initialized) return;
    t.environ.scan(t.allocator);
    t.environ_initialized = true;
}

fn processReplace(userdata: ?*anyopaque, options: process.ReplaceOptions) process.ReplaceError {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    if (!process.can_replace) return error.OperationUnsupported;

    t.scanEnviron(); // for PATH
    const PATH = t.environ.string.PATH orelse default_PATH;

    var arena_allocator = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const argv_buf = try arena.allocSentinel(?[*:0]const u8, options.argv.len, null);
    for (options.argv, 0..) |arg, i| argv_buf[i] = (try arena.dupeZ(u8, arg)).ptr;

    const env_block = env_block: {
        const prog_fd: i32 = -1;
        if (options.environ_map) |environ_map| break :env_block try environ_map.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
        break :env_block try t.environ.process_environ.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
    };

    return posixExecv(options.expand_arg0, argv_buf.ptr[0].?, argv_buf.ptr, env_block, PATH);
}

fn processReplacePath(userdata: ?*anyopaque, dir: Dir, options: process.ReplaceOptions) process.ReplaceError {
    if (!process.can_replace) return error.OperationUnsupported;
    _ = userdata;
    _ = dir;
    _ = options;
    @panic("TODO processReplacePath");
}

fn processSpawnPath(userdata: ?*anyopaque, dir: Dir, options: process.SpawnOptions) process.SpawnError!process.Child {
    if (!process.can_spawn) return error.OperationUnsupported;
    _ = userdata;
    _ = dir;
    _ = options;
    @panic("TODO processSpawnPath");
}

const processSpawn = switch (native_os) {
    .wasi, .emscripten, .ios, .tvos, .visionos, .watchos => processSpawnUnsupported,
    .windows => processSpawnWindows,
    else => processSpawnPosix,
};

fn processSpawnUnsupported(userdata: ?*anyopaque, options: process.SpawnOptions) process.SpawnError!process.Child {
    _ = userdata;
    _ = options;
    return error.OperationUnsupported;
}

const Spawned = struct {
    pid: posix.pid_t,
    err_fd: posix.fd_t,
    stdin: ?File,
    stdout: ?File,
    stderr: ?File,
};

fn spawnPosix(t: *Threaded, options: process.SpawnOptions) process.SpawnError!Spawned {
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
    const pipe_flags: posix.O = .{ .CLOEXEC = true };

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

    const any_ignore = (options.stdin == .ignore or options.stdout == .ignore or options.stderr == .ignore);
    const dev_null_fd = if (any_ignore) try getDevNullFd(t) else undefined;

    const prog_pipe: [2]posix.fd_t = if (options.progress_node.index != .none) pipe: {
        // We use CLOEXEC for the same reason as in `pipe_flags`.
        const pipe = try pipe2(.{ .NONBLOCK = true, .CLOEXEC = true });
        switch (native_os) {
            .linux => _ = posix.system.fcntl(pipe[0], posix.F.SETPIPE_SZ, @as(u32, std.Progress.max_packet_len * 2)),
            else => {},
        }
        break :pipe pipe;
    } else .{ -1, -1 };
    errdefer destroyPipe(prog_pipe);

    var arena_allocator = std.heap.ArenaAllocator.init(t.allocator);
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

    const prog_fileno = 3;
    comptime assert(@max(posix.STDIN_FILENO, posix.STDOUT_FILENO, posix.STDERR_FILENO) + 1 == prog_fileno);

    const env_block = env_block: {
        const prog_fd: i32 = if (prog_pipe[1] == -1) -1 else prog_fileno;
        if (options.environ_map) |environ_map| break :env_block try environ_map.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
        break :env_block try t.environ.process_environ.createPosixBlock(arena, .{
            .zig_progress_fd = prog_fd,
        });
    };

    // This pipe communicates to the parent errors in the child between `fork` and `execvpe`.
    // It is closed by the child (via CLOEXEC) without writing if `execvpe` succeeds.
    const err_pipe = try pipe2(.{ .CLOEXEC = true });
    errdefer destroyPipe(err_pipe);

    t.scanEnviron(); // for PATH
    const PATH = t.environ.string.PATH orelse default_PATH;

    const pid_result: posix.pid_t = fork: {
        const rc = posix.system.fork();
        switch (posix.errno(rc)) {
            .SUCCESS => break :fork @intCast(rc),
            .AGAIN => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOSYS => return error.OperationUnsupported,
            else => |err| return posix.unexpectedErrno(err),
        }
    };

    if (pid_result == 0) {
        defer comptime unreachable; // We are the child.
        if (Thread.current) |current_thread| current_thread.cancel_protection = .blocked;
        const ep1 = err_pipe[1];

        setUpChildIo(options.stdin, stdin_pipe[0], posix.STDIN_FILENO, dev_null_fd) catch |err| forkBail(ep1, err);
        setUpChildIo(options.stdout, stdout_pipe[1], posix.STDOUT_FILENO, dev_null_fd) catch |err| forkBail(ep1, err);
        setUpChildIo(options.stderr, stderr_pipe[1], posix.STDERR_FILENO, dev_null_fd) catch |err| forkBail(ep1, err);

        switch (options.cwd) {
            .inherit => {},
            .dir => |cwd| {
                fchdir(cwd.handle) catch |err| forkBail(ep1, err);
            },
            .path => |cwd| {
                chdir(cwd) catch |err| forkBail(ep1, err);
            },
        }

        // Must happen after fchdir above, the cwd file descriptor might be
        // equal to prog_fileno and be clobbered by this dup2 call.
        if (prog_pipe[1] != -1) dup2(prog_pipe[1], prog_fileno) catch |err| forkBail(ep1, err);

        if (options.gid) |gid| {
            switch (posix.errno(posix.system.setregid(gid, gid))) {
                .SUCCESS => {},
                .AGAIN => forkBail(ep1, error.ResourceLimitReached),
                .INVAL => forkBail(ep1, error.InvalidUserId),
                .PERM => forkBail(ep1, error.PermissionDenied),
                else => forkBail(ep1, error.Unexpected),
            }
        }

        if (options.uid) |uid| {
            switch (posix.errno(posix.system.setreuid(uid, uid))) {
                .SUCCESS => {},
                .AGAIN => forkBail(ep1, error.ResourceLimitReached),
                .INVAL => forkBail(ep1, error.InvalidUserId),
                .PERM => forkBail(ep1, error.PermissionDenied),
                else => forkBail(ep1, error.Unexpected),
            }
        }

        if (options.pgid) |pid| {
            switch (posix.errno(posix.system.setpgid(0, pid))) {
                .SUCCESS => {},
                .ACCES => forkBail(ep1, error.ProcessAlreadyExec),
                .INVAL => forkBail(ep1, error.InvalidProcessGroupId),
                .PERM => forkBail(ep1, error.PermissionDenied),
                else => forkBail(ep1, error.Unexpected),
            }
        }

        if (options.start_suspended) {
            switch (posix.errno(posix.system.kill(0, .STOP))) {
                .SUCCESS => {},
                .PERM => forkBail(ep1, error.PermissionDenied),
                else => forkBail(ep1, error.Unexpected),
            }
        }

        const err = posixExecv(options.expand_arg0, argv_buf.ptr[0].?, argv_buf.ptr, env_block, PATH);
        forkBail(ep1, err);
    }

    const pid: posix.pid_t = @intCast(pid_result); // We are the parent.
    errdefer comptime unreachable; // The child is forked; we must not error from now on

    closeFd(err_pipe[1]); // make sure only the child holds the write end open

    if (options.stdin == .pipe) closeFd(stdin_pipe[0]);
    if (options.stdout == .pipe) closeFd(stdout_pipe[1]);
    if (options.stderr == .pipe) closeFd(stderr_pipe[1]);

    if (prog_pipe[1] != -1) closeFd(prog_pipe[1]);
    options.progress_node.setIpcFile(t, .{ .handle = prog_pipe[0], .flags = .{ .nonblocking = true } });

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

fn getDevNullFd(t: *Threaded) !posix.fd_t {
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);
        if (t.null_file.fd != -1) return t.null_file.fd;
    }
    const mode: u32 = 0;
    const syscall: Syscall = try .start();
    while (true) {
        const rc = open_sym("/dev/null", .{ .ACCMODE = .RDWR }, mode);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                syscall.finish();
                const fresh_fd: posix.fd_t = @intCast(rc);
                mutexLock(&t.mutex); // Another thread might have won the race.
                defer mutexUnlock(&t.mutex);
                if (t.null_file.fd != -1) {
                    closeFd(fresh_fd);
                    return t.null_file.fd;
                } else {
                    t.null_file.fd = fresh_fd;
                    return fresh_fd;
                }
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .ACCES => return syscall.fail(error.AccessDenied),
            .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
            .NFILE => return syscall.fail(error.SystemFdQuotaExceeded),
            .NODEV => return syscall.fail(error.NoDevice),
            .NOENT => return syscall.fail(error.FileNotFound),
            .NOMEM => return syscall.fail(error.SystemResources),
            .PERM => return syscall.fail(error.PermissionDenied),
            else => |err| return syscall.unexpectedErrno(err),
        }
    }
}

fn processSpawnPosix(userdata: ?*anyopaque, options: process.SpawnOptions) process.SpawnError!process.Child {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const spawned = try spawnPosix(t, options);
    defer closeFd(spawned.err_fd);

    // Wait for the child to report any errors in or before `execvpe`.
    if (readIntFd(spawned.err_fd)) |child_err_int| {
        const child_err: process.SpawnError = @errorCast(@errorFromInt(child_err_int));
        return child_err;
    } else |read_err| switch (read_err) {
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
}

fn childWait(userdata: ?*anyopaque, child: *process.Child) process.Child.WaitError!process.Child.Term {
    if (native_os == .wasi) unreachable;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    switch (native_os) {
        .windows => return childWaitWindows(child),
        else => return childWaitPosix(child),
    }
}

fn childKill(userdata: ?*anyopaque, child: *process.Child) void {
    if (native_os == .wasi) unreachable;
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    if (is_windows) {
        childKillWindows(t, child, 1) catch childCleanupWindows(child);
    } else {
        childKillPosix(child) catch {};
        childCleanupPosix(child);
    }
}

fn childKillWindows(t: *Threaded, child: *process.Child, exit_code: windows.UINT) !void {
    _ = t; // TODO cancelation
    const handle = child.id.?;
    _ = windows.ntdll.RtlReportSilentProcessExit(handle, @enumFromInt(exit_code));
    switch (windows.ntdll.NtTerminateProcess(handle, @enumFromInt(exit_code))) {
        .SUCCESS, .PROCESS_IS_TERMINATING => {
            const infinite_timeout: windows.LARGE_INTEGER = std.math.minInt(windows.LARGE_INTEGER);
            _ = windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &infinite_timeout);
            childCleanupWindows(child);
        },
        .ACCESS_DENIED => {
            // Usually when TerminateProcess triggers a ACCESS_DENIED error, it
            // indicates that the process has already exited, but there may be
            // some rare edge cases where our process handle no longer has the
            // PROCESS_TERMINATE access right, so let's do another check to make
            // sure the process is really no longer running:
            const minimal_timeout: windows.LARGE_INTEGER = -1;
            return switch (windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &minimal_timeout)) {
                windows.NTSTATUS.WAIT_0 => error.AlreadyTerminated,
                else => error.AccessDenied,
            };
        },
        else => |status| return windows.unexpectedStatus(status),
    }
}

fn childWaitWindows(child: *process.Child) process.Child.WaitError!process.Child.Term {
    const handle = child.id.?;

    const alertable_syscall: AlertableSyscall = try .start();
    const infinite_timeout: windows.LARGE_INTEGER = std.math.minInt(windows.LARGE_INTEGER);
    while (true) switch (windows.ntdll.NtWaitForSingleObject(handle, .TRUE, &infinite_timeout)) {
        windows.NTSTATUS.WAIT_0 => break alertable_syscall.finish(),
        .USER_APC, .ALERTED, .TIMEOUT => {
            try alertable_syscall.checkCancel();
            continue;
        },
        else => |status| return alertable_syscall.unexpectedNtstatus(status),
    };

    var info: windows.PROCESS.BASIC_INFORMATION = undefined;
    const term: process.Child.Term = switch (windows.ntdll.NtQueryInformationProcess(
        handle,
        .BasicInformation,
        &info,
        @sizeOf(windows.PROCESS.BASIC_INFORMATION),
        null,
    )) {
        .SUCCESS => .{ .exited = @as(u8, @truncate(@intFromEnum(info.ExitStatus))) },
        else => .{ .unknown = 0 },
    };

    childCleanupWindows(child);
    return term;
}

fn childCleanupWindows(child: *process.Child) void {
    const handle = child.id orelse return;

    if (child.request_resource_usage_statistics) {
        var vmc: windows.PROCESS.VM_COUNTERS = undefined;
        switch (windows.ntdll.NtQueryInformationProcess(
            handle,
            .VmCounters,
            &vmc,
            @sizeOf(windows.PROCESS.VM_COUNTERS),
            null,
        )) {
            .SUCCESS => child.resource_usage_statistics.rusage = vmc,
            else => child.resource_usage_statistics.rusage = null,
        }
    }

    windows.CloseHandle(handle);
    child.id = null;

    windows.CloseHandle(child.thread_handle);
    child.thread_handle = undefined;

    if (child.stdin) |stdin| {
        windows.CloseHandle(stdin.handle);
        child.stdin = null;
    }
    if (child.stdout) |stdout| {
        windows.CloseHandle(stdout.handle);
        child.stdout = null;
    }
    if (child.stderr) |stderr| {
        windows.CloseHandle(stderr.handle);
        child.stderr = null;
    }
}

fn childWaitPosix(child: *process.Child) process.Child.WaitError!process.Child.Term {
    defer childCleanupPosix(child);

    const pid = child.id.?;

    var ru: posix.rusage = undefined;
    const ru_ptr = if (child.request_resource_usage_statistics) &ru else null;

    if (have_wait4) {
        var status: if (builtin.link_libc) c_int else u32 = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (posix.errno(posix.system.wait4(pid, &status, 0, ru_ptr))) {
            .SUCCESS => {
                syscall.finish();
                if (ru_ptr) |p| child.resource_usage_statistics.rusage = p.*;
                return statusToTerm(@bitCast(status));
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .CHILD => |err| return syscall.errnoBug(err), // Double-free.
            else => |err| return syscall.unexpectedErrno(err),
        };
    }

    if (have_waitid) {
        const linux = std.os.linux; // Bypass libc which has the wrong signature.
        var info: linux.siginfo_t = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED, ru_ptr))) {
            .SUCCESS => {
                syscall.finish();
                if (ru_ptr) |p| child.resource_usage_statistics.rusage = p.*;
                const status: u32 = @bitCast(info.fields.common.second.sigchld.status);
                const code: linux.CLD = @enumFromInt(info.code);
                return switch (code) {
                    .EXITED => .{ .exited = @truncate(status) },
                    .KILLED, .DUMPED => .{ .signal = @enumFromInt(status) },
                    .TRAPPED, .STOPPED => .{ .stopped = @enumFromInt(status) },
                    _, .CONTINUED => .{ .unknown = status },
                };
            },
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            .CHILD => |err| return syscall.errnoBug(err), // Double-free.
            else => |err| return syscall.unexpectedErrno(err),
        };
    }

    var status: if (builtin.link_libc) c_int else u32 = undefined;
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.waitpid(pid, &status, 0))) {
        .SUCCESS => {
            syscall.finish();
            return statusToTerm(@bitCast(status));
        },
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .CHILD => |err| return syscall.errnoBug(err), // Double-free.
        else => |err| return syscall.unexpectedErrno(err),
    };
}

pub fn statusToTerm(status: u32) process.Child.Term {
    return if (posix.W.IFEXITED(status))
        .{ .exited = posix.W.EXITSTATUS(status) }
    else if (posix.W.IFSIGNALED(status))
        .{ .signal = posix.W.TERMSIG(status) }
    else if (posix.W.IFSTOPPED(status))
        .{ .stopped = posix.W.STOPSIG(status) }
    else
        .{ .unknown = status };
}

fn childKillPosix(child: *process.Child) !void {
    // Entire function body is intentionally uncancelable.

    const pid = child.id.?;

    while (true) switch (posix.errno(posix.system.kill(pid, .TERM))) {
        .SUCCESS => break,
        .INTR => continue,
        .PERM => return error.PermissionDenied,
        .INVAL => |err| return errnoBug(err),
        .SRCH => |err| return errnoBug(err),
        else => |err| return posix.unexpectedErrno(err),
    };

    if (have_wait4) {
        var status: if (builtin.link_libc) c_int else u32 = undefined;
        while (true) switch (posix.errno(posix.system.wait4(pid, &status, 0, null))) {
            .SUCCESS => return,
            .INTR => continue,
            .CHILD => |err| return errnoBug(err), // Double-free.
            else => |err| return posix.unexpectedErrno(err),
        };
    }

    if (have_waitid) {
        const linux = std.os.linux; // Bypass libc which has the wrong signature.
        var info: linux.siginfo_t = undefined;
        while (true) switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED, null))) {
            .SUCCESS => return,
            .INTR => continue,
            .CHILD => |err| return errnoBug(err), // Double-free.
            else => |err| return posix.unexpectedErrno(err),
        };
    }

    var status: if (builtin.link_libc) c_int else u32 = undefined;
    while (true) switch (posix.errno(posix.system.waitpid(pid, &status, 0))) {
        .SUCCESS => return,
        .INTR => continue,
        .CHILD => |err| return errnoBug(err), // Double-free.
        else => |err| return posix.unexpectedErrno(err),
    };
}

fn childCleanupPosix(child: *process.Child) void {
    if (child.stdin) |stdin| {
        closeFd(stdin.handle);
        child.stdin = null;
    }
    if (child.stdout) |stdout| {
        closeFd(stdout.handle);
        child.stdout = null;
    }
    if (child.stderr) |stderr| {
        closeFd(stderr.handle);
        child.stderr = null;
    }
    child.id = null;
}

/// Errors that can occur between fork() and execv()
const ForkBailError = process.SpawnError || process.ReplaceError;

/// Child of fork calls this to report an error to the fork parent. Then the
/// child exits.
fn forkBail(fd: posix.fd_t, err: ForkBailError) noreturn {
    writeIntFd(fd, @as(ErrInt, @intFromError(err))) catch {};
    // If we're linking libc, some naughty applications may have registered atexit handlers
    // which we really do not want to run in the fork child. I caught LLVM doing this and
    // it caused a deadlock instead of doing an exit syscall. In the words of Avril Lavigne,
    // "Why'd you have to go and make things so complicated?"
    if (builtin.link_libc) {
        // The `_exit` function does nothing but make the exit syscall, unlike `exit`.
        std.c._exit(1);
    } else if (native_os == .linux and !builtin.single_threaded) {
        std.os.linux.exit_group(1);
    } else {
        posix.system.exit(1);
    }
}

fn writeIntFd(fd: posix.fd_t, value: ErrInt) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    // Skip the cancel mechanism.
    var i: usize = 0;
    while (true) {
        const rc = posix.system.write(fd, buffer[i..].ptr, buffer.len - i);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                const n: usize = @intCast(rc);
                i += n;
                if (buffer.len - i == 0) return;
            },
            .INTR => continue,
            else => return error.SystemResources,
        }
    }
}

fn readIntFd(fd: posix.fd_t) !ErrInt {
    var buffer: [8]u8 = undefined;
    var i: usize = 0;
    while (true) {
        const rc = posix.system.read(fd, buffer[i..].ptr, buffer.len - i);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                const n: usize = @intCast(rc);
                if (n == 0) break;
                i += n;
                continue;
            },
            .INTR => continue,
            else => |err| return posix.unexpectedErrno(err),
        }
    }
    if (buffer.len - i != 0) return error.EndOfStream;
    return @intCast(std.mem.readInt(u64, &buffer, .little));
}

const ErrInt = std.meta.Int(.unsigned, @sizeOf(anyerror) * 8);

fn destroyPipe(pipe: [2]posix.fd_t) void {
    if (pipe[0] != -1) closeFd(pipe[0]);
    if (pipe[0] != pipe[1]) closeFd(pipe[1]);
}

fn setUpChildIo(stdio: process.SpawnOptions.StdIo, pipe_fd: i32, std_fileno: i32, dev_null_fd: i32) !void {
    switch (stdio) {
        .pipe => try dup2(pipe_fd, std_fileno),
        .close => closeFd(std_fileno),
        .inherit => {},
        .ignore => try dup2(dev_null_fd, std_fileno),
        .file => |file| try dup2(file.handle, std_fileno),
    }
}

fn processSpawnWindows(userdata: ?*anyopaque, options: process.SpawnOptions) process.SpawnError!process.Child {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    const any_ignore =
        options.stdin == .ignore or
        options.stdout == .ignore or
        options.stderr == .ignore;
    const nul_handle = if (any_ignore) try getNulDevice(t) else undefined;

    const any_inherit =
        options.stdin == .inherit or
        options.stdout == .inherit or
        options.stderr == .inherit;
    const peb = if (any_inherit) windows.peb() else undefined;

    const stdin_pipe = if (options.stdin == .pipe) try t.windowsCreatePipe(.{
        .server = .{ .attributes = .{ .INHERIT = false }, .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
        .client = .{ .attributes = .{ .INHERIT = true }, .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
        .outbound = true,
    }) else undefined;
    errdefer if (options.stdin == .pipe) for (stdin_pipe) |handle| windows.CloseHandle(handle);

    const stdout_pipe = if (options.stdout == .pipe) try t.windowsCreatePipe(.{
        .server = .{ .attributes = .{ .INHERIT = false }, .mode = .{ .IO = .ASYNCHRONOUS } },
        .client = .{ .attributes = .{ .INHERIT = true }, .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
        .inbound = true,
    }) else undefined;
    errdefer if (options.stdout == .pipe) for (stdout_pipe) |handle| windows.CloseHandle(handle);

    const stderr_pipe = if (options.stderr == .pipe) try t.windowsCreatePipe(.{
        .server = .{ .attributes = .{ .INHERIT = false }, .mode = .{ .IO = .ASYNCHRONOUS } },
        .client = .{ .attributes = .{ .INHERIT = true }, .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
        .inbound = true,
    }) else undefined;
    errdefer if (options.stderr == .pipe) for (stderr_pipe) |handle| windows.CloseHandle(handle);

    const prog_pipe = if (options.progress_node.index != .none) try t.windowsCreatePipe(.{
        .server = .{ .attributes = .{ .INHERIT = false }, .mode = .{ .IO = .ASYNCHRONOUS } },
        .client = .{ .attributes = .{ .INHERIT = true }, .mode = .{ .IO = .ASYNCHRONOUS } },
        .inbound = true,
        .quota = std.Progress.max_packet_len * 2,
    }) else undefined;
    errdefer if (options.progress_node.index != .none) for (prog_pipe) |handle| windows.CloseHandle(handle);

    var siStartInfo: windows.STARTUPINFOW = .{
        .cb = @sizeOf(windows.STARTUPINFOW),
        .dwFlags = windows.STARTF_USESTDHANDLES,
        .hStdInput = switch (options.stdin) {
            .inherit => peb.ProcessParameters.hStdInput,
            .file => |file| try OpenFile(&.{}, .{
                .access_mask = .{
                    .STANDARD = .{ .SYNCHRONIZE = true },
                    .GENERIC = .{ .READ = true },
                },
                .dir = file.handle,
                .sa = &.{
                    .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
                    .lpSecurityDescriptor = null,
                    .bInheritHandle = .TRUE,
                },
                .creation = .OPEN,
            }),
            .ignore => nul_handle,
            .pipe => stdin_pipe[1],
            .close => null,
        },
        .hStdOutput = switch (options.stdout) {
            .inherit => peb.ProcessParameters.hStdOutput,
            .file => |file| try OpenFile(&.{}, .{
                .access_mask = .{
                    .STANDARD = .{ .SYNCHRONIZE = true },
                    .GENERIC = .{ .WRITE = true },
                },
                .dir = file.handle,
                .sa = &.{
                    .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
                    .lpSecurityDescriptor = null,
                    .bInheritHandle = .TRUE,
                },
                .creation = .OPEN,
            }),
            .ignore => nul_handle,
            .pipe => stdout_pipe[1],
            .close => null,
        },
        .hStdError = switch (options.stderr) {
            .inherit => peb.ProcessParameters.hStdError,
            .file => |file| try OpenFile(&.{}, .{
                .access_mask = .{
                    .STANDARD = .{ .SYNCHRONIZE = true },
                    .GENERIC = .{ .WRITE = true },
                },
                .dir = file.handle,
                .sa = &.{
                    .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
                    .lpSecurityDescriptor = null,
                    .bInheritHandle = .TRUE,
                },
                .creation = .OPEN,
            }),
            .ignore => nul_handle,
            .pipe => stderr_pipe[1],
            .close => null,
        },

        .lpReserved = null,
        .lpDesktop = null,
        .lpTitle = null,
        .dwX = 0,
        .dwY = 0,
        .dwXSize = 0,
        .dwYSize = 0,
        .dwXCountChars = 0,
        .dwYCountChars = 0,
        .dwFillAttribute = 0,
        .wShowWindow = 0,
        .cbReserved2 = 0,
        .lpReserved2 = null,
    };
    var piProcInfo: windows.PROCESS.INFORMATION = undefined;

    var arena_allocator = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const cwd_w = cwd_w: {
        switch (options.cwd) {
            .inherit => break :cwd_w null,
            .dir => |cwd_dir| {
                var dir_path_buffer = try arena.alloc(u16, windows.PATH_MAX_WIDE + 1);
                const dir_path = try GetFinalPathNameByHandle(
                    cwd_dir.handle,
                    .{},
                    dir_path_buffer[0..windows.PATH_MAX_WIDE],
                );
                dir_path_buffer[dir_path.len] = 0;
                // Shrink the allocation down to just the path buffer + sentinel
                dir_path_buffer = try arena.realloc(dir_path_buffer, dir_path.len + 1);
                break :cwd_w dir_path_buffer[0..dir_path.len :0];
            },
            .path => |cwd| {
                break :cwd_w try std.unicode.wtf8ToWtf16LeAllocZ(arena, cwd);
            },
        }
    };
    const cwd_w_ptr = if (cwd_w) |cwd| cwd.ptr else null;

    const env_block = env_block: {
        const prog_handle = if (options.progress_node.index != .none)
            prog_pipe[1]
        else
            windows.INVALID_HANDLE_VALUE;
        if (options.environ_map) |environ_map| break :env_block try environ_map.createWindowsBlock(arena, .{
            .zig_progress_handle = prog_handle,
        });
        break :env_block try t.environ.process_environ.createWindowsBlock(arena, .{
            .zig_progress_handle = if (options.progress_node.index != .none) prog_pipe[1] else windows.INVALID_HANDLE_VALUE,
        });
    };

    const app_name_wtf8 = options.argv[0];
    const app_name_is_absolute = Dir.path.isAbsolute(app_name_wtf8);

    // The cwd provided by options is in effect when choosing the executable
    // path to match POSIX semantics.
    const cwd_path_w = x: {
        // If the app name is absolute, then we need to use its dirname as the cwd
        if (app_name_is_absolute) {
            const dir = Dir.path.dirname(app_name_wtf8).?;
            break :x try std.unicode.wtf8ToWtf16LeAllocZ(arena, dir);
        } else if (cwd_w) |cwd| {
            break :x cwd;
        } else {
            break :x &[_:0]u16{}; // empty for cwd
        }
    };

    // If the app name has more than just a filename, then we need to separate
    // that into the basename and dirname and use the dirname as an addition to
    // the cwd path. This is because NtQueryDirectoryFile cannot accept
    // FileName params with path separators.
    const app_basename_wtf8 = Dir.path.basename(app_name_wtf8);
    // If the app name is absolute, then the cwd will already have the app's dirname in it,
    // so only populate app_dirname if app name is a relative path with > 0 path separators.
    const maybe_app_dirname_wtf8 = if (!app_name_is_absolute) Dir.path.dirname(app_name_wtf8) else null;
    const app_dirname_w: ?[:0]u16 = x: {
        if (maybe_app_dirname_wtf8) |app_dirname_wtf8| {
            break :x try std.unicode.wtf8ToWtf16LeAllocZ(arena, app_dirname_wtf8);
        }
        break :x null;
    };
    const app_name_w = try std.unicode.wtf8ToWtf16LeAllocZ(arena, app_basename_wtf8);

    const flags: windows.CreateProcessFlags = .{
        .create_suspended = options.start_suspended,
        .create_unicode_environment = true,
        .create_no_window = options.create_no_window,
    };

    run: {
        // We have to scan each time because the PEB environment pointer is not stable.
        const env_strings: WindowsEnvironStrings = .scan();
        const PATH = env_strings.PATH orelse &[_:0]u16{};
        const PATHEXT = env_strings.PATHEXT orelse &[_:0]u16{};

        // In case the command ends up being a .bat/.cmd script, we need to escape things using the cmd.exe rules
        // and invoke cmd.exe ourselves in order to mitigate arbitrary command execution from maliciously
        // constructed arguments.
        //
        // We'll need to wait until we're actually trying to run the command to know for sure
        // if the resolved command has the `.bat` or `.cmd` extension, so we defer actually
        // serializing the command line until we determine how it should be serialized.
        var cmd_line_cache = WindowsCommandLineCache.init(arena, options.argv);

        var app_buf: std.ArrayList(u16) = .empty;
        try app_buf.appendSlice(arena, app_name_w);

        var dir_buf: std.ArrayList(u16) = .empty;

        if (cwd_path_w.len > 0) {
            try dir_buf.appendSlice(arena, cwd_path_w);
        }
        if (app_dirname_w) |app_dir| {
            if (dir_buf.items.len > 0) try dir_buf.append(arena, Dir.path.sep);
            try dir_buf.appendSlice(arena, app_dir);
        }

        windowsCreateProcessPathExt(
            arena,
            &dir_buf,
            &app_buf,
            PATHEXT,
            &cmd_line_cache,
            env_block,
            cwd_w_ptr,
            flags,
            &siStartInfo,
            &piProcInfo,
        ) catch |no_path_err| {
            const original_err = switch (no_path_err) {
                // argv[0] contains unsupported characters that will never resolve to a valid exe.
                error.InvalidArg0 => return error.FileNotFound,
                error.FileNotFound, error.InvalidExe, error.AccessDenied => |e| e,
                error.UnrecoverableInvalidExe => return error.InvalidExe,
                else => |e| return e,
            };

            // If the app name had path separators, that disallows PATH searching,
            // and there's no need to search the PATH if the app name is absolute.
            // We still search the path if the cwd is absolute because of the
            // "cwd provided by options is in effect when choosing the executable path
            // to match posix semantics" behavior--we don't want to skip searching
            // the PATH just because we were trying to set the cwd of the child process.
            if (app_dirname_w != null or app_name_is_absolute) {
                return original_err;
            }

            var it = std.mem.tokenizeScalar(u16, PATH, ';');
            while (it.next()) |search_path| {
                dir_buf.clearRetainingCapacity();
                try dir_buf.appendSlice(arena, search_path);

                if (windowsCreateProcessPathExt(
                    arena,
                    &dir_buf,
                    &app_buf,
                    PATHEXT,
                    &cmd_line_cache,
                    env_block,
                    cwd_w_ptr,
                    flags,
                    &siStartInfo,
                    &piProcInfo,
                )) {
                    break :run;
                } else |err| switch (err) {
                    // argv[0] contains unsupported characters that will never resolve to a valid exe.
                    error.InvalidArg0 => return error.FileNotFound,
                    error.FileNotFound, error.AccessDenied, error.InvalidExe => continue,
                    error.UnrecoverableInvalidExe => return error.InvalidExe,
                    else => |e| return e,
                }
            } else {
                return original_err;
            }
        };
    }

    if (options.progress_node.index != .none) {
        windows.CloseHandle(prog_pipe[1]);
        options.progress_node.setIpcFile(t, .{ .handle = prog_pipe[0], .flags = .{ .nonblocking = true } });
    }

    return .{
        .id = piProcInfo.hProcess,
        .thread_handle = piProcInfo.hThread,
        .stdin = stdin: switch (options.stdin) {
            .file => {
                windows.CloseHandle(siStartInfo.hStdInput.?);
                break :stdin null;
            },
            .pipe => {
                windows.CloseHandle(stdin_pipe[1]);
                break :stdin .{ .handle = stdin_pipe[0], .flags = .{ .nonblocking = false } };
            },
            else => null,
        },
        .stdout = stdout: switch (options.stdout) {
            .file => {
                windows.CloseHandle(siStartInfo.hStdOutput.?);
                break :stdout null;
            },
            .pipe => {
                windows.CloseHandle(stdout_pipe[1]);
                break :stdout .{ .handle = stdout_pipe[0], .flags = .{ .nonblocking = true } };
            },
            else => null,
        },
        .stderr = stderr: switch (options.stderr) {
            .file => {
                windows.CloseHandle(siStartInfo.hStdError.?);
                break :stderr null;
            },
            .pipe => {
                windows.CloseHandle(stderr_pipe[1]);
                break :stderr .{ .handle = stderr_pipe[0], .flags = .{ .nonblocking = true } };
            },
            else => null,
        },
        .request_resource_usage_statistics = options.request_resource_usage_statistics,
    };
}

fn inheritFile() windows.HANDLE {}

fn getCngDevice(t: *Threaded) Io.RandomSecureError!windows.HANDLE {
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);
        if (t.random_file.handle) |handle| return handle;
    }

    var fresh_handle: windows.HANDLE = undefined;
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtOpenFile(
        &fresh_handle,
        .{
            .STANDARD = .{ .SYNCHRONIZE = true },
            .SPECIFIC = .{ .FILE = .{ .READ_DATA = true } },
        },
        &.{ .ObjectName = @constCast(&windows.UNICODE_STRING.init(
            &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'C', 'N', 'G' },
        )) },
        &io_status_block,
        .VALID_FLAGS,
        .{ .IO = .SYNCHRONOUS_NONALERT },
    )) {
        .SUCCESS => {
            syscall.finish();
            mutexLock(&t.mutex); // Another thread might have won the race.
            defer mutexUnlock(&t.mutex);
            if (t.random_file.handle) |prev_handle| {
                windows.CloseHandle(fresh_handle);
                return prev_handle;
            } else {
                t.random_file.handle = fresh_handle;
                return fresh_handle;
            }
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.EntropyUnavailable), // Observed on wine 10.0
        else => return syscall.fail(error.EntropyUnavailable),
    };
}

fn getNulDevice(t: *Threaded) !windows.HANDLE {
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);
        if (t.null_file.handle) |handle| return handle;
    }

    var fresh_handle: windows.HANDLE = undefined;
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtOpenFile(
        &fresh_handle,
        .{
            .STANDARD = .{ .SYNCHRONIZE = true },
            .SPECIFIC = .{ .FILE = .{ .READ_DATA = true, .WRITE_DATA = true } },
        },
        &.{
            .Attributes = .{ .INHERIT = true },
            .ObjectName = @constCast(&windows.UNICODE_STRING.init(
                &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'N', 'u', 'l', 'l' },
            )),
        },
        &io_status_block,
        .VALID_FLAGS,
        .{ .IO = .SYNCHRONOUS_NONALERT },
    )) {
        .SUCCESS => {
            syscall.finish();
            mutexLock(&t.mutex); // Another thread might have won the race.
            defer mutexUnlock(&t.mutex);
            if (t.null_file.handle) |prev_handle| {
                windows.CloseHandle(fresh_handle);
                return prev_handle;
            } else {
                t.null_file.handle = fresh_handle;
                return fresh_handle;
            }
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
        .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
        .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
        .SHARING_VIOLATION => return syscall.fail(error.AccessDenied),
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .PIPE_NOT_AVAILABLE => return syscall.fail(error.NoDevice),
        .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
        .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
        .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
}

fn getNamedPipeDevice(t: *Threaded) !windows.HANDLE {
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);
        if (t.pipe_file.handle) |handle| return handle;
    }

    var fresh_handle: windows.HANDLE = undefined;
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var syscall: Syscall = try .start();
    while (true) switch (windows.ntdll.NtOpenFile(
        &fresh_handle,
        .{ .STANDARD = .{ .SYNCHRONIZE = true } },
        &.{
            .ObjectName = @constCast(&windows.UNICODE_STRING.init(
                &.{ '\\', 'D', 'e', 'v', 'i', 'c', 'e', '\\', 'N', 'a', 'm', 'e', 'd', 'P', 'i', 'p', 'e', '\\' },
            )),
        },
        &io_status_block,
        .VALID_FLAGS,
        .{ .IO = .SYNCHRONOUS_NONALERT },
    )) {
        .SUCCESS => {
            syscall.finish();
            mutexLock(&t.mutex); // Another thread might have won the race.
            defer mutexUnlock(&t.mutex);
            if (t.pipe_file.handle) |prev_handle| {
                windows.CloseHandle(fresh_handle);
                return prev_handle;
            } else {
                t.pipe_file.handle = fresh_handle;
                return fresh_handle;
            }
        },
        .DELETE_PENDING => {
            // This error means that there *was* a file in this location on
            // the file system, but it was deleted. However, the OS is not
            // finished with the deletion operation, and so this CreateFile
            // call has failed. There is not really a sane way to handle
            // this other than retrying the creation after the OS finishes
            // the deletion.
            syscall.finish();
            try parking_sleep.sleep(.{ .duration = .{
                .raw = .fromMilliseconds(1),
                .clock = .awake,
            } });
            syscall = try .start();
            continue;
        },
        .CANCELLED => {
            try syscall.checkCancel();
            continue;
        },
        .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
        .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
        .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
        .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
        .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
        .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
        .SHARING_VIOLATION => return syscall.fail(error.AccessDenied),
        .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
        .PIPE_NOT_AVAILABLE => return syscall.fail(error.NoDevice),
        .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
        .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
        .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
        else => |status| return syscall.unexpectedNtstatus(status),
    };
}

/// Expects `app_buf` to contain exactly the app name, and `dir_buf` to contain exactly the dir path.
/// After return, `app_buf` will always contain exactly the app name and `dir_buf` will always contain exactly the dir path.
/// Note: `app_buf` should not contain any leading path separators.
/// Note: If the dir is the cwd, dir_buf should be empty (len = 0).
fn windowsCreateProcessPathExt(
    arena: Allocator,
    dir_buf: *std.ArrayList(u16),
    app_buf: *std.ArrayList(u16),
    pathext: [:0]const u16,
    cmd_line_cache: *WindowsCommandLineCache,
    env_block: ?process.Environ.WindowsBlock,
    cwd_ptr: ?[*:0]u16,
    flags: windows.CreateProcessFlags,
    lpStartupInfo: *windows.STARTUPINFOW,
    lpProcessInformation: *windows.PROCESS.INFORMATION,
) !void {
    const app_name_len = app_buf.items.len;
    const dir_path_len = dir_buf.items.len;

    if (app_name_len == 0) return error.FileNotFound;

    defer app_buf.shrinkRetainingCapacity(app_name_len);
    defer dir_buf.shrinkRetainingCapacity(dir_path_len);

    // The name of the game here is to avoid CreateProcessW calls at all costs,
    // and only ever try calling it when we have a real candidate for execution.
    // Secondarily, we want to minimize the number of syscalls used when checking
    // for each PATHEXT-appended version of the app name.
    //
    // An overview of the technique used:
    // - Open the search directory for iteration (either cwd or a path from PATH)
    // - Use NtQueryDirectoryFile with a wildcard filename of `<app name>*` to
    //   check if anything that could possibly match either the unappended version
    //   of the app name or any of the versions with a PATHEXT value appended exists.
    // - If the wildcard NtQueryDirectoryFile call found nothing, we can exit early
    //   without needing to use PATHEXT at all.
    //
    // This allows us to use a <open dir, NtQueryDirectoryFile, close dir> sequence
    // for any directory that doesn't contain any possible matches, instead of having
    // to use a separate look up for each individual filename combination (unappended +
    // each PATHEXT appended). For directories where the wildcard *does* match something,
    // we iterate the matches and take note of any that are either the unappended version,
    // or a version with a supported PATHEXT appended. We then try calling CreateProcessW
    // with the found versions in the appropriate order.
    const dir = dir: {
        // needs to be null-terminated
        try dir_buf.append(arena, 0);
        defer dir_buf.shrinkRetainingCapacity(dir_path_len);
        const dir_path_z = dir_buf.items[0 .. dir_buf.items.len - 1 :0];
        const prefixed_path = try wToPrefixedFileW(null, dir_path_z, .{});
        break :dir dirOpenDirWindows(.cwd(), prefixed_path.span(), .{
            .iterate = true,
        }) catch |err| switch (err) {
            // These errors must not be ignored because they should not be able
            // to affect which file is chosen to execute. Also `error.Canceled`
            // must never be swallowed.
            error.Canceled,
            error.SystemResources,
            error.Unexpected,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            => |e| return e,

            error.AccessDenied,
            error.PermissionDenied,
            error.SymLinkLoop,
            error.FileNotFound,
            error.NotDir,
            error.NoDevice,
            error.NetworkNotFound,
            error.NameTooLong,
            error.BadPathName,
            => return error.FileNotFound,
        };
    };
    defer windows.CloseHandle(dir.handle);

    // Add wildcard and null-terminator
    try app_buf.append(arena, '*');
    try app_buf.append(arena, 0);
    const app_name_wildcard = app_buf.items[0 .. app_buf.items.len - 1 :0];

    // This 2048 is arbitrary, we just want it to be large enough to get multiple FILE_DIRECTORY_INFORMATION entries
    // returned per NtQueryDirectoryFile call.
    var file_information_buf: [2048]u8 align(@alignOf(windows.FILE_DIRECTORY_INFORMATION)) = undefined;
    const file_info_maximum_single_entry_size = @sizeOf(windows.FILE_DIRECTORY_INFORMATION) + (windows.NAME_MAX * 2);
    if (file_information_buf.len < file_info_maximum_single_entry_size) {
        @compileError("file_information_buf must be large enough to contain at least one maximum size FILE_DIRECTORY_INFORMATION entry");
    }
    var io_status: windows.IO_STATUS_BLOCK = undefined;

    const num_supported_pathext = @typeInfo(process.WindowsExtension).@"enum".fields.len;
    var pathext_seen = [_]bool{false} ** num_supported_pathext;
    var any_pathext_seen = false;
    var unappended_exists = false;

    // Fully iterate the wildcard matches via NtQueryDirectoryFile and take note of all versions
    // of the app_name we should try to spawn.
    // Note: This is necessary because the order of the files returned is filesystem-dependent:
    //       On NTFS, `blah.exe*` will always return `blah.exe` first if it exists.
    //       On FAT32, it's possible for something like `blah.exe.obj` to be returned first.
    while (true) {
        // If we get nothing with the wildcard, then we can just bail out
        // as we know appending PATHEXT will not yield anything.
        switch (windows.ntdll.NtQueryDirectoryFile(
            dir.handle,
            null,
            null,
            null,
            &io_status,
            &file_information_buf,
            file_information_buf.len,
            .Directory,
            .FALSE, // single result
            &.init(app_name_wildcard),
            .FALSE, // restart iteration
        )) {
            .SUCCESS => {},
            .NO_SUCH_FILE => return error.FileNotFound,
            .NO_MORE_FILES => break,
            .ACCESS_DENIED => return error.AccessDenied,
            else => |status| return windows.unexpectedStatus(status),
        }

        // According to the docs, this can only happen if there is not enough room in the
        // buffer to write at least one complete FILE_DIRECTORY_INFORMATION entry.
        // Therefore, this condition should not be possible to hit with the buffer size we use.
        std.debug.assert(io_status.Information != 0);

        var it = windows.FileInformationIterator(windows.FILE_DIRECTORY_INFORMATION){ .buf = &file_information_buf };
        while (it.next()) |info| {
            // Skip directories
            if (info.FileAttributes.DIRECTORY) continue;
            const filename = @as([*]u16, @ptrCast(&info.FileName))[0 .. info.FileNameLength / 2];
            // Because all results start with the app_name since we're using the wildcard `app_name*`,
            // if the length is equal to app_name then this is an exact match
            if (filename.len == app_name_len) {
                // Note: We can't break early here because it's possible that the unappended version
                //       fails to spawn, in which case we still want to try the PATHEXT appended versions.
                unappended_exists = true;
            } else if (windowsCreateProcessSupportsExtension(filename[app_name_len..])) |pathext_ext| {
                pathext_seen[@intFromEnum(pathext_ext)] = true;
                any_pathext_seen = true;
            }
        }
    }

    const unappended_err = unappended: {
        if (unappended_exists) {
            if (dir_path_len != 0) switch (dir_buf.items[dir_buf.items.len - 1]) {
                '/', '\\' => {},
                else => try dir_buf.append(arena, Dir.path.sep),
            };
            try dir_buf.appendSlice(arena, app_buf.items[0..app_name_len]);
            try dir_buf.append(arena, 0);
            const full_app_name = dir_buf.items[0 .. dir_buf.items.len - 1 :0];

            const is_bat_or_cmd = bat_or_cmd: {
                const app_name = app_buf.items[0..app_name_len];
                const ext_start = std.mem.lastIndexOfScalar(u16, app_name, '.') orelse break :bat_or_cmd false;
                const ext = app_name[ext_start..];
                const ext_enum = windowsCreateProcessSupportsExtension(ext) orelse break :bat_or_cmd false;
                switch (ext_enum) {
                    .cmd, .bat => break :bat_or_cmd true,
                    else => break :bat_or_cmd false,
                }
            };
            const cmd_line_w = if (is_bat_or_cmd)
                try cmd_line_cache.scriptCommandLine(full_app_name)
            else
                try cmd_line_cache.commandLine();
            const app_name_w = if (is_bat_or_cmd)
                try cmd_line_cache.cmdExePath()
            else
                full_app_name;

            if (windowsCreateProcess(
                app_name_w.ptr,
                cmd_line_w.ptr,
                env_block,
                cwd_ptr,
                flags,
                lpStartupInfo,
                lpProcessInformation,
            )) |_| {
                return;
            } else |err| switch (err) {
                error.FileNotFound,
                error.AccessDenied,
                => break :unappended err,
                error.InvalidExe => {
                    // On InvalidExe, if the extension of the app name is .exe then
                    // it's treated as an unrecoverable error. Otherwise, it'll be
                    // skipped as normal.
                    const app_name = app_buf.items[0..app_name_len];
                    const ext_start = std.mem.lastIndexOfScalar(u16, app_name, '.') orelse break :unappended err;
                    const ext = app_name[ext_start..];
                    if (windows.eqlIgnoreCaseWtf16(ext, std.unicode.utf8ToUtf16LeStringLiteral(".EXE"))) {
                        return error.UnrecoverableInvalidExe;
                    }
                    break :unappended err;
                },
                else => return err,
            }
        }
        break :unappended error.FileNotFound;
    };

    if (!any_pathext_seen) return unappended_err;

    // Now try any PATHEXT appended versions that we've seen
    var ext_it = std.mem.tokenizeScalar(u16, pathext, ';');
    while (ext_it.next()) |ext| {
        const ext_enum = windowsCreateProcessSupportsExtension(ext) orelse continue;
        if (!pathext_seen[@intFromEnum(ext_enum)]) continue;

        dir_buf.shrinkRetainingCapacity(dir_path_len);
        if (dir_path_len != 0) switch (dir_buf.items[dir_buf.items.len - 1]) {
            '/', '\\' => {},
            else => try dir_buf.append(arena, Dir.path.sep),
        };
        try dir_buf.appendSlice(arena, app_buf.items[0..app_name_len]);
        try dir_buf.appendSlice(arena, ext);
        try dir_buf.append(arena, 0);
        const full_app_name = dir_buf.items[0 .. dir_buf.items.len - 1 :0];

        const is_bat_or_cmd = switch (ext_enum) {
            .cmd, .bat => true,
            else => false,
        };
        const cmd_line_w = if (is_bat_or_cmd)
            try cmd_line_cache.scriptCommandLine(full_app_name)
        else
            try cmd_line_cache.commandLine();
        const app_name_w = if (is_bat_or_cmd)
            try cmd_line_cache.cmdExePath()
        else
            full_app_name;

        if (windowsCreateProcess(app_name_w.ptr, cmd_line_w.ptr, env_block, cwd_ptr, flags, lpStartupInfo, lpProcessInformation)) |_| {
            return;
        } else |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => continue,
            error.InvalidExe => {
                // On InvalidExe, if the extension of the app name is .exe then
                // it's treated as an unrecoverable error. Otherwise, it'll be
                // skipped as normal.
                if (windows.eqlIgnoreCaseWtf16(ext, std.unicode.utf8ToUtf16LeStringLiteral(".EXE"))) {
                    return error.UnrecoverableInvalidExe;
                }
                continue;
            },
            else => return err,
        }
    }

    return unappended_err;
}

fn windowsCreateProcess(
    app_name: [*:0]u16,
    cmd_line: [*:0]u16,
    env_block: ?process.Environ.WindowsBlock,
    cwd_ptr: ?[*:0]u16,
    flags: windows.CreateProcessFlags,
    lpStartupInfo: *windows.STARTUPINFOW,
    lpProcessInformation: *windows.PROCESS.INFORMATION,
) !void {
    const syscall: Syscall = try .start();
    while (true) {
        if (windows.kernel32.CreateProcessW(
            app_name,
            cmd_line,
            null,
            null,
            .TRUE,
            flags,
            if (env_block) |block| block.slice.ptr else null,
            cwd_ptr,
            lpStartupInfo,
            lpProcessInformation,
        ).toBool()) {
            return syscall.finish();
        } else switch (windows.GetLastError()) {
            .INVALID_PARAMETER => unreachable,
            .OPERATION_ABORTED => {
                try syscall.checkCancel();
                continue;
            },
            .FILE_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .DIRECTORY => return syscall.fail(error.FileNotFound),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .INVALID_NAME => return syscall.fail(error.InvalidName),
            .FILENAME_EXCED_RANGE => return syscall.fail(error.NameTooLong),
            .SHARING_VIOLATION => return syscall.fail(error.FileBusy),
            .COMMITMENT_LIMIT => return syscall.fail(error.SystemResources),

            // These are all the system errors that are mapped to ENOEXEC by
            // the undocumented _dosmaperr (old CRT) or __acrt_errno_map_os_error
            // (newer CRT) functions. Their code can be found in crt/src/dosmap.c (old SDK)
            // or urt/misc/errno.cpp (newer SDK) in the Windows SDK.
            .BAD_FORMAT,
            .INVALID_STARTING_CODESEG, // MIN_EXEC_ERROR in errno.cpp
            .INVALID_STACKSEG,
            .INVALID_MODULETYPE,
            .INVALID_EXE_SIGNATURE,
            .EXE_MARKED_INVALID,
            .BAD_EXE_FORMAT,
            .ITERATED_DATA_EXCEEDS_64k,
            .INVALID_MINALLOCSIZE,
            .DYNLINK_FROM_INVALID_RING,
            .IOPL_NOT_ENABLED,
            .INVALID_SEGDPL,
            .AUTODATASEG_EXCEEDS_64k,
            .RING2SEG_MUST_BE_MOVABLE,
            .RELOC_CHAIN_XEEDS_SEGLIM,
            .INFLOOP_IN_RELOC_CHAIN, // MAX_EXEC_ERROR in errno.cpp
            // This one is not mapped to ENOEXEC but it is possible, for example
            // when calling CreateProcessW on a plain text file with a .exe extension
            .EXE_MACHINE_TYPE_MISMATCH,
            => return syscall.fail(error.InvalidExe),

            else => |err| {
                syscall.finish();
                return windows.unexpectedError(err);
            },
        }
    }
}

/// Case-insensitive WTF-16 lookup
fn windowsCreateProcessSupportsExtension(ext: []const u16) ?process.WindowsExtension {
    comptime {
        // Ensures keeping this function in sync with the enum.
        const fields = @typeInfo(process.WindowsExtension).@"enum".fields;
        assert(fields.len == 4);
        assert(@intFromEnum(process.WindowsExtension.bat) == 0);
        assert(@intFromEnum(process.WindowsExtension.cmd) == 1);
        assert(@intFromEnum(process.WindowsExtension.com) == 2);
        assert(@intFromEnum(process.WindowsExtension.exe) == 3);
    }

    if (ext.len != 4) return null;
    const State = enum {
        start,
        dot,
        b,
        ba,
        c,
        cm,
        co,
        e,
        ex,
    };
    var state: State = .start;
    for (ext) |c| switch (state) {
        .start => switch (c) {
            '.' => state = .dot,
            else => return null,
        },
        .dot => switch (c) {
            'b', 'B' => state = .b,
            'c', 'C' => state = .c,
            'e', 'E' => state = .e,
            else => return null,
        },
        .b => switch (c) {
            'a', 'A' => state = .ba,
            else => return null,
        },
        .c => switch (c) {
            'm', 'M' => state = .cm,
            'o', 'O' => state = .co,
            else => return null,
        },
        .e => switch (c) {
            'x', 'X' => state = .ex,
            else => return null,
        },
        .ba => switch (c) {
            't', 'T' => return .bat,
            else => return null,
        },
        .cm => switch (c) {
            'd', 'D' => return .cmd,
            else => return null,
        },
        .co => switch (c) {
            'm', 'M' => return .com,
            else => return null,
        },
        .ex => switch (c) {
            'e', 'E' => return .exe,
            else => return null,
        },
    };
    return null;
}

test windowsCreateProcessSupportsExtension {
    try std.testing.expectEqual(process.WindowsExtension.exe, windowsCreateProcessSupportsExtension(&[_]u16{ '.', 'e', 'X', 'e' }).?);
    try std.testing.expect(windowsCreateProcessSupportsExtension(&[_]u16{ '.', 'e', 'X', 'e', 'c' }) == null);
}

/// Serializes argv into a WTF-16 encoded command-line string for use with CreateProcessW.
///
/// Serialization is done on-demand and the result is cached in order to allow for:
/// - Only serializing the particular type of command line needed (`.bat`/`.cmd`
///   command line serialization is different from `.exe`/etc)
/// - Reusing the serialized command lines if necessary (i.e. if the execution
///   of a command fails and the PATH is going to be continued to be searched
///   for more candidates)
const WindowsCommandLineCache = struct {
    cmd_line: ?[:0]u16 = null,
    script_cmd_line: ?[:0]u16 = null,
    cmd_exe_path: ?[:0]u16 = null,
    argv: []const []const u8,
    allocator: Allocator,

    fn init(allocator: Allocator, argv: []const []const u8) WindowsCommandLineCache {
        return .{
            .allocator = allocator,
            .argv = argv,
        };
    }

    fn deinit(self: *WindowsCommandLineCache) void {
        if (self.cmd_line) |cmd_line| self.allocator.free(cmd_line);
        if (self.script_cmd_line) |script_cmd_line| self.allocator.free(script_cmd_line);
        if (self.cmd_exe_path) |cmd_exe_path| self.allocator.free(cmd_exe_path);
    }

    fn commandLine(self: *WindowsCommandLineCache) ![:0]u16 {
        if (self.cmd_line == null) {
            self.cmd_line = try argvToCommandLineWindows(self.allocator, self.argv);
        }
        return self.cmd_line.?;
    }

    /// Not cached, since the path to the batch script will change during PATH searching.
    /// `script_path` should be as qualified as possible, e.g. if the PATH is being searched,
    /// then script_path should include both the search path and the script filename
    /// (this allows avoiding cmd.exe having to search the PATH again).
    fn scriptCommandLine(self: *WindowsCommandLineCache, script_path: []const u16) ![:0]u16 {
        if (self.script_cmd_line) |v| self.allocator.free(v);
        self.script_cmd_line = try argvToScriptCommandLineWindows(
            self.allocator,
            script_path,
            self.argv[1..],
        );
        return self.script_cmd_line.?;
    }

    fn cmdExePath(self: *WindowsCommandLineCache) Allocator.Error![:0]u16 {
        if (self.cmd_exe_path == null) {
            // Remove trailing slash from system directory path; we'll re-add it below
            const system_dir = std.mem.trimEnd(u16, windows.getSystemDirectoryWtf16Le(), &.{ '/', '\\' });
            const suffix = std.unicode.utf8ToUtf16LeStringLiteral("\\cmd.exe");
            const buf = try self.allocator.allocSentinel(u16, system_dir.len + suffix.len, 0);
            errdefer comptime unreachable;
            @memcpy(buf[0..system_dir.len], system_dir);
            @memcpy(buf[system_dir.len..], suffix);
            self.cmd_exe_path = buf;
        }
        return self.cmd_exe_path.?;
    }
};

const ArgvToScriptCommandLineError = error{
    OutOfMemory,
    InvalidWtf8,
    /// NUL (U+0000), LF (U+000A), CR (U+000D) are not allowed
    /// within arguments when executing a `.bat`/`.cmd` script.
    /// - NUL/LF signifiies end of arguments, so anything afterwards
    ///   would be lost after execution.
    /// - CR is stripped by `cmd.exe`, so any CR codepoints
    ///   would be lost after execution.
    InvalidBatchScriptArg,
};

/// Serializes `argv` to a Windows command-line string that uses `cmd.exe /c` and `cmd.exe`-specific
/// escaping rules. The caller owns the returned slice.
///
/// Escapes `argv` using the suggested mitigation against arbitrary command execution from:
/// https://flatt.tech/research/posts/batbadbut-you-cant-securely-execute-commands-on-windows/
///
/// The return of this function will look like
/// `cmd.exe /d /e:ON /v:OFF /c "<escaped command line>"`
/// and should be used as the `lpCommandLine` of `CreateProcessW`, while the return of
/// `WindowsCommandLineCache.cmdExePath` should be used as `lpApplicationName`.
///
/// Should only be used when spawning `.bat`/`.cmd` scripts, see `argvToCommandLineWindows` otherwise.
/// The `.bat`/`.cmd` file must be known to both have the `.bat`/`.cmd` extension and exist on the filesystem.
fn argvToScriptCommandLineWindows(
    allocator: Allocator,
    /// Path to the `.bat`/`.cmd` script. If this path is relative, it is assumed to be relative to the CWD.
    /// The script must have been verified to exist at this path before calling this function.
    script_path: []const u16,
    /// Arguments, not including the script name itself. Expected to be encoded as WTF-8.
    script_args: []const []const u8,
) ArgvToScriptCommandLineError![:0]u16 {
    var buf = try std.array_list.Managed(u8).initCapacity(allocator, 64);
    defer buf.deinit();

    // `/d` disables execution of AutoRun commands.
    // `/e:ON` and `/v:OFF` are needed for BatBadBut mitigation:
    // > If delayed expansion is enabled via the registry value DelayedExpansion,
    // > it must be disabled by explicitly calling cmd.exe with the /V:OFF option.
    // > Escaping for % requires the command extension to be enabled.
    // > If it’s disabled via the registry value EnableExtensions, it must be enabled with the /E:ON option.
    // https://flatt.tech/research/posts/batbadbut-you-cant-securely-execute-commands-on-windows/
    buf.appendSliceAssumeCapacity("cmd.exe /d /e:ON /v:OFF /c \"");

    // Always quote the path to the script arg
    buf.appendAssumeCapacity('"');
    // We always want the path to the batch script to include a path separator in order to
    // avoid cmd.exe searching the PATH for the script. This is not part of the arbitrary
    // command execution mitigation, we just know exactly what script we want to execute
    // at this point, and potentially making cmd.exe re-find it is unnecessary.
    //
    // If the script path does not have a path separator, then we know its relative to CWD and
    // we can just put `.\` in the front.
    if (std.mem.findAny(u16, script_path, &[_]u16{
        std.mem.nativeToLittle(u16, '\\'), std.mem.nativeToLittle(u16, '/'),
    }) == null) {
        try buf.appendSlice(".\\");
    }
    // Note that we don't do any escaping/mitigations for this argument, since the relevant
    // characters (", %, etc) are illegal in file paths and this function should only be called
    // with script paths that have been verified to exist.
    try std.unicode.wtf16LeToWtf8ArrayList(&buf, script_path);
    buf.appendAssumeCapacity('"');

    for (script_args) |arg| {
        // Literal carriage returns get stripped when run through cmd.exe
        // and NUL/newlines act as 'end of command.' Because of this, it's basically
        // always a mistake to include these characters in argv, so it's
        // an error condition in order to ensure that the return of this
        // function can always roundtrip through cmd.exe.
        if (std.mem.findAny(u8, arg, "\x00\r\n") != null) {
            return error.InvalidBatchScriptArg;
        }

        // Separate args with a space.
        try buf.append(' ');

        // Need to quote if the argument is empty (otherwise the arg would just be lost)
        // or if the last character is a `\`, since then something like "%~2" in a .bat
        // script would cause the closing " to be escaped which we don't want.
        var needs_quotes = arg.len == 0 or arg[arg.len - 1] == '\\';
        if (!needs_quotes) {
            for (arg) |c| {
                switch (c) {
                    // Known good characters that don't need to be quoted
                    'A'...'Z', 'a'...'z', '0'...'9', '#', '$', '*', '+', '-', '.', '/', ':', '?', '@', '\\', '_' => {},
                    // When in doubt, quote
                    else => {
                        needs_quotes = true;
                        break;
                    },
                }
            }
        }
        if (needs_quotes) {
            try buf.append('"');
        }
        var backslashes: usize = 0;
        for (arg) |c| {
            switch (c) {
                '\\' => {
                    backslashes += 1;
                },
                '"' => {
                    try buf.appendNTimes('\\', backslashes);
                    try buf.append('"');
                    backslashes = 0;
                },
                // Replace `%` with `%%cd:~,%`.
                //
                // cmd.exe allows extracting a substring from an environment
                // variable with the syntax: `%foo:~<start_index>,<end_index>%`.
                // Therefore, `%cd:~,%` will always expand to an empty string
                // since both the start and end index are blank, and it is assumed
                // that `%cd%` is always available since it is a built-in variable
                // that corresponds to the current directory.
                //
                // This means that replacing `%foo%` with `%%cd:~,%foo%%cd:~,%`
                // will stop `%foo%` from being expanded and *after* expansion
                // we'll still be left with `%foo%` (the literal string).
                '%' => {
                    // the trailing `%` is appended outside the switch
                    try buf.appendSlice("%%cd:~,");
                    backslashes = 0;
                },
                else => {
                    backslashes = 0;
                },
            }
            try buf.append(c);
        }
        if (needs_quotes) {
            try buf.appendNTimes('\\', backslashes);
            try buf.append('"');
        }
    }

    try buf.append('"');

    return try std.unicode.wtf8ToWtf16LeAllocZ(allocator, buf.items);
}

const ArgvToCommandLineError = error{ OutOfMemory, InvalidWtf8, InvalidArg0 };

/// Serializes `argv` to a Windows command-line string suitable for passing to a child process and
/// parsing by the `CommandLineToArgvW` algorithm. The caller owns the returned slice.
///
/// To avoid arbitrary command execution, this function should not be used when spawning `.bat`/`.cmd` scripts.
/// https://flatt.tech/research/posts/batbadbut-you-cant-securely-execute-commands-on-windows/
///
/// When executing `.bat`/`.cmd` scripts, use `argvToScriptCommandLineWindows` instead.
fn argvToCommandLineWindows(
    allocator: Allocator,
    argv: []const []const u8,
) ArgvToCommandLineError![:0]u16 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    if (argv.len != 0) {
        const arg0 = argv[0];

        // The first argument must be quoted if it contains spaces or ASCII control characters
        // (excluding DEL). It also follows special quoting rules where backslashes have no special
        // interpretation, which makes it impossible to pass certain first arguments containing
        // double quotes to a child process without characters from the first argument leaking into
        // subsequent ones (which could have security implications).
        //
        // Empty arguments technically don't need quotes, but we quote them anyway for maximum
        // compatibility with different implementations of the 'CommandLineToArgvW' algorithm.
        //
        // Double quotes are illegal in paths on Windows, so for the sake of simplicity we reject
        // all first arguments containing double quotes, even ones that we could theoretically
        // serialize in unquoted form.
        var needs_quotes = arg0.len == 0;
        for (arg0) |c| {
            if (c <= ' ') {
                needs_quotes = true;
            } else if (c == '"') {
                return error.InvalidArg0;
            }
        }
        if (needs_quotes) {
            try buf.append('"');
            try buf.appendSlice(arg0);
            try buf.append('"');
        } else {
            try buf.appendSlice(arg0);
        }

        for (argv[1..]) |arg| {
            try buf.append(' ');

            // Subsequent arguments must be quoted if they contain spaces, tabs or double quotes,
            // or if they are empty. For simplicity and for maximum compatibility with different
            // implementations of the 'CommandLineToArgvW' algorithm, we also quote all ASCII
            // control characters (again, excluding DEL).
            needs_quotes = for (arg) |c| {
                if (c <= ' ' or c == '"') {
                    break true;
                }
            } else arg.len == 0;
            if (!needs_quotes) {
                try buf.appendSlice(arg);
                continue;
            }

            try buf.append('"');
            var backslash_count: usize = 0;
            for (arg) |byte| {
                switch (byte) {
                    '\\' => {
                        backslash_count += 1;
                    },
                    '"' => {
                        try buf.appendNTimes('\\', backslash_count * 2 + 1);
                        try buf.append('"');
                        backslash_count = 0;
                    },
                    else => {
                        try buf.appendNTimes('\\', backslash_count);
                        try buf.append(byte);
                        backslash_count = 0;
                    },
                }
            }
            try buf.appendNTimes('\\', backslash_count * 2);
            try buf.append('"');
        }
    }

    return try std.unicode.wtf8ToWtf16LeAllocZ(allocator, buf.items);
}

test argvToCommandLineWindows {
    const t = testArgvToCommandLineWindows;

    try t(&.{
        \\C:\Program Files\zig\zig.exe
        ,
        \\run
        ,
        \\.\src\main.zig
        ,
        \\-target
        ,
        \\x86_64-windows-gnu
        ,
        \\-O
        ,
        \\ReleaseSafe
        ,
        \\--
        ,
        \\--emoji=🗿
        ,
        \\--eval=new Regex("Dwayne \"The Rock\" Johnson")
        ,
    },
        \\"C:\Program Files\zig\zig.exe" run .\src\main.zig -target x86_64-windows-gnu -O ReleaseSafe -- --emoji=🗿 "--eval=new Regex(\"Dwayne \\\"The Rock\\\" Johnson\")"
    );

    try t(&.{}, "");
    try t(&.{""}, "\"\"");
    try t(&.{" "}, "\" \"");
    try t(&.{"\t"}, "\"\t\"");
    try t(&.{"\x07"}, "\"\x07\"");
    try t(&.{"🦎"}, "🦎");

    try t(
        &.{ "zig", "aa aa", "bb\tbb", "cc\ncc", "dd\r\ndd", "ee\x7Fee" },
        "zig \"aa aa\" \"bb\tbb\" \"cc\ncc\" \"dd\r\ndd\" ee\x7Fee",
    );

    try t(
        &.{ "\\\\foo bar\\foo bar\\", "\\\\zig zag\\zig zag\\" },
        "\"\\\\foo bar\\foo bar\\\" \"\\\\zig zag\\zig zag\\\\\"",
    );

    try std.testing.expectError(
        error.InvalidArg0,
        argvToCommandLineWindows(std.testing.allocator, &.{"\"quotes\"quotes\""}),
    );
    try std.testing.expectError(
        error.InvalidArg0,
        argvToCommandLineWindows(std.testing.allocator, &.{"quotes\"quotes"}),
    );
    try std.testing.expectError(
        error.InvalidArg0,
        argvToCommandLineWindows(std.testing.allocator, &.{"q u o t e s \" q u o t e s"}),
    );
}

fn testArgvToCommandLineWindows(argv: []const []const u8, expected_cmd_line: []const u8) !void {
    const cmd_line_w = try argvToCommandLineWindows(std.testing.allocator, argv);
    defer std.testing.allocator.free(cmd_line_w);

    const cmd_line = try std.unicode.wtf16LeToWtf8Alloc(std.testing.allocator, cmd_line_w);
    defer std.testing.allocator.free(cmd_line);

    try std.testing.expectEqualStrings(expected_cmd_line, cmd_line);
}

fn posixExecv(
    arg0_expand: process.ArgExpansion,
    file: [*:0]const u8,
    child_argv: [*:null]?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
    PATH: []const u8,
) process.ReplaceError {
    const file_slice = std.mem.sliceTo(file, 0);
    if (std.mem.findScalar(u8, file_slice, '/') != null) return posixExecvPath(file, child_argv, env_block);

    // Use of PATH_MAX here is valid as the path_buf will be passed
    // directly to the operating system in posixExecvPath.
    var path_buf: [posix.PATH_MAX]u8 = undefined;
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
        err = posixExecvPath(full_path, child_argv, env_block);
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
pub fn posixExecvPath(
    path: [*:0]const u8,
    child_argv: [*:null]const ?[*:0]const u8,
    env_block: process.Environ.PosixBlock,
) process.ReplaceError {
    try Thread.checkCancel();
    switch (posix.errno(posix.system.execve(path, child_argv, env_block.slice.ptr))) {
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
        else => |err| switch (native_os) {
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (err) {
                .BADEXEC => return error.InvalidExe,
                .BADARCH => return error.InvalidExe,
                else => return posix.unexpectedErrno(err),
            },
            .linux => switch (err) {
                .LIBBAD => return error.InvalidExe,
                else => return posix.unexpectedErrno(err),
            },
            else => return posix.unexpectedErrno(err),
        },
    }
}

pub const CreatePipeOptions = struct {
    server: End,
    client: End,
    inbound: bool = false,
    outbound: bool = false,
    maximum_instances: u32 = 1,
    quota: u32 = 4096,
    default_timeout: windows.LARGE_INTEGER = -120 * std.time.ns_per_s / 100,

    pub const End = struct {
        attributes: windows.OBJECT.ATTRIBUTES.Flags = .{},
        mode: windows.FILE.MODE,
    };
};
pub fn windowsCreatePipe(t: *Threaded, options: CreatePipeOptions) ![2]windows.HANDLE {
    const named_pipe_device = try t.getNamedPipeDevice();
    const server_handle = server_handle: {
        var handle: windows.HANDLE = undefined;
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtCreateNamedPipeFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .READ_DATA = options.inbound,
                    .WRITE_DATA = options.outbound,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = named_pipe_device,
                .Attributes = options.server.attributes,
            },
            &io_status_block,
            .{ .READ = true, .WRITE = true },
            .CREATE,
            options.server.mode,
            .{ .TYPE = .BYTE_STREAM },
            .{ .MODE = .BYTE_STREAM },
            .{ .OPERATION = .QUEUE },
            options.maximum_instances,
            if (options.inbound) options.quota else 0,
            if (options.outbound) options.quota else 0,
            &options.default_timeout,
        )) {
            .SUCCESS => break syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
            .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
        break :server_handle handle;
    };
    errdefer windows.CloseHandle(server_handle);
    const client_handle = client_handle: {
        var handle: windows.HANDLE = undefined;
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        const syscall: Syscall = try .start();
        while (true) switch (windows.ntdll.NtOpenFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .READ_DATA = options.outbound,
                    .WRITE_DATA = options.inbound,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = server_handle,
                .Attributes = options.client.attributes,
            },
            &io_status_block,
            .{ .READ = true, .WRITE = true },
            options.client.mode,
        )) {
            .SUCCESS => break syscall.finish(),
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
            .INSUFFICIENT_RESOURCES => return syscall.fail(error.SystemResources),
            else => |status| return syscall.unexpectedNtstatus(status),
        };
        break :client_handle handle;
    };
    errdefer windows.CloseHandle(client_handle);
    return .{ server_handle, client_handle };
}

fn progressParentFile(userdata: ?*anyopaque) std.Progress.ParentFileError!File {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    t.scanEnviron();
    return t.environ.zig_progress_file;
}

pub fn environString(t: *Threaded, comptime name: []const u8) ?[:0]const u8 {
    t.scanEnviron();
    return @field(t.environ.string, name);
}

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const thread = Thread.current orelse return randomMainThread(t, buffer);
    if (!thread.csprng.isInitialized()) {
        @branchHint(.unlikely);
        var seed: [Csprng.seed_len]u8 = undefined;
        randomMainThread(t, &seed);
        thread.csprng.rng = .init(seed);
    }
    thread.csprng.rng.fill(buffer);
}

fn randomMainThread(t: *Threaded, buffer: []u8) void {
    mutexLock(&t.mutex);
    defer mutexUnlock(&t.mutex);

    if (!t.csprng.isInitialized()) {
        @branchHint(.unlikely);
        var seed: [Csprng.seed_len]u8 = undefined;
        {
            mutexUnlock(&t.mutex);
            defer mutexLock(&t.mutex);

            const prev = swapCancelProtection(t, .blocked);
            defer _ = swapCancelProtection(t, prev);

            randomSecure(t, &seed) catch |err| switch (err) {
                error.Canceled => unreachable,
                error.EntropyUnavailable => fallbackSeed(t, &seed),
            };
        }
        t.csprng.rng = .init(seed);
    }

    t.csprng.rng.fill(buffer);
}

pub fn fallbackSeed(aslr_addr: ?*anyopaque, seed: *[Csprng.seed_len]u8) void {
    @memset(seed, 0);
    std.mem.writeInt(usize, seed[seed.len - @sizeOf(usize) ..][0..@sizeOf(usize)], @intFromPtr(aslr_addr), .native);
    const fallbackSeedImpl = switch (native_os) {
        .windows => fallbackSeedWindows,
        .wasi => if (builtin.link_libc) fallbackSeedPosix else fallbackSeedWasi,
        else => fallbackSeedPosix,
    };
    fallbackSeedImpl(seed);
}

fn fallbackSeedPosix(seed: *[Csprng.seed_len]u8) void {
    std.mem.writeInt(posix.pid_t, seed[0..@sizeOf(posix.pid_t)], posix.system.getpid(), .native);
    const i_1 = @sizeOf(posix.pid_t);

    var ts: posix.timespec = undefined;
    const Sec = @TypeOf(ts.sec);
    const Nsec = @TypeOf(ts.nsec);
    const i_2 = i_1 + @sizeOf(Sec);
    switch (posix.errno(posix.system.clock_gettime(.REALTIME, &ts))) {
        .SUCCESS => {
            std.mem.writeInt(Sec, seed[i_1..][0..@sizeOf(Sec)], ts.sec, .native);
            std.mem.writeInt(Nsec, seed[i_2..][0..@sizeOf(Nsec)], ts.nsec, .native);
        },
        else => {},
    }
}

fn fallbackSeedWindows(seed: *[Csprng.seed_len]u8) void {
    var pc: windows.LARGE_INTEGER = undefined;
    _ = windows.ntdll.RtlQueryPerformanceCounter(&pc);
    std.mem.writeInt(windows.LARGE_INTEGER, seed[0..@sizeOf(windows.LARGE_INTEGER)], pc, .native);
}

fn fallbackSeedWasi(seed: *[Csprng.seed_len]u8) void {
    var ts: std.os.wasi.timestamp_t = undefined;
    if (std.os.wasi.clock_time_get(.REALTIME, 1, &ts) == .SUCCESS) {
        std.mem.writeInt(std.os.wasi.timestamp_t, seed[0..@sizeOf(std.os.wasi.timestamp_t)], ts, .native);
    }
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));

    if (is_windows) {
        if (buffer.len == 0) return;
        // ProcessPrng from bcryptprimitives.dll has the following properties:
        // * introduces a dependency on bcryptprimitives.dll, which apparently
        //   runs a test suite every time it is loaded
        // * heap allocates a 48-byte buffer, handling failure by returning NO_MEMORY in a BOOL
        //   despite the function being documented to always return TRUE
        // * reads from "\\Device\\CNG" which then seeds a per-CPU AES CSPRNG
        // Therefore, that function is avoided in favor of using the device directly.
        const cng_device = try getCngDevice(t);
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        var i: usize = 0;
        const syscall: Syscall = try .start();
        while (true) {
            const remaining_len = std.math.lossyCast(u32, buffer.len - i);
            switch (windows.ntdll.NtDeviceIoControlFile(
                cng_device,
                null,
                null,
                null,
                &io_status_block,
                windows.IOCTL.KSEC.GEN_RANDOM,
                null,
                0,
                buffer[i..].ptr,
                remaining_len,
            )) {
                .SUCCESS => {
                    i += remaining_len;
                    if (buffer.len - i == 0) {
                        return syscall.finish();
                    } else {
                        try syscall.checkCancel();
                        continue;
                    }
                },
                .CANCELLED => {
                    try syscall.checkCancel();
                    continue;
                },
                else => return syscall.fail(error.EntropyUnavailable),
            }
        }
    }

    if (builtin.link_libc and @TypeOf(posix.system.arc4random_buf) != void) {
        if (buffer.len == 0) return;
        posix.system.arc4random_buf(buffer.ptr, buffer.len);
        return;
    }

    if (native_os == .wasi) {
        if (buffer.len == 0) return;
        const syscall: Syscall = try .start();
        while (true) switch (std.os.wasi.random_get(buffer.ptr, buffer.len)) {
            .SUCCESS => return syscall.finish(),
            .INTR => {
                try syscall.checkCancel();
                continue;
            },
            else => return syscall.fail(error.EntropyUnavailable),
        };
    }

    if (@TypeOf(posix.system.getrandom) != void) {
        const getrandom = if (use_libc_getrandom) std.c.getrandom else std.os.linux.getrandom;
        var i: usize = 0;
        const syscall: Syscall = try .start();
        while (buffer.len - i != 0) {
            const buf = buffer[i..];
            const rc = getrandom(buf.ptr, buf.len, 0);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    const n: usize = @intCast(rc);
                    i += n;
                    continue;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => return syscall.fail(error.EntropyUnavailable),
            }
        }
        return;
    }

    if (native_os == .emscripten) {
        if (buffer.len == 0) return;
        const err = posix.errno(std.c.getentropy(buffer.ptr, buffer.len));
        switch (err) {
            .SUCCESS => return,
            else => return error.EntropyUnavailable,
        }
    }

    if (native_os == .linux) {
        comptime assert(use_dev_urandom);
        const urandom_fd = try getRandomFd(t);

        var i: usize = 0;
        while (buffer.len - i != 0) {
            const syscall: Syscall = try .start();
            const rc = posix.system.read(urandom_fd, buffer[i..].ptr, buffer.len - i);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    const n: usize = @intCast(rc);
                    if (n == 0) return error.EntropyUnavailable;
                    i += n;
                    continue;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => return syscall.fail(error.EntropyUnavailable),
            }
        }
    }

    return error.EntropyUnavailable;
}

fn getRandomFd(t: *Threaded) Io.RandomSecureError!posix.fd_t {
    {
        mutexLock(&t.mutex);
        defer mutexUnlock(&t.mutex);

        if (t.random_file.fd == -2) return error.EntropyUnavailable;
        if (t.random_file.fd != -1) return t.random_file.fd;
    }

    const mode: posix.mode_t = 0;

    const fd: posix.fd_t = fd: {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = openat_sym(posix.AT.FDCWD, "/dev/urandom", .{
                .ACCMODE = .RDONLY,
                .CLOEXEC = true,
            }, mode);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    break :fd @intCast(rc);
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => return syscall.fail(error.EntropyUnavailable),
            }
        }
    };
    errdefer closeFd(fd);

    switch (native_os) {
        .linux => {
            const sys = if (statx_use_c) std.c else std.os.linux;
            const syscall: Syscall = try .start();
            while (true) {
                var statx = std.mem.zeroes(std.os.linux.Statx);
                switch (sys.errno(sys.statx(fd, "", std.os.linux.AT.EMPTY_PATH, .{ .TYPE = true }, &statx))) {
                    .SUCCESS => {
                        syscall.finish();
                        if (!statx.mask.TYPE) return error.EntropyUnavailable;
                        mutexLock(&t.mutex); // Another thread might have won the race.
                        defer mutexUnlock(&t.mutex);
                        if (t.random_file.fd >= 0) {
                            closeFd(fd);
                            return t.random_file.fd;
                        } else if (!posix.S.ISCHR(statx.mode)) {
                            t.random_file.fd = -2;
                            return error.EntropyUnavailable;
                        } else {
                            t.random_file.fd = fd;
                            return fd;
                        }
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => return syscall.fail(error.EntropyUnavailable),
                }
            }
        },
        else => {
            const syscall: Syscall = try .start();
            while (true) {
                var stat = std.mem.zeroes(posix.Stat);
                switch (posix.errno(fstat_sym(fd, &stat))) {
                    .SUCCESS => {
                        syscall.finish();
                        mutexLock(&t.mutex); // Another thread might have won the race.
                        defer mutexUnlock(&t.mutex);
                        if (t.random_file.fd >= 0) {
                            closeFd(fd);
                            return t.random_file.fd;
                        } else if (!posix.S.ISCHR(stat.mode)) {
                            t.random_file.fd = -2;
                            return error.EntropyUnavailable;
                        } else {
                            t.random_file.fd = fd;
                            return fd;
                        }
                    },
                    .INTR => {
                        try syscall.checkCancel();
                        continue;
                    },
                    else => return syscall.fail(error.EntropyUnavailable),
                }
            }
        },
    }
}

test {
    _ = @import("Threaded/test.zig");
}

const use_parking_futex = switch (native_os) {
    .windows => true, // RtlWaitOnAddress is a userland implementation anyway
    .netbsd => true, // NetBSD has `futex(2)`, but it's historically been quite buggy. TODO: evaluate whether it's okay to use now.
    .illumos => true, // Illumos has no futex mechanism
    else => false,
};
const use_parking_sleep = switch (native_os) {
    // On Windows, we can implement sleep either with `NtDelayExecution` (which is how `SleepEx` in
    // kernel32 works) or `NtWaitForAlertByThreadId` (thread parking). We're already using the
    // latter for futex, so we may as well use it for sleeping too, to maximise code reuse. I'm
    // also more confident that it will always correctly handle the cancelation race (so "unpark"
    // before "park" causes "park" to return immediately): it *seems* like alertable sleeps paired
    // with `NtAlertThread` do actually do this too, but there could be some caveat (e.g. it might
    // fail under some specific condition), whereas `NtWaitForAlertByThreadId` must reliably trigger
    // this behavior because `RtlWaitOnAddress` relies on it.
    .windows => true,

    // These targets have `_lwp_park`, which is superior to POSIX nanosleep because it has a better
    // cancelation mechanism.
    .netbsd,
    .illumos,
    => true,

    else => false,
};

const parking_futex = struct {
    comptime {
        assert(use_parking_futex);
    }

    const Bucket = struct {
        /// Used as a fast check for `wake` to avoid having to acquire `mutex` to discover there are no
        /// waiters. It is important for `wait` to increment this *before* checking the futex value to
        /// avoid a race.
        num_waiters: std.atomic.Value(u32),
        /// Protects `waiters`.
        mutex: ParkingMutex,
        waiters: std.DoublyLinkedList,

        /// Prevent false sharing between buckets.
        _: void align(std.atomic.cache_line) = {},

        const init: Bucket = .{ .num_waiters = .init(0), .mutex = .init, .waiters = .{} };
    };

    const Waiter = struct {
        node: std.DoublyLinkedList.Node,
        address: usize,
        tid: std.Thread.Id,
        /// `thread_status.cancelation` is `.parked` while the thread is waiting. The single thread
        /// which atomically updates it (to `.none` or `.canceling`) is responsible for:
        ///
        /// * Removing the `Waiter` from `Bucket.waiters`
        /// * Decrementing `Bucket.num_waiters`
        /// * Unparking the thread (*after* the above, so that the `Waiter` does not go out of scope
        ///   while it is still in the `Bucket`).
        thread_status: *std.atomic.Value(Thread.Status),
        unpark_flag: if (need_unpark_flag) *UnparkFlag else void,
    };

    fn bucketForAddress(address: usize) *Bucket {
        const global = struct {
            /// Length must be a power of two. The longer this array, the less likely contention is
            /// between different futexes. This length seems like it'll provide a reasonable balance
            /// between contention and memory usage: assuming a 128-byte `Bucket` (due to cache line
            /// alignment), this uses 32 KiB of memory.
            var buckets: [256]Bucket = @splat(.init);
        };

        // Here we use Fibonacci hashing: the golden ratio can be used to evenly redistribute input
        // values across a range, giving a poor, but extremely quick to compute, hash.

        // This literal is the rounded value of '2^64 / phi' (where 'phi' is the golden ratio). The
        // shift then converts it to '2^b / phi', where 'b' is the pointer bit width.
        const fibonacci_multiplier = 0x9E3779B97F4A7C15 >> (64 - @bitSizeOf(usize));
        const hashed = address *% fibonacci_multiplier;

        comptime assert(std.math.isPowerOfTwo(global.buckets.len));
        // The high bits of `hashed` have better entropy than the low bits.
        const index = hashed >> (@bitSizeOf(usize) - @ctz(global.buckets.len));

        return &global.buckets[index];
    }

    fn wait(ptr: *const u32, expect: u32, uncancelable: bool, timeout: Io.Timeout) Io.Cancelable!void {
        const bucket = bucketForAddress(@intFromPtr(ptr));

        // Put the threadlocal access outside of the critical section.
        const opt_thread = Thread.current;
        const self_tid = if (opt_thread) |thread| thread.id else std.Thread.getCurrentId();

        var waiter: Waiter = .{
            .node = undefined, // populated by list append
            .address = @intFromPtr(ptr),
            .tid = self_tid,
            .thread_status = undefined, // populated in critical section
            .unpark_flag = undefined, // populated in critical section
        };

        var status_buf: std.atomic.Value(Thread.Status) = undefined;
        var unpark_flag_buf: UnparkFlag = unpark_flag_init;

        {
            bucket.mutex.lock();
            defer bucket.mutex.unlock();

            _ = bucket.num_waiters.fetchAdd(1, .acquire);

            if (@atomicLoad(u32, ptr, .monotonic) != expect) {
                assert(bucket.num_waiters.fetchSub(1, .monotonic) > 0);
                return;
            }

            // This is in the critical section to avoid marking the thread as parked until we're
            // certain that we're actually going to park.
            waiter.thread_status, waiter.unpark_flag = status: {
                cancelable: {
                    if (uncancelable) break :cancelable;
                    const thread = opt_thread orelse break :cancelable;
                    switch (thread.cancel_protection) {
                        .blocked => break :cancelable,
                        .unblocked => {},
                    }
                    thread.futex_waiter = &waiter;
                    const old_status = thread.status.fetchOr(
                        .{ .cancelation = @enumFromInt(0b001), .awaitable = .null },
                        .release, // release `thread.futex_waiter`
                    );
                    switch (old_status.cancelation) {
                        .none => {}, // status is now `.parked`
                        .canceling => {
                            // status is now `.canceled`
                            assert(bucket.num_waiters.fetchSub(1, .monotonic) > 0);
                            return error.Canceled;
                        },
                        .canceled => break :cancelable, // status is still `.canceled`
                        .parked => unreachable,
                        .blocked => unreachable,
                        .blocked_alertable => unreachable,
                        .blocked_alertable_canceling => unreachable,
                        .blocked_canceling => unreachable,
                    }
                    // We could now be unparked for a cancelation at any time!
                    break :status .{ &thread.status, if (need_unpark_flag) &thread.unpark_flag };
                }
                // This is an uncancelable wait, so just use `status_buf`. Note that the value of
                // `status_buf.awaitable` is irrelevant because this is only visible to futex code,
                // while only cancelation cares about `awaitable`.
                status_buf.raw = .{ .cancelation = .parked, .awaitable = .null };
                break :status .{ &status_buf, if (need_unpark_flag) &unpark_flag_buf };
            };

            bucket.waiters.append(&waiter.node);
        }

        if (park(timeout, ptr, waiter.unpark_flag)) {
            // We were unparked by either `wake` or cancelation, so our current status is either
            // `.none` or `.canceling`. In either case, they've already removed `waiter` from
            // `bucket`, so we have nothing more to do!
        } else |err| switch (err) {
            error.Timeout => {
                // We're not out of the woods yet: an unpark could race with the timeout.
                const old_status = waiter.thread_status.fetchAnd(
                    .{ .cancelation = @enumFromInt(0b110), .awaitable = .all_ones },
                    .monotonic,
                );
                switch (old_status.cancelation) {
                    .parked => {
                        // No race. It is our responsibility to remove `waiter` from `bucket`.
                        // New status is `.none`.
                        bucket.mutex.lock();
                        defer bucket.mutex.unlock();
                        bucket.waiters.remove(&waiter.node);
                        assert(bucket.num_waiters.fetchSub(1, .monotonic) > 0);
                    },
                    .none, .canceling => {
                        // Race condition: the timeout was reached, then `wake` or a canceler tried
                        // to unpark us. Whoever did that will remove us from `bucket`. Wait for
                        // that (and drop the unpark request in doing so).
                        // New status is `.none` or `.canceling` respectively.
                        park(.none, ptr, waiter.unpark_flag) catch |e| switch (e) {
                            error.Timeout => unreachable,
                        };
                    },
                    .canceled => unreachable,
                    .blocked => unreachable,
                    .blocked_alertable => unreachable,
                    .blocked_canceling => unreachable,
                    .blocked_alertable_canceling => unreachable,
                }
            },
        }
    }

    fn wake(ptr: *const u32, max_waiters: u32) void {
        if (max_waiters == 0) return;

        const bucket = bucketForAddress(@intFromPtr(ptr));

        // To ensure the store to `ptr` is ordered before this check, we effectively want a `.release`
        // load, but that doesn't exist in the C11 memory model, so emulate it with a non-mutating rmw.
        if (bucket.num_waiters.fetchAdd(0, .release) == 0) {
            @branchHint(.likely);
            return; // no waiters
        }

        // Waiters removed from the linked list under the mutex so we can unpark their threads outside
        // of the critical section. This forms a singly-linked list of waiters using `Waiter.node.next`.
        var waking_head: ?*std.DoublyLinkedList.Node = null;
        {
            bucket.mutex.lock();
            defer bucket.mutex.unlock();

            var num_removed: u32 = 0;
            var it = bucket.waiters.first;
            while (num_removed < max_waiters) {
                const waiter: *Waiter = @fieldParentPtr("node", it orelse break);
                it = waiter.node.next;
                if (waiter.address != @intFromPtr(ptr)) continue;
                const old_status = waiter.thread_status.fetchAnd(
                    .{ .cancelation = @enumFromInt(0b110), .awaitable = .all_ones },
                    .monotonic,
                );
                switch (old_status.cancelation) {
                    .parked => {}, // state updated to `.none`
                    .none => continue, // race with timeout; they are about to lock `bucket.mutex` and remove themselves from the bucket
                    .canceling => continue, // race with a canceler who hasn't called `removeCanceledWaiter` yet
                    .canceled => unreachable,
                    .blocked => unreachable,
                    .blocked_alertable => unreachable,
                    .blocked_alertable_canceling => unreachable,
                    .blocked_canceling => unreachable,
                }
                // We're waking this waiter. Remove them from the bucket and add them to our local list.
                bucket.waiters.remove(&waiter.node);
                waiter.node.next = waking_head;
                waking_head = &waiter.node;
                num_removed += 1;
            }
            _ = bucket.num_waiters.fetchSub(num_removed, .monotonic);
        }

        var unpark_buf: [128]UnparkTid = undefined;
        var unpark_len: usize = 0;

        // Finally, unpark the threads.
        while (waking_head) |node| {
            waking_head = node.next;
            const waiter: *Waiter = @fieldParentPtr("node", node);
            unpark_buf[unpark_len] = waiter.tid;
            if (need_unpark_flag) setUnparkFlag(waiter.unpark_flag);
            unpark_len += 1;
            if (unpark_len == unpark_buf.len) {
                unpark(&unpark_buf, ptr);
                unpark_len = 0;
            }
        }
        if (unpark_len > 0) {
            unpark(unpark_buf[0..unpark_len], ptr);
        }
    }

    fn removeCanceledWaiter(waiter: *Waiter) void {
        const bucket = bucketForAddress(waiter.address);
        bucket.mutex.lock();
        defer bucket.mutex.unlock();
        bucket.waiters.remove(&waiter.node);
        assert(bucket.num_waiters.fetchSub(1, .monotonic) > 0);
    }
};
const parking_sleep = struct {
    comptime {
        assert(use_parking_sleep);
    }
    fn sleep(timeout: Io.Timeout) Io.Cancelable!void {
        const opt_thread = Thread.current;
        cancelable: {
            const thread = opt_thread orelse break :cancelable;
            switch (thread.cancel_protection) {
                .blocked => break :cancelable,
                .unblocked => {},
            }
            thread.futex_waiter = null;
            {
                const old_status = thread.status.fetchOr(
                    .{ .cancelation = @enumFromInt(0b001), .awaitable = .null },
                    .release, // release `thread.futex_waiter`
                );
                switch (old_status.cancelation) {
                    .none => {}, // status is now `.parked`
                    .canceling => return error.Canceled, // status is now `.canceled`
                    .canceled => break :cancelable, // status is still `.canceled`
                    .parked => unreachable,
                    .blocked => unreachable,
                    .blocked_alertable => unreachable,
                    .blocked_alertable_canceling => unreachable,
                    .blocked_canceling => unreachable,
                }
            }
            if (park(timeout, null, if (need_unpark_flag) &thread.unpark_flag)) {
                // The only reason this could possibly happen is cancelation.
                const old_status = thread.status.load(.monotonic);
                assert(old_status.cancelation == .canceling);
                thread.status.store(
                    .{ .cancelation = .canceled, .awaitable = old_status.awaitable },
                    .monotonic,
                );
                return error.Canceled;
            } else |err| switch (err) {
                error.Timeout => {
                    // We're not out of the woods yet: an unpark could race with the timeout.
                    const old_status = thread.status.fetchAnd(
                        .{ .cancelation = @enumFromInt(0b110), .awaitable = .all_ones },
                        .monotonic,
                    );
                    switch (old_status.cancelation) {
                        .parked => return, // No race; new status is `.none`
                        .canceling => {
                            // Race condition: the timeout was reached, then someone tried to unpark
                            // us for a cancelation. Whoever did that will have called `unpark`, so
                            // drop that unpark request by waiting for it.
                            // Status is still `.canceling`.
                            park(.none, null, if (need_unpark_flag) &thread.unpark_flag) catch |e| switch (e) {
                                error.Timeout => unreachable,
                            };
                            return;
                        },
                        .none => unreachable,
                        .canceled => unreachable,
                        .blocked => unreachable,
                        .blocked_alertable => unreachable,
                        .blocked_canceling => unreachable,
                        .blocked_alertable_canceling => unreachable,
                    }
                },
            }
        }
        // Uncancelable sleep; we expect not to be manually unparked.
        var dummy_flag: UnparkFlag = unpark_flag_init;
        if (park(timeout, null, if (need_unpark_flag) &dummy_flag)) {
            unreachable; // unexpected unpark
        } else |err| switch (err) {
            error.Timeout => return,
        }
    }
};
const ParkingMutex = struct {
    state: std.atomic.Value(State),

    const init: ParkingMutex = .{ .state = .init(.unlocked) };

    comptime {
        assert(use_parking_futex);
    }

    const State = enum(usize) {
        unlocked = 1,
        /// This value is intentionally 0 so that `waiter` returns `null`.
        locked_once = 0,
        /// Contended; value is a `*Waiter`.
        _,
        /// Returns the head of the waiter list. Illegal to call if `s == .unlocked`.
        fn waiter(s: State) ?*Waiter {
            return @ptrFromInt(@intFromEnum(s));
        }
        /// Returns a locked state where `w` is contending the lock.
        /// If `w` is `null`, returns `.locked_once`.
        fn fromWaiter(w: ?*Waiter) State {
            return @enumFromInt(@intFromPtr(w));
        }
    };
    const Waiter = struct {
        unpark_flag: UnparkFlag,
        /// Never modified once the `Waiter` is in the linked list.
        next: ?*Waiter,
        /// Never modified once the `Waiter` is in the linked list.
        tid: std.Thread.Id,
    };
    fn lock(m: *ParkingMutex) void {
        state: switch (State.unlocked) { // assume 'unlocked' to optimize for uncontended case
            .unlocked => continue :state m.state.cmpxchgWeak(
                .unlocked,
                .locked_once,
                .acquire, // acquire lock
                .monotonic,
            ) orelse {
                @branchHint(.likely);
                return;
            },

            .locked_once, _ => |last_state| {
                const old_waiter = last_state.waiter();
                const self_tid = if (Thread.current) |t| t.id else std.Thread.getCurrentId();
                var waiter: Waiter = .{
                    .next = old_waiter,
                    .unpark_flag = unpark_flag_init,
                    .tid = self_tid,
                };
                if (m.state.cmpxchgWeak(
                    .fromWaiter(old_waiter),
                    .fromWaiter(&waiter),
                    .release, // release `waiter`
                    .monotonic,
                )) |new_state| {
                    continue :state new_state;
                }
                // We're now in the list of waiters---park until we're given the lock.
                park(.none, m, if (need_unpark_flag) &waiter.unpark_flag) catch |err| switch (err) {
                    error.Timeout => unreachable,
                };
                return;
            },
        }
    }
    fn unlock(m: *ParkingMutex) void {
        state: switch (State.locked_once) { // assume 'locked_once' to optimize for uncontended case
            .unlocked => unreachable, // we hold the lock

            .locked_once => continue :state m.state.cmpxchgWeak(
                .locked_once,
                .unlocked,
                .release, // release lock
                .acquire, // acquire any `Waiter` memory
            ) orelse {
                @branchHint(.likely);
                return;
            },

            _ => |last_state| {
                // The logic here does not have ABA problems, and does some accesses non-atomically,
                // because `Waiter.next` is owned by the lock holder (that's us!) once the waiter is
                // in the linked list, up until we unpark the waiter.

                // Run through the waiter list to the end to ensure fairness. This is obviously not
                // ideal, but it shouldn't be a big deal in practice provided the critical section
                // is fairly small (so we won't get too many threads contending the mutex at once).
                // There's a *chance* we could get away with a LIFO queue for our use case, but I
                // don't wanna risk that.
                var parent: ?*Waiter = null;
                var waiter: *Waiter = last_state.waiter().?;
                while (waiter.next) |next| {
                    parent = waiter;
                    waiter = next;
                }
                // `waiter` is next in line for the lock. Remove them from the list.
                if (parent) |p| {
                    assert(p.next == waiter);
                    p.next = null;
                } else {
                    // We're waking the last waiter, so clear the list head.
                    if (m.state.cmpxchgWeak(
                        .fromWaiter(last_state.waiter().?),
                        .locked_once,
                        .acquire,
                        .acquire, // acquire any new `Waiter` memory
                    )) |new_state| {
                        continue :state new_state;
                    }
                }
                // Now we're ready to actually hand the lock over to them.
                const tid = waiter.tid; // load before the unpark below potentially invalidates `waiter`
                if (need_unpark_flag) setUnparkFlag(&waiter.unpark_flag);
                unpark(&.{tid}, m);
                return;
            },
        }
    }
};

fn timeoutToWindowsInterval(timeout: Io.Timeout) ?windows.LARGE_INTEGER {
    // ntdll only supports two combinations:
    // * real-time (`.real`) sleeps with absolute deadlines
    // * monotonic (`.awake`/`.boot`) sleeps with relative durations
    const clock = switch (timeout) {
        .none => return null,
        .duration => |d| d.clock,
        .deadline => |d| d.clock,
    };
    switch (clock) {
        .cpu_process, .cpu_thread => unreachable, // cannot sleep for CPU time
        .real => {
            const deadline = switch (timeout) {
                .none => unreachable,
                .duration => |d| nowWindows(clock).addDuration(d.raw),
                .deadline => |d| d.raw,
            };
            const epoch_ns = std.time.epoch.windows * std.time.ns_per_s;
            return @intCast(@max(@divTrunc(deadline.nanoseconds - epoch_ns, 100), 0));
        },
        .awake, .boot => {
            const duration = switch (timeout) {
                .none => unreachable,
                .duration => |d| d.raw,
                .deadline => |d| nowWindows(clock).durationTo(d.raw),
            };
            return @intCast(@min(@divTrunc(-duration.nanoseconds, 100), -1));
        },
    }
}

/// The API on NetBSD and Illumos sucks and can unpark spuriously (well, it *can't*, but signals
/// cause an indistinguishable unblock, and libpthread really likes to leave unparks pending).
/// As such, on these targets only, we need to pass around a flag to track whether a thread is
/// "actually" being unparked.
const need_unpark_flag = switch (native_os) {
    .netbsd, .illumos => true,
    else => false,
};
const UnparkFlag = if (need_unpark_flag) std.atomic.Value(bool) else void;
const unpark_flag_init: UnparkFlag = if (need_unpark_flag) .init(false);
/// Must be called before `unpark`. After this function is called, the thread may be unparked at any
/// time, so the caller must not reference values on its stack.
fn setUnparkFlag(f: *UnparkFlag) void {
    f.store(true, .release);
}

/// The type passed into `unpark` for the thread ID. You'd think this was just a `std.Thread.Id`,
/// but it seems that someone at Microsoft forgot how big their TIDs are supposed to be.
const UnparkTid = switch (native_os) {
    .windows => usize,
    else => std.Thread.Id,
};

fn park(
    timeout: Io.Timeout,
    /// This value has no semantic effect, but may allow the OS to optimize the operation.
    addr_hint: ?*const anyopaque,
    unpark_flag: if (need_unpark_flag) *UnparkFlag else void,
) error{Timeout}!void {
    comptime assert(use_parking_futex or use_parking_sleep);
    switch (native_os) {
        .windows => {
            const raw_timeout = timeoutToWindowsInterval(timeout);
            // `RtlWaitOnAddress` passes the futex address in as the first argument to this call,
            // but it's unclear what that actually does, especially since `NtAlertThreadByThreadId`
            // does *not* accept the address so the kernel can't really be using it as a hint. An
            // old Microsoft blog post discusses a more traditional futex-like mechanism in the
            // kernel which definitely isn't how `RtlWaitOnAddress` works today:
            //
            // https://devblogs.microsoft.com/oldnewthing/20160826-00/?p=94185
            //
            // ...so it's possible this argument is simply a remnant which no longer does anything
            // (perhaps the implementation changed during development but someone forgot to remove
            // this parameter). However, to err on the side of caution, let's match the behavior of
            // `RtlWaitOnAddress` and pass the pointer, in case the kernel ever does something
            // stupid such as trying to dereference it.
            switch (windows.ntdll.NtWaitForAlertByThreadId(
                addr_hint,
                if (raw_timeout) |*t| t else null,
            )) {
                .ALERTED => return,
                .TIMEOUT => return error.Timeout,
                else => unreachable,
            }
        },
        .netbsd => {
            var ts_buf: posix.timespec = undefined;
            const ts: ?*posix.timespec, const abstime: bool, const clock_real: bool = switch (timeout) {
                .none => .{ null, false, false },
                .deadline => |timestamp| timeout: {
                    ts_buf = timestampToPosix(timestamp.raw.nanoseconds);
                    break :timeout .{ &ts_buf, true, timestamp.clock == .real };
                },
                .duration => |duration| timeout: {
                    ts_buf = timestampToPosix(duration.raw.nanoseconds);
                    break :timeout .{ &ts_buf, false, duration.clock == .real };
                },
            };
            // It's okay to pass the same timeout in a loop. If it's a duration, the OS actually
            // writes the remaining time into the buffer when the syscall returns.
            while (!unpark_flag.swap(false, .acquire)) {
                switch (posix.errno(std.c._lwp_park(
                    if (clock_real) .REALTIME else .MONOTONIC,
                    .{ .ABSTIME = abstime },
                    ts,
                    0,
                    addr_hint,
                    null,
                ))) {
                    .SUCCESS, .ALREADY, .INTR => {},
                    .TIMEDOUT => return error.Timeout,
                    .INVAL => unreachable,
                    .SRCH => unreachable,
                    else => unreachable,
                }
            }
        },
        .illumos => @panic("TODO: illumos lwp_park"),
        else => comptime unreachable,
    }
}
/// `addr_hint` has no semantic effect, but may allow the OS to optimize this operation.
fn unpark(tids: []const UnparkTid, addr_hint: ?*const anyopaque) void {
    comptime assert(use_parking_futex or use_parking_sleep);
    switch (native_os) {
        .windows => {
            // TODO: this condition is currently disabled because mingw-w64 does not contain this
            // symbol. Once it's added, enable this check to use the new bulk API where possible.
            if (false and (builtin.os.version_range.windows.isAtLeast(.win11_dt) orelse false)) {
                _ = windows.ntdll.NtAlertMultipleThreadByThreadId(tids.ptr, @intCast(tids.len), null, null);
            } else {
                for (tids) |tid| {
                    _ = windows.ntdll.NtAlertThreadByThreadId(@intCast(tid));
                }
            }
        },
        .netbsd => {
            switch (posix.errno(std.c._lwp_unpark_all(@ptrCast(tids.ptr), tids.len, addr_hint))) {
                .SUCCESS => return,
                // For errors, fall through to a loop over `tids`, though this is only expected to
                // be possible for ENOMEM (even that is questionable) and ESRCH (see comment below).
                .SRCH => {},
                .FAULT => recoverableOsBugDetected(),
                .INVAL => recoverableOsBugDetected(),
                .NOMEM => {},
                else => recoverableOsBugDetected(),
            }
            for (tids) |tid| {
                switch (posix.errno(std.c._lwp_unpark(@bitCast(tid), addr_hint))) {
                    .SUCCESS => {},
                    .SRCH => {
                        // This can happen in a rare race: the thread might have been spuriously
                        // unparked, so already observed the changing status, and from there have
                        // exited. That's okay, because the thread has woken up like we wanted.
                    },
                    else => recoverableOsBugDetected(),
                }
            }
        },
        .illumos => @panic("TODO: illumos lwp_unpark"),
        else => comptime unreachable,
    }
}

pub const PipeError = error{
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
} || Io.UnexpectedError;

pub fn pipe2(flags: posix.O) PipeError![2]posix.fd_t {
    var fds: [2]posix.fd_t = undefined;

    if (@TypeOf(posix.system.pipe2) != void) {
        switch (posix.errno(posix.system.pipe2(&fds, flags))) {
            .SUCCESS => return fds,
            .INVAL => |err| return errnoBug(err), // Invalid flags
            .NFILE => return error.SystemFdQuotaExceeded,
            .MFILE => return error.ProcessFdQuotaExceeded,
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    switch (posix.errno(posix.system.pipe(&fds))) {
        .SUCCESS => {},
        .NFILE => return error.SystemFdQuotaExceeded,
        .MFILE => return error.ProcessFdQuotaExceeded,
        else => |err| return posix.unexpectedErrno(err),
    }
    errdefer {
        closeFd(fds[0]);
        closeFd(fds[1]);
    }

    // https://github.com/ziglang/zig/issues/18882
    if (@as(u32, @bitCast(flags)) == 0) return fds;

    // CLOEXEC is special, it's a file descriptor flag and must be set using
    // F.SETFD.
    if (flags.CLOEXEC) for (fds) |fd| {
        switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(u32, posix.FD_CLOEXEC)))) {
            .SUCCESS => {},
            else => |err| return posix.unexpectedErrno(err),
        }
    };

    const new_flags: u32 = f: {
        var new_flags = flags;
        new_flags.CLOEXEC = false;
        break :f @bitCast(new_flags);
    };

    // Set every other flag affecting the file status using F.SETFL.
    if (new_flags != 0) for (fds) |fd| {
        switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, new_flags))) {
            .SUCCESS => {},
            .INVAL => |err| return errnoBug(err),
            else => |err| return posix.unexpectedErrno(err),
        }
    };

    return fds;
}

pub const DupError = error{
    ProcessFdQuotaExceeded,
    SystemResources,
} || Io.UnexpectedError || Io.Cancelable;

pub fn dup2(old_fd: posix.fd_t, new_fd: posix.fd_t) DupError!void {
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.dup2(old_fd, new_fd))) {
        .SUCCESS => return syscall.finish(),
        .BUSY, .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .INVAL => |err| return syscall.errnoBug(err), // invalid parameters
        .BADF => |err| return syscall.errnoBug(err), // use after free
        .MFILE => return syscall.fail(error.ProcessFdQuotaExceeded),
        .NOMEM => return syscall.fail(error.SystemResources),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

pub const FchdirError = error{
    AccessDenied,
    NotDir,
    FileSystem,
} || Io.Cancelable || Io.UnexpectedError;

pub fn fchdir(fd: posix.fd_t) FchdirError!void {
    if (fd == posix.AT.FDCWD) return;
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.fchdir(fd))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ACCES => return syscall.fail(error.AccessDenied),
        .NOTDIR => return syscall.fail(error.NotDir),
        .IO => return syscall.fail(error.FileSystem),
        .BADF => |err| return syscall.errnoBug(err),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

pub const ChdirError = error{
    AccessDenied,
    FileSystem,
    SymLinkLoop,
    NameTooLong,
    FileNotFound,
    SystemResources,
    NotDir,
    BadPathName,
} || Io.Cancelable || Io.UnexpectedError;

pub fn chdir(dir_path: []const u8) ChdirError!void {
    var path_buffer: [posix.PATH_MAX]u8 = undefined;
    const dir_path_posix = try pathToPosix(dir_path, &path_buffer);
    const syscall: Syscall = try .start();
    while (true) switch (posix.errno(posix.system.chdir(dir_path_posix))) {
        .SUCCESS => return syscall.finish(),
        .INTR => {
            try syscall.checkCancel();
            continue;
        },
        .ACCES => return syscall.fail(error.AccessDenied),
        .IO => return syscall.fail(error.FileSystem),
        .LOOP => return syscall.fail(error.SymLinkLoop),
        .NAMETOOLONG => return syscall.fail(error.NameTooLong),
        .NOENT => return syscall.fail(error.FileNotFound),
        .NOMEM => return syscall.fail(error.SystemResources),
        .NOTDIR => return syscall.fail(error.NotDir),
        .ILSEQ => return syscall.fail(error.BadPathName),
        .FAULT => |err| return syscall.errnoBug(err),
        else => |err| return syscall.unexpectedErrno(err),
    };
}

fn fileMemoryMapCreate(
    userdata: ?*anyopaque,
    file: File,
    options: File.MemoryMap.CreateOptions,
) File.MemoryMap.CreateError!File.MemoryMap {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const offset = options.offset;
    const len = options.len;

    if (!t.disable_memory_mapping) {
        if (createFileMap(file, options.protection, offset, options.populate, len)) |result| {
            return result;
        } else |err| switch (err) {
            error.Unseekable, error.Canceled, error.AccessDenied => |e| return e,
            error.OperationUnsupported => {},
            else => {
                if (builtin.mode == .Debug)
                    std.log.warn("memory mapping failed with {t}, falling back to file operations", .{err});
            },
        }
    }

    const gpa = t.allocator;
    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const memory = m: {
        const ptr = gpa.rawAlloc(len, alignment, @returnAddress()) orelse return error.OutOfMemory;
        break :m ptr[0..len];
    };
    errdefer gpa.rawFree(memory, alignment, @returnAddress());

    if (!options.undefined_contents) try mmSyncRead(file, memory, offset);

    return .{
        .file = file,
        .offset = offset,
        .memory = @alignCast(memory),
        .section = null,
    };
}

const CreateFileMapError = error{
    /// MaximumSize is greater than the system-defined maximum for sections, or
    /// greater than the specified file and the section is not writable.
    SectionOversize,
    /// A file descriptor refers to a non-regular file. Or a file mapping was requested,
    /// but the file descriptor is not open for reading. Or `MAP.SHARED` was requested
    /// and `PROT_WRITE` is set, but the file descriptor is not open in `RDWR` mode.
    /// Or `PROT_WRITE` is set, but the file is append-only.
    AccessDenied,
    /// The `prot` argument asks for `PROT_EXEC` but the mapped area belongs to a file on
    /// a filesystem that was mounted no-exec.
    PermissionDenied,
    FileBusy,
    LockedMemoryLimitExceeded,
    OperationUnsupported,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    OutOfMemory,
    MappingAlreadyExists,
    Unseekable,
    LockViolation,
} || Io.Cancelable || Io.UnexpectedError;

fn createFileMap(
    file: File,
    protection: std.process.MemoryProtection,
    offset: u64,
    populate: bool,
    len: usize,
) CreateFileMapError!File.MemoryMap {
    if (is_windows) {
        try Thread.checkCancel();

        var section = windows.INVALID_HANDLE_VALUE;
        const section_size: windows.LARGE_INTEGER = @intCast(len);
        const page = windows.PAGE.fromProtection(protection) orelse return error.AccessDenied;
        switch (windows.ntdll.NtCreateSection(
            &section,
            .{
                .SPECIFIC = .{ .SECTION = .{
                    .QUERY = true,
                    .MAP_WRITE = protection.write,
                    .MAP_READ = protection.read,
                    .MAP_EXECUTE = protection.execute,
                    .EXTEND_SIZE = true,
                } },
                .STANDARD = .{ .RIGHTS = .REQUIRED },
            },
            null,
            &section_size,
            page,
            .{ .COMMIT = populate },
            file.handle,
        )) {
            .SUCCESS => {},
            .FILE_LOCK_CONFLICT => return error.LockViolation,
            .INVALID_FILE_FOR_SECTION => return error.OperationUnsupported,
            .ACCESS_DENIED => return error.AccessDenied,
            .SECTION_TOO_BIG => return error.SectionOversize,
            else => |status| return windows.unexpectedStatus(status),
        }
        var contents_ptr: ?[*]align(std.heap.page_size_min) u8 = null;
        var contents_len = len;
        switch (windows.ntdll.NtMapViewOfSection(
            section,
            windows.current_process,
            @ptrCast(&contents_ptr),
            null,
            0,
            null,
            &contents_len,
            .Unmap,
            .{},
            page,
        )) {
            .SUCCESS => {},
            .CONFLICTING_ADDRESSES => return error.MappingAlreadyExists,
            .SECTION_PROTECTION => return error.PermissionDenied,
            .ACCESS_DENIED => return error.AccessDenied,
            .INVALID_VIEW_SIZE => |status| return windows.statusBug(status),
            else => |status| return windows.unexpectedStatus(status),
        }
        if (builtin.mode == .Debug) {
            const page_size = std.heap.pageSize();
            const alignment: Alignment = .fromByteUnits(page_size);
            assert(contents_len == alignment.forward(len));
        }
        return .{
            .file = file,
            .offset = offset,
            .memory = contents_ptr.?[0..len],
            .section = section,
        };
    } else if (have_mmap) {
        const prot: posix.PROT = .{
            .READ = protection.read,
            .WRITE = protection.write,
            .EXEC = protection.execute,
        };
        const flags: posix.MAP = switch (native_os) {
            .linux => .{
                .TYPE = .SHARED_VALIDATE,
                .POPULATE = populate,
            },
            else => .{
                .TYPE = .SHARED,
            },
        };

        const page_align = std.heap.page_size_min;

        const contents = while (true) {
            const syscall: Syscall = try .start();
            const casted_offset = std.math.cast(i64, offset) orelse return error.Unseekable;
            const rc = mmap_sym(null, len, prot, flags, file.handle, casted_offset);
            syscall.finish();
            const err: posix.E = if (builtin.link_libc) e: {
                if (rc != std.c.MAP_FAILED) {
                    break @as([*]align(page_align) u8, @ptrCast(@alignCast(rc)))[0..len];
                }
                break :e @enumFromInt(posix.system._errno().*);
            } else e: {
                const err = posix.errno(rc);
                if (err == .SUCCESS) {
                    break @as([*]align(page_align) u8, @ptrFromInt(rc))[0..len];
                }
                break :e err;
            };
            switch (err) {
                .SUCCESS => unreachable,
                .INTR => continue,
                .ACCES => return error.AccessDenied,
                .AGAIN => return error.LockedMemoryLimitExceeded,
                .EXIST => return error.MappingAlreadyExists,
                .MFILE => return error.ProcessFdQuotaExceeded,
                .NFILE => return error.SystemFdQuotaExceeded,
                .NODEV => return error.OperationUnsupported,
                .NOMEM => return error.OutOfMemory,
                .PERM => return error.PermissionDenied,
                .TXTBSY => return error.FileBusy,
                .OVERFLOW => return error.Unseekable,
                .BADF => return errnoBug(err), // Always a race condition.
                .INVAL => return errnoBug(err), // Invalid parameters to mmap()
                .OPNOTSUPP => return errnoBug(err), // Bad flags with MAP.SHARED_VALIDATE on Linux.
                else => return posix.unexpectedErrno(err),
            }
        };
        return .{
            .file = file,
            .offset = offset,
            .memory = contents,
            .section = {},
        };
    }

    return error.OperationUnsupported;
}

fn fileMemoryMapDestroy(userdata: ?*anyopaque, mm: *File.MemoryMap) void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const memory = mm.memory;
    if (mm.section) |section| switch (native_os) {
        .windows => {
            if (section == windows.INVALID_HANDLE_VALUE) return;
            _ = windows.ntdll.NtUnmapViewOfSection(windows.current_process, memory.ptr);
            windows.CloseHandle(section);
        },
        .wasi => unreachable,
        else => {
            if (memory.len == 0) return;
            switch (posix.errno(posix.system.munmap(memory.ptr, memory.len))) {
                .SUCCESS => {},
                else => |e| {
                    if (builtin.mode == .Debug)
                        std.log.err("failed to unmap {d} bytes at {*}: {t}", .{ memory.len, memory.ptr, e });
                },
            }
        },
    } else {
        const gpa = t.allocator;
        gpa.rawFree(memory, .fromByteUnits(std.heap.pageSize()), @returnAddress());
    }
    mm.* = undefined;
}

fn fileMemoryMapSetLength(
    userdata: ?*anyopaque,
    mm: *File.MemoryMap,
    new_len: usize,
) File.MemoryMap.SetLengthError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    const page_size = std.heap.pageSize();
    const alignment: Alignment = .fromByteUnits(page_size);
    const page_align = std.heap.page_size_min;
    const old_memory = mm.memory;

    if (mm.section) |section| {
        _ = section;
        if (alignment.forward(new_len) == alignment.forward(old_memory.len)) {
            mm.memory.len = new_len;
            return;
        }
        switch (native_os) {
            .wasi => unreachable,
            .linux => {
                const flags: posix.MREMAP = .{ .MAYMOVE = true };
                const addr_hint: ?[*]const u8 = null;
                const new_memory = while (true) {
                    const syscall: Syscall = try .start();
                    const rc = posix.system.mremap(old_memory.ptr, old_memory.len, new_len, flags, addr_hint);
                    syscall.finish();
                    const err: posix.E = if (builtin.link_libc) e: {
                        if (rc != std.c.MAP_FAILED) break @as([*]align(page_align) u8, @ptrCast(@alignCast(rc)))[0..new_len];
                        break :e @enumFromInt(posix.system._errno().*);
                    } else e: {
                        const err = posix.errno(rc);
                        if (err == .SUCCESS) break @as([*]align(page_align) u8, @ptrFromInt(rc))[0..new_len];
                        break :e err;
                    };
                    switch (err) {
                        .SUCCESS => unreachable,
                        .INTR => continue,
                        .AGAIN => return error.LockedMemoryLimitExceeded,
                        .NOMEM => return error.OutOfMemory,
                        .INVAL => return errnoBug(err),
                        .FAULT => return errnoBug(err),
                        else => return posix.unexpectedErrno(err),
                    }
                };
                mm.memory = new_memory;
                return;
            },
            else => return error.OperationUnsupported,
        }
    } else {
        const gpa = t.allocator;
        if (gpa.rawRemap(old_memory, alignment, new_len, @returnAddress())) |new_ptr| {
            mm.memory = @alignCast(new_ptr[0..new_len]);
        } else {
            const new_ptr: [*]align(page_align) u8 = @alignCast(
                gpa.rawAlloc(new_len, alignment, @returnAddress()) orelse return error.OutOfMemory,
            );
            const copy_len = @min(new_len, old_memory.len);
            @memcpy(new_ptr[0..copy_len], old_memory[0..copy_len]);
            mm.memory = new_ptr[0..new_len];
            gpa.rawFree(old_memory, alignment, @returnAddress());
        }
    }
}

fn fileMemoryMapRead(userdata: ?*anyopaque, mm: *File.MemoryMap) File.ReadPositionalError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const section = mm.section orelse return mmSyncRead(mm.file, mm.memory, mm.offset);
    _ = section;
}

fn fileMemoryMapWrite(userdata: ?*anyopaque, mm: *File.MemoryMap) File.WritePositionalError!void {
    const t: *Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    const section = mm.section orelse return mmSyncWrite(mm.file, mm.memory, mm.offset);
    _ = section;
}

fn mmSyncRead(file: File, memory: []u8, offset: u64) File.ReadPositionalError!void {
    if (is_windows) {
        var i: usize = 0;
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) break;
            const n = try readFilePositionalWindows(file, buf, offset + i);
            if (n == 0) {
                @memset(memory[i..], 0);
                break;
            }
            i += n;
        }
    } else if (native_os == .wasi and !builtin.link_libc) {
        var i: usize = 0;
        const syscall: Syscall = try .start();
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) {
                syscall.finish();
                break;
            }
            var n: usize = undefined;
            const vec: std.os.wasi.iovec_t = .{ .base = buf.ptr, .len = buf.len };
            switch (std.os.wasi.fd_pread(file.handle, (&vec)[0..1], 1, offset + i, &n)) {
                .SUCCESS => {
                    if (n == 0) {
                        syscall.finish();
                        @memset(memory[i..], 0);
                        break;
                    }
                    i += n;
                    try syscall.checkCancel();
                    continue;
                },
                .INTR, .TIMEDOUT => {
                    try syscall.checkCancel();
                    continue;
                },
                .NOTCONN => |err| return syscall.errnoBug(err), // not a socket
                .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
                .BADF => |err| return syscall.errnoBug(err), // use after free
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err), // segmentation fault
                .AGAIN => |err| return syscall.errnoBug(err),
                .IO => return syscall.fail(error.InputOutput),
                .ISDIR => return syscall.fail(error.IsDir),
                .NOBUFS => return syscall.fail(error.SystemResources),
                .NOMEM => return syscall.fail(error.SystemResources),
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                .NOTCAPABLE => return syscall.fail(error.AccessDenied),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    } else {
        var i: usize = 0;
        const syscall: Syscall = try .start();
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) {
                syscall.finish();
                break;
            }
            const rc = pread_sym(file.handle, buf.ptr, buf.len, @intCast(offset + i));
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    const n: usize = @intCast(rc);
                    if (n == 0) {
                        syscall.finish();
                        @memset(memory[i..], 0);
                        break;
                    }
                    i += n;
                    try syscall.checkCancel();
                    continue;
                },
                .INTR, .TIMEDOUT => {
                    try syscall.checkCancel();
                    continue;
                },
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                .NOBUFS => return syscall.fail(error.SystemResources),
                .NOMEM => return syscall.fail(error.SystemResources),
                .AGAIN => return syscall.fail(error.WouldBlock),
                .IO => return syscall.fail(error.InputOutput),
                .ISDIR => return syscall.fail(error.IsDir),
                .NOTCONN => |err| return syscall.errnoBug(err), // not a socket
                .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err),
                .BADF => |err| return syscall.errnoBug(err), // use after free
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }
}

fn mmSyncWrite(file: File, memory: []u8, offset: u64) File.WritePositionalError!void {
    if (is_windows) {
        var i: usize = 0;
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) break;
            i += try writeFilePositionalWindows(file, memory[i..], offset + i);
        }
    } else if (native_os == .wasi and !builtin.link_libc) {
        var i: usize = 0;
        var n: usize = undefined;
        const syscall: Syscall = try .start();
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) {
                syscall.finish();
                break;
            }
            const iovec: std.os.wasi.ciovec_t = .{ .base = buf.ptr, .len = buf.len };
            switch (std.os.wasi.fd_pwrite(file.handle, (&iovec)[0..1], 1, offset + i, &n)) {
                .SUCCESS => {
                    i += n;
                    try syscall.checkCancel();
                    continue;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .DQUOT => return syscall.fail(error.DiskQuota),
                .FBIG => return syscall.fail(error.FileTooBig),
                .IO => return syscall.fail(error.InputOutput),
                .NOSPC => return syscall.fail(error.NoSpaceLeft),
                .PERM => return syscall.fail(error.PermissionDenied),
                .PIPE => return syscall.fail(error.BrokenPipe),
                .NOTCAPABLE => return syscall.fail(error.AccessDenied),
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err),
                .AGAIN => |err| return syscall.errnoBug(err),
                .BADF => |err| return syscall.errnoBug(err), // use after free
                .DESTADDRREQ => |err| return syscall.errnoBug(err), // not a socket
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    } else {
        var i: usize = 0;
        const syscall: Syscall = try .start();
        while (true) {
            const buf = memory[i..];
            if (buf.len == 0) {
                syscall.finish();
                break;
            }
            const rc = pwrite_sym(file.handle, buf.ptr, buf.len, @intCast(offset + i));
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    const n: usize = @bitCast(rc);
                    i += n;
                    try syscall.checkCancel();
                    continue;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                .INVAL => |err| return syscall.errnoBug(err),
                .FAULT => |err| return syscall.errnoBug(err),
                .DESTADDRREQ => |err| return syscall.errnoBug(err), // not a socket
                .CONNRESET => |err| return syscall.errnoBug(err), // not a socket
                .BADF => return syscall.fail(error.NotOpenForWriting),
                .AGAIN => return syscall.fail(error.WouldBlock),
                .DQUOT => return syscall.fail(error.DiskQuota),
                .FBIG => return syscall.fail(error.FileTooBig),
                .IO => return syscall.fail(error.InputOutput),
                .NOSPC => return syscall.fail(error.NoSpaceLeft),
                .PERM => return syscall.fail(error.PermissionDenied),
                .PIPE => return syscall.fail(error.BrokenPipe),
                .BUSY => return syscall.fail(error.DeviceBusy),
                .TXTBSY => return syscall.fail(error.FileBusy),
                .NXIO => return syscall.fail(error.Unseekable),
                .SPIPE => return syscall.fail(error.Unseekable),
                .OVERFLOW => return syscall.fail(error.Unseekable),
                else => |err| return syscall.unexpectedErrno(err),
            }
        }
    }
}

fn deviceIoControl(o: *const Io.Operation.DeviceIoControl) Io.Cancelable!Io.Operation.DeviceIoControl.Result {
    if (is_windows) {
        const NtControlFile = switch (o.code.DeviceType) {
            .FILE_SYSTEM, .NAMED_PIPE => &windows.ntdll.NtFsControlFile,
            else => &windows.ntdll.NtDeviceIoControlFile,
        };
        var iosb: windows.IO_STATUS_BLOCK = undefined;
        if (o.file.flags.nonblocking) {
            var done: bool = false;
            switch (NtControlFile(
                o.file.handle,
                null, // event
                flagApc,
                &done, // APC context
                &iosb,
                o.code,
                if (o.in.len > 0) o.in.ptr else null,
                @intCast(o.in.len),
                if (o.out.len > 0) o.out.ptr else null,
                @intCast(o.out.len),
            )) {
                // We must wait for the APC routine.
                .PENDING, .SUCCESS => while (!done) {
                    // Once we get here we must not return from the function until the
                    // operation completes, thereby releasing reference to io_status_block.
                    const alertable_syscall = AlertableSyscall.start() catch |err| switch (err) {
                        error.Canceled => |e| {
                            var cancel_iosb: windows.IO_STATUS_BLOCK = undefined;
                            _ = windows.ntdll.NtCancelIoFileEx(o.file.handle, &iosb, &cancel_iosb);
                            while (!done) waitForApcOrAlert();
                            return e;
                        },
                    };
                    waitForApcOrAlert();
                    alertable_syscall.finish();
                },
                else => |status| iosb.u.Status = status,
            }
        } else {
            const syscall: Syscall = try .start();
            while (true) switch (NtControlFile(
                o.file.handle,
                null, // event
                null, // APC routine
                null, // APC context
                &iosb,
                o.code,
                if (o.in.len > 0) o.in.ptr else null,
                @intCast(o.in.len),
                if (o.out.len > 0) o.out.ptr else null,
                @intCast(o.out.len),
            )) {
                .PENDING => unreachable, // unrecoverable: wrong asynchronous flag
                .CANCELLED => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |status| {
                    syscall.finish();
                    iosb.u.Status = status;
                    break;
                },
            };
        }
        return iosb;
    } else {
        const syscall: Syscall = try .start();
        while (true) {
            const rc = posix.system.ioctl(o.file.handle, @bitCast(o.code), @intFromPtr(o.arg));
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    syscall.finish();
                    if (@TypeOf(rc) == usize) return @bitCast(@as(u32, @truncate(rc)));
                    return rc;
                },
                .INTR => {
                    try syscall.checkCancel();
                    continue;
                },
                else => |err| {
                    syscall.finish();
                    return -@as(i32, @intFromEnum(err));
                },
            }
        }
    }
}

const WaitGroup = struct {
    state: std.atomic.Value(usize),
    event: Io.Event,

    const init: WaitGroup = .{ .state = .{ .raw = 0 }, .event = .unset };

    const is_waiting: usize = 1 << 0;
    const one_pending: usize = 1 << 1;

    fn start(wg: *WaitGroup) void {
        const prev_state = wg.state.fetchAdd(one_pending, .monotonic);
        assert((prev_state / one_pending) < (std.math.maxInt(usize) / one_pending));
    }

    fn value(wg: *WaitGroup) usize {
        return wg.state.load(.monotonic) / one_pending;
    }

    fn wait(wg: *WaitGroup) void {
        const prev_state = wg.state.fetchAdd(is_waiting, .acquire);
        assert(prev_state & is_waiting == 0);
        if ((prev_state / one_pending) > 0) eventWait(&wg.event);
    }

    fn finish(wg: *WaitGroup) void {
        const state = wg.state.fetchSub(one_pending, .acq_rel);
        assert((state / one_pending) > 0);

        if (state == (one_pending | is_waiting)) {
            eventSet(&wg.event);
        }
    }
};

/// Same as `Io.Event.wait` but avoids the VTable.
fn eventWait(event: *Io.Event) void {
    if (@cmpxchgStrong(Io.Event, event, .unset, .waiting, .acquire, .acquire)) |prev| switch (prev) {
        .unset => unreachable,
        .waiting => {},
        .is_set => return,
    };
    while (true) {
        Thread.futexWaitUncancelable(@ptrCast(event), @intFromEnum(Io.Event.waiting), null);
        switch (@atomicLoad(Io.Event, event, .acquire)) {
            .unset => unreachable, // `reset` called before pending `wait` returned
            .waiting => continue,
            .is_set => return,
        }
    }
}

/// Same as `Io.Event.set` but avoids the VTable.
fn eventSet(event: *Io.Event) void {
    switch (@atomicRmw(Io.Event, event, .Xchg, .is_set, .release)) {
        .unset, .is_set => {},
        .waiting => Thread.futexWake(@ptrCast(event), std.math.maxInt(u32)),
    }
}

/// Same as `Io.Condition.broadcast` but avoids the VTable.
fn condBroadcast(cond: *Io.Condition) void {
    var prev_state = cond.state.load(.monotonic);
    while (prev_state.waiters > prev_state.signals) {
        @branchHint(.unlikely);
        prev_state = cond.state.cmpxchgWeak(prev_state, .{
            .waiters = prev_state.waiters,
            .signals = prev_state.waiters,
        }, .release, .monotonic) orelse {
            // Update the epoch to tell the waiting threads that there are new signals for them.
            // Note that a waiting thread could miss a take if *exactly* (1<<32)-1 wakes happen
            // between it observing the epoch and sleeping on it, but this is extraordinarily
            // unlikely due to the precise number of calls required.
            _ = cond.epoch.fetchAdd(1, .release); // `.release` to ensure ordered after `state` update
            Thread.futexWake(&cond.epoch.raw, prev_state.waiters - prev_state.signals);
            return;
        };
    }
}

/// Same as `Io.Condition.signal` but avoids the VTable.
fn condSignal(cond: *Io.Condition) void {
    var prev_state = cond.state.load(.monotonic);
    while (prev_state.waiters > prev_state.signals) {
        @branchHint(.unlikely);
        prev_state = cond.state.cmpxchgWeak(prev_state, .{
            .waiters = prev_state.waiters,
            .signals = prev_state.signals + 1,
        }, .release, .monotonic) orelse {
            // Update the epoch to tell the waiting threads that there are new signals for them.
            // Note that a waiting thread could miss a take if *exactly* (1<<32)-1 wakes happen
            // between it observing the epoch and sleeping on it, but this is extraordinarily
            // unlikely due to the precise number of calls required.
            _ = cond.epoch.fetchAdd(1, .release); // `.release` to ensure ordered after `state` update
            Thread.futexWake(&cond.epoch.raw, 1);
            return;
        };
    }
}

/// Same as `Io.Condition.waitUncancelable` but avoids the VTable.
fn condWait(cond: *Io.Condition, mutex: *Io.Mutex) void {
    var epoch = cond.epoch.load(.acquire); // `.acquire` to ensure ordered before state load

    {
        const prev_state = cond.state.fetchAdd(.{ .waiters = 1, .signals = 0 }, .monotonic);
        assert(prev_state.waiters < std.math.maxInt(u16)); // overflow caused by too many waiters
    }

    mutexUnlock(mutex);
    defer mutexLock(mutex);

    while (true) {
        Thread.futexWaitUncancelable(&cond.epoch.raw, epoch, null);

        epoch = cond.epoch.load(.acquire); // `.acquire` to ensure ordered before `state` laod

        var prev_state = cond.state.load(.monotonic);
        while (prev_state.signals > 0) {
            prev_state = cond.state.cmpxchgWeak(prev_state, .{
                .waiters = prev_state.waiters - 1,
                .signals = prev_state.signals - 1,
            }, .acquire, .monotonic) orelse {
                // We successfully consumed a signal.
                return;
            };
        }
    }
}

/// Same as `Io.Mutex.lockUncancelable` but avoids the VTable.
pub fn mutexLock(m: *Io.Mutex) void {
    const initial_state = m.state.cmpxchgStrong(
        .unlocked,
        .locked_once,
        .acquire,
        .monotonic,
    ) orelse {
        @branchHint(.likely);
        return;
    };
    if (initial_state == .contended) {
        Thread.futexWaitUncancelable(@ptrCast(&m.state.raw), @intFromEnum(Io.Mutex.State.contended), null);
    }
    while (m.state.swap(.contended, .acquire) != .unlocked) {
        Thread.futexWaitUncancelable(@ptrCast(&m.state.raw), @intFromEnum(Io.Mutex.State.contended), null);
    }
}

/// Same as `Io.Mutex.unlock` but avoids the VTable.
pub fn mutexUnlock(m: *Io.Mutex) void {
    switch (m.state.swap(.unlocked, .release)) {
        .unlocked => unreachable,
        .locked_once => {},
        .contended => {
            @branchHint(.unlikely);
            Thread.futexWake(@ptrCast(&m.state.raw), 1);
        },
    }
}

const OpenError = error{
    IsDir,
    NotDir,
    FileNotFound,
    NoDevice,
    AccessDenied,
    PipeBusy,
    PathAlreadyExists,
    WouldBlock,
    NetworkNotFound,
    AntivirusInterference,
    FileBusy,
} || Dir.PathNameError || Io.Cancelable || Io.UnexpectedError;

const OpenFileOptions = struct {
    access_mask: windows.ACCESS_MASK,
    dir: ?windows.HANDLE = null,
    sa: ?*const windows.SECURITY_ATTRIBUTES = null,
    share_access: windows.FILE.SHARE = .VALID_FLAGS,
    creation: windows.FILE.CREATE_DISPOSITION,
    filter: Filter = .non_directory_only,
    /// If false, tries to open path as a reparse point without dereferencing it.
    /// Defaults to true.
    follow_symlinks: bool = true,

    pub const Filter = enum {
        /// Causes `OpenFile` to return `error.IsDir` if the opened handle would be a directory.
        non_directory_only,
        /// Causes `OpenFile` to return `error.NotDir` if the opened handle is not a directory.
        dir_only,
        /// `OpenFile` does not discriminate between opening files and directories.
        any,
    };
};

/// TODO: inline this logic everywhere and delete this function
fn OpenFile(sub_path_w: []const u16, options: OpenFileOptions) OpenError!windows.HANDLE {
    if (std.mem.eql(u16, sub_path_w, &.{'.'}) and options.filter == .non_directory_only) {
        return error.IsDir;
    }
    if (std.mem.eql(u16, sub_path_w, &.{ '.', '.' }) and options.filter == .non_directory_only) {
        return error.IsDir;
    }

    var result: windows.HANDLE = undefined;

    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = if (Dir.path.isAbsoluteWindowsWtf16(sub_path_w)) null else options.dir,
        .Attributes = .{ .INHERIT = if (options.sa) |sa| sa.bInheritHandle.toBool() else false },
        .ObjectName = @constCast(&windows.UNICODE_STRING.init(sub_path_w)),
        .SecurityDescriptor = if (options.sa) |ptr| ptr.lpSecurityDescriptor else null,
    };

    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var attempt: u5 = 0;
    var syscall: Syscall = try .start();
    while (true) {
        switch (windows.ntdll.NtCreateFile(
            &result,
            options.access_mask,
            &attr,
            &iosb,
            null,
            .{ .NORMAL = true },
            options.share_access,
            options.creation,
            .{
                .DIRECTORY_FILE = options.filter == .dir_only,
                .NON_DIRECTORY_FILE = options.filter == .non_directory_only,
                .IO = if (options.follow_symlinks) .SYNCHRONOUS_NONALERT else .ASYNCHRONOUS,
                .OPEN_REPARSE_POINT = !options.follow_symlinks,
            },
            null,
            0,
        )) {
            .SUCCESS => {
                syscall.finish();
                return result;
            },
            .CANCELLED => {
                try syscall.checkCancel();
                continue;
            },
            .SHARING_VIOLATION => {
                // This occurs if the file attempting to be opened is a running
                // executable. However, there's a kernel bug: the error may be
                // incorrectly returned for an indeterminate amount of time
                // after an executable file is closed. Here we work around the
                // kernel bug with retry attempts.
                syscall.finish();
                if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
                try parking_sleep.sleep(.{ .duration = .{
                    .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                    .clock = .awake,
                } });
                attempt += 1;
                syscall = try .start();
                continue;
            },
            .DELETE_PENDING => {
                // This error means that there *was* a file in this location on
                // the file system, but it was deleted. However, the OS is not
                // finished with the deletion operation, and so this CreateFile
                // call has failed. There is not really a sane way to handle
                // this other than retrying the creation after the OS finishes
                // the deletion.
                syscall.finish();
                if (max_windows_kernel_bug_retries - attempt == 0) return error.FileBusy;
                try parking_sleep.sleep(.{ .duration = .{
                    .raw = .fromMilliseconds((@as(u32, 1) << attempt) >> 1),
                    .clock = .awake,
                } });
                attempt += 1;
                syscall = try .start();
                continue;
            },
            .OBJECT_NAME_INVALID => return syscall.fail(error.BadPathName),
            .OBJECT_NAME_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .OBJECT_PATH_NOT_FOUND => return syscall.fail(error.FileNotFound),
            .BAD_NETWORK_PATH => return syscall.fail(error.NetworkNotFound), // \\server was not found
            .BAD_NETWORK_NAME => return syscall.fail(error.NetworkNotFound), // \\server was found but \\server\share wasn't
            .NO_MEDIA_IN_DEVICE => return syscall.fail(error.NoDevice),
            .ACCESS_DENIED => return syscall.fail(error.AccessDenied),
            .PIPE_BUSY => return syscall.fail(error.PipeBusy),
            .PIPE_NOT_AVAILABLE => return syscall.fail(error.NoDevice),
            .OBJECT_NAME_COLLISION => return syscall.fail(error.PathAlreadyExists),
            .FILE_IS_A_DIRECTORY => return syscall.fail(error.IsDir),
            .NOT_A_DIRECTORY => return syscall.fail(error.NotDir),
            .USER_MAPPED_FILE => return syscall.fail(error.AccessDenied),
            .VIRUS_INFECTED, .VIRUS_DELETED => return syscall.fail(error.AntivirusInterference),
            .INVALID_PARAMETER => |status| return syscall.ntstatusBug(status),
            .OBJECT_PATH_SYNTAX_BAD => |status| return syscall.ntstatusBug(status),
            .INVALID_HANDLE => |status| return syscall.ntstatusBug(status),
            else => |status| return syscall.unexpectedNtstatus(status),
        }
    }
}

pub fn closeFd(fd: posix.fd_t) void {
    if (native_os == .wasi and !builtin.link_libc) {
        switch (std.os.wasi.fd_close(fd)) {
            .SUCCESS, .INTR => {},
            .BADF => recoverableOsBugDetected(), // use after free
            else => recoverableOsBugDetected(), // unexpected failure
        }
    } else switch (posix.errno(posix.system.close(fd))) {
        .SUCCESS, .INTR => {}, // INTR still a success, see https://github.com/ziglang/zig/issues/2425
        .BADF => recoverableOsBugDetected(), // use after free
        else => recoverableOsBugDetected(), // unexpected failure
    }
}
