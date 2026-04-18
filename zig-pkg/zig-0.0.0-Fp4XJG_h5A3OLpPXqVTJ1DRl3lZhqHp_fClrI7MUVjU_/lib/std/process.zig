const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std.zig");
const Io = std.Io;
const File = std.Io.File;
const fs = std.fs;
const mem = std.mem;
const math = std.math;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;
const posix = std.posix;
const windows = std.os.windows;
const unicode = std.unicode;
const max_path_bytes = std.fs.max_path_bytes;

pub const Child = @import("process/Child.zig");
pub const Args = @import("process/Args.zig");
pub const Environ = @import("process/Environ.zig");
pub const Preopens = @import("process/Preopens.zig");

/// A standard set of pre-initialized useful APIs for programs to take
/// advantage of. This is the type of the first parameter of the main function.
/// Applications wanting more flexibility can accept `Init.Minimal` instead.
///
/// Completion of https://github.com/ziglang/zig/issues/24510 will also allow
/// the second parameter of the main function to be a custom struct that
/// contain auto-parsed CLI arguments.
pub const Init = struct {
    /// `Init` is a superset of `Minimal`; the latter is included here.
    minimal: Minimal,
    /// Permanent storage for the entire process, cleaned automatically on
    /// exit. Threadsafe.
    arena: *std.heap.ArenaAllocator,
    /// A default-selected general purpose allocator for temporary heap
    /// allocations. Debug mode will set up leak checking if possible.
    /// Threadsafe.
    gpa: Allocator,
    /// An appropriate default Io implementation based on the target
    /// configuration. Debug mode will set up leak checking if possible.
    io: Io,
    /// Environment variables, initialized with `gpa`. Not threadsafe.
    environ_map: *Environ.Map,
    /// Named files that have been provided by the parent process. This is
    /// mainly useful on WASI, but can be used on other systems to mimic the
    /// behavior with respect to stdio.
    preopens: Preopens,

    /// Alternative to `Init` as the first parameter of the main function.
    pub const Minimal = struct {
        /// Environment variables.
        environ: Environ,
        /// Command line arguments.
        args: Args,
    };
};

pub const CurrentPathError = error{
    NameTooLong,
    /// Not possible on Windows. Always returned on WASI.
    CurrentDirUnlinked,
} || Io.Cancelable || Io.UnexpectedError;

/// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On other platforms, the result is an opaque sequence of bytes with no
/// particular encoding.
pub fn currentPath(io: Io, buffer: []u8) CurrentPathError!usize {
    return io.vtable.processCurrentPath(io.userdata, buffer);
}

pub const CurrentPathAllocError = Allocator.Error || error{
    /// Not possible on Windows. Always returned on WASI.
    CurrentDirUnlinked,
} || Io.Cancelable || Io.UnexpectedError;

/// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On other platforms, the result is an opaque sequence of bytes with no
/// particular encoding.
///
/// Caller owns returned memory.
pub fn currentPathAlloc(io: Io, allocator: Allocator) CurrentPathAllocError![:0]u8 {
    var buffer: [max_path_bytes]u8 = undefined;
    const n = currentPath(io, &buffer) catch |err| switch (err) {
        error.NameTooLong => unreachable,
        else => |e| return e,
    };
    return allocator.dupeZ(u8, buffer[0..n]);
}

test currentPathAlloc {
    const cwd = try currentPathAlloc(testing.io, testing.allocator);
    testing.allocator.free(cwd);
}

pub const UserInfo = struct {
    uid: posix.uid_t,
    gid: posix.gid_t,
};

/// POSIX function which gets a uid from username.
pub fn getUserInfo(name: []const u8) !UserInfo {
    return switch (native_os) {
        .linux,
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        .freebsd,
        .netbsd,
        .openbsd,
        .haiku,
        .illumos,
        .serenity,
        => posixGetUserInfo(name),
        else => @compileError("Unsupported OS"),
    };
}

/// TODO this reads /etc/passwd. But sometimes the user/id mapping is in something else
/// like NIS, AD, etc. See `man nss` or look at an strace for `id myuser`.
pub fn posixGetUserInfo(io: Io, name: []const u8) !UserInfo {
    const file = try Io.Dir.openFileAbsolute(io, "/etc/passwd", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&buffer);
    return posixGetUserInfoPasswdStream(name, &file_reader.interface) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err.?,
        error.EndOfStream => return error.UserNotFound,
        error.CorruptPasswordFile => return error.CorruptPasswordFile,
    };
}

fn posixGetUserInfoPasswdStream(name: []const u8, reader: *std.Io.Reader) !UserInfo {
    const State = enum {
        start,
        wait_for_next_line,
        skip_password,
        read_user_id,
        read_group_id,
    };

    var name_index: usize = 0;
    var uid: posix.uid_t = 0;
    var gid: posix.gid_t = 0;

    sw: switch (State.start) {
        .start => switch (try reader.takeByte()) {
            ':' => {
                if (name_index == name.len) {
                    continue :sw .skip_password;
                } else {
                    continue :sw .wait_for_next_line;
                }
            },
            '\n' => return error.CorruptPasswordFile,
            else => |byte| {
                if (name_index == name.len or name[name_index] != byte) {
                    continue :sw .wait_for_next_line;
                }
                name_index += 1;
                continue :sw .start;
            },
        },
        .wait_for_next_line => switch (try reader.takeByte()) {
            '\n' => {
                name_index = 0;
                continue :sw .start;
            },
            else => continue :sw .wait_for_next_line,
        },
        .skip_password => switch (try reader.takeByte()) {
            '\n' => return error.CorruptPasswordFile,
            ':' => {
                continue :sw .read_user_id;
            },
            else => continue :sw .skip_password,
        },
        .read_user_id => switch (try reader.takeByte()) {
            ':' => {
                continue :sw .read_group_id;
            },
            '\n' => return error.CorruptPasswordFile,
            else => |byte| {
                const digit = switch (byte) {
                    '0'...'9' => byte - '0',
                    else => return error.CorruptPasswordFile,
                };
                {
                    const ov = @mulWithOverflow(uid, 10);
                    if (ov[1] != 0) return error.CorruptPasswordFile;
                    uid = ov[0];
                }
                {
                    const ov = @addWithOverflow(uid, digit);
                    if (ov[1] != 0) return error.CorruptPasswordFile;
                    uid = ov[0];
                }
                continue :sw .read_user_id;
            },
        },
        .read_group_id => switch (try reader.takeByte()) {
            '\n', ':' => return .{
                .uid = uid,
                .gid = gid,
            },
            else => |byte| {
                const digit = switch (byte) {
                    '0'...'9' => byte - '0',
                    else => return error.CorruptPasswordFile,
                };
                {
                    const ov = @mulWithOverflow(gid, 10);
                    if (ov[1] != 0) return error.CorruptPasswordFile;
                    gid = ov[0];
                }
                {
                    const ov = @addWithOverflow(gid, digit);
                    if (ov[1] != 0) return error.CorruptPasswordFile;
                    gid = ov[0];
                }
                continue :sw .read_group_id;
            },
        },
    }
    comptime unreachable;
}

pub fn getBaseAddress() usize {
    switch (native_os) {
        .linux => {
            const phdrs = std.posix.getSelfPhdrs();
            var base: usize = 0;
            for (phdrs) |phdr| switch (phdr.type) {
                .LOAD => return base + phdr.vaddr,
                .PHDR => base = @intFromPtr(phdrs.ptr) - phdr.vaddr,
                else => {},
            } else unreachable;
        },
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
            return @intFromPtr(&std.c._mh_execute_header);
        },
        .windows => return @intFromPtr(windows.peb().ImageBaseAddress),
        else => @compileError("Unsupported OS"),
    }
}

/// Tells whether the target operating system supports replacing the current
/// process image. If this is `false` then calling `replace` or `replaceFile`
/// functions will return `error.OperationUnsupported`.
pub const can_replace = switch (native_os) {
    .windows, .haiku, .wasi => false,
    else => true,
};

/// Tells whether spawning child processes is supported.
pub const can_spawn = switch (native_os) {
    .wasi, .ios, .tvos, .visionos, .watchos => false,
    else => true,
};

pub const ReplaceError = error{
    /// The target operating system cannot replace the process image with a new
    /// one.
    OperationUnsupported,
    SystemResources,
    AccessDenied,
    PermissionDenied,
    InvalidExe,
    FileSystem,
    IsDir,
    FileNotFound,
    NotDir,
    FileBusy,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
} || Allocator.Error || Io.Dir.PathNameError || Io.Cancelable || Io.UnexpectedError;

pub const ReplaceOptions = struct {
    argv: []const []const u8,
    expand_arg0: ArgExpansion = .no_expand,
    /// Replaces the environment when provided. The PATH value from here is
    /// never used to resolve `argv[0]`.
    environ_map: ?*const Environ.Map = null,
};

/// Replaces the current process image with the executed process. If this
/// function succeeds, it does not return.
///
/// `argv[0]` is the name of the process to replace the current one with. If it
/// is not already a file path (i.e. it contains '/'), it is resolved into a
/// file path based on PATH from the parent environment.
///
/// It is illegal to call this function in a fork() child.
pub fn replace(io: Io, options: ReplaceOptions) ReplaceError {
    return io.vtable.processReplace(io.userdata, options);
}

/// Replaces the current process image with the executed process. If this
/// function succeeds, it does not return.
///
/// `argv[0]` is the file path of the process to replace the current one with,
/// relative to `dir`. It is *always* treated as a file path, even if it does
/// not contain '/'.
///
/// It is illegal to call this function in a fork() child.
pub fn replacePath(io: Io, dir: Io.Dir, options: ReplaceOptions) ReplaceError {
    return io.vtable.processReplacePath(io.userdata, dir, options);
}

pub const ArgExpansion = enum { expand, no_expand };

/// File name extensions supported natively by `CreateProcess()` on Windows.
pub const WindowsExtension = enum { bat, cmd, com, exe };

pub const SpawnError = error{
    /// The operating system does not support creating child processes.
    OperationUnsupported,
    OutOfMemory,
    /// POSIX-only. `StdIo.ignore` was selected and opening `/dev/null` returned ENODEV.
    NoDevice,
    /// Windows-only. `cwd` or `argv` was provided and it was invalid WTF-8.
    /// https://wtf-8.codeberg.page/
    InvalidWtf8,
    /// Windows-only. NUL (U+0000), LF (U+000A), CR (U+000D) are not allowed
    /// within arguments when executing a `.bat`/`.cmd` script.
    /// - NUL/LF signifiies end of arguments, so anything afterwards
    ///   would be lost after execution.
    /// - CR is stripped by `cmd.exe`, so any CR codepoints
    ///   would be lost after execution.
    InvalidBatchScriptArg,
    SystemResources,
    AccessDenied,
    PermissionDenied,
    InvalidExe,
    FileSystem,
    IsDir,
    FileNotFound,
    NotDir,
    FileBusy,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    ResourceLimitReached,
    InvalidUserId,
    InvalidProcessGroupId,
    SymLinkLoop,
    InvalidName,
    /// An attempt was made to change the process group ID of one of the
    /// children of the calling process and the child had already performed an
    /// image replacement.
    ProcessAlreadyExec,
    /// On Windows, the volume does not contain a recognized file system. File
    /// system drivers might not be loaded, or the volume may be corrupt.
    UnrecognizedVolume,
} || Io.File.OpenError || Io.Dir.PathNameError || Io.Cancelable || Io.UnexpectedError;

pub const SpawnOptions = struct {
    argv: []const []const u8,

    /// Set to change the current working directory when spawning the child process.
    cwd: Child.Cwd = .inherit,
    /// Replaces the child environment when provided. The PATH value from here
    /// is not used to resolve `argv[0]`; that resolution always uses parent
    /// environment.
    environ_map: ?*const Environ.Map = null,
    expand_arg0: ArgExpansion = .no_expand,
    /// When populated, a pipe will be created for the child process to
    /// communicate progress back to the parent. The file descriptor of the
    /// write end of the pipe will be specified in the `ZIG_PROGRESS`
    /// environment variable inside the child process. The progress reported by
    /// the child will be attached to this progress node in the parent process.
    ///
    /// The child's progress tree will be grafted into the parent's progress tree,
    /// by substituting this node with the child's root node.
    progress_node: std.Progress.Node = std.Progress.Node.none,

    stdin: StdIo = .inherit,
    stdout: StdIo = .inherit,
    stderr: StdIo = .inherit,

    /// Set to true to obtain rusage information for the child process.
    /// Depending on the target platform and implementation status, the
    /// requested statistics may or may not be available. If they are
    /// available, then the `resource_usage_statistics` field will be populated
    /// after calling `wait`.
    /// On Linux and Darwin, this obtains rusage statistics from wait4().
    request_resource_usage_statistics: bool = false,

    /// Set to change the user id when spawning the child process.
    uid: ?posix.uid_t = null,
    /// Set to change the group id when spawning the child process.
    gid: ?posix.gid_t = null,
    /// Set to change the process group id when spawning the child process.
    pgid: ?posix.pid_t = null,

    /// Start child process in suspended state.
    /// For Posix systems it's started as if SIGSTOP was sent.
    start_suspended: bool = false,
    /// Windows-only. Sets the CREATE_NO_WINDOW flag in CreateProcess.
    create_no_window: bool = false,
    /// Darwin-only. Disable ASLR for the child process.
    disable_aslr: bool = false,

    /// Behavior of the child process's standard input, output, and error streams.
    pub const StdIo = union(enum) {
        /// Inherit the corresponding stream from the parent process.
        inherit,
        /// Pass an already open file from the parent to the child.
        ///
        /// Nonblocking mode will be kept in the child process if present. This is
        /// likely not supported by the child process. For example:
        /// - Zig's std.Io.File.stdout() assumes blocking mode
        /// - Rust explicity documents that nonblocking stdio may cause panics
        /// - C++ standard streams do not support nonblocking file descriptors
        file: File,
        /// Pass a null stream to the child process by opening "/dev/null" on POSIX
        /// and "NUL" on Windows.
        ignore,
        /// Create a new pipe for the stream.
        ///
        /// The corresponding field (`stdout`, `stderr`, or `stdin`) will be
        /// assigned a `File` object that can be used to read from or write to the
        /// pipe.
        pipe,
        /// Spawn the child process with the corresponding stream missing. This
        /// will likely result in the child encountering EBADF if it tries to use
        /// stdin, stdout, or stderr, or if only one stream is closed, it will
        /// result in them getting mixed up. Generally, this option is for advanced
        /// use cases only.
        close,
    };
};

/// Creates a child process.
///
/// `argv[0]` is the name of the program to execute. If it is not already a
/// file path (i.e. it contains '/'), it is resolved into a file path based on
/// PATH from the parent environment.
pub fn spawn(io: Io, options: SpawnOptions) SpawnError!Child {
    return io.vtable.processSpawn(io.userdata, options);
}

/// Creates a child process.
///
/// `argv[0]` is the file path of the program to execute, relative to `dir`. It
/// is *always* treated as a file path, even if it does not contain '/'.
pub fn spawnPath(io: Io, dir: Io.Dir, options: SpawnOptions) SpawnError!Child {
    return io.vtable.processSpawnPath(io.userdata, dir, options);
}

pub const RunError = error{
    StreamTooLong,
} || SpawnError || Io.File.MultiReader.UnendingError || Io.Timeout.Error;

pub const RunOptions = struct {
    argv: []const []const u8,
    stderr_limit: Io.Limit = .unlimited,
    stdout_limit: Io.Limit = .unlimited,
    /// How many bytes to initially allocate for stderr and stdout.
    reserve_amount: usize = 64,

    /// Set to change the current working directory when spawning the child process.
    cwd: Child.Cwd = .inherit,
    /// Replaces the child environment when provided. The PATH value from here
    /// is not used to resolve `argv[0]`; that resolution always uses parent
    /// environment.
    environ_map: ?*const Environ.Map = null,
    expand_arg0: ArgExpansion = .no_expand,
    /// When populated, a pipe will be created for the child process to
    /// communicate progress back to the parent. The file descriptor of the
    /// write end of the pipe will be specified in the `ZIG_PROGRESS`
    /// environment variable inside the child process. The progress reported by
    /// the child will be attached to this progress node in the parent process.
    ///
    /// The child's progress tree will be grafted into the parent's progress tree,
    /// by substituting this node with the child's root node.
    progress_node: std.Progress.Node = std.Progress.Node.none,
    /// Windows-only. Sets the CREATE_NO_WINDOW flag in CreateProcess.
    create_no_window: bool = true,
    /// Darwin-only. Disable ASLR for the child process.
    disable_aslr: bool = false,
    timeout: Io.Timeout = .none,
};

pub const RunResult = struct {
    term: Child.Term,
    stdout: []u8,
    stderr: []u8,
};

/// Spawns a child process, waits for it, collecting stdout and stderr, and then returns.
/// If it succeeds, the caller owns result.stdout and result.stderr memory.
pub fn run(gpa: Allocator, io: Io, options: RunOptions) RunError!RunResult {
    var child = try spawn(io, .{
        .argv = options.argv,
        .cwd = options.cwd,
        .environ_map = options.environ_map,
        .expand_arg0 = options.expand_arg0,
        .progress_node = options.progress_node,
        .create_no_window = options.create_no_window,
        .disable_aslr = options.disable_aslr,

        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);

    var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);

    while (multi_reader.fill(options.reserve_amount, options.timeout)) |_| {
        if (options.stdout_limit.toInt()) |limit| {
            if (stdout_reader.buffered().len > limit)
                return error.StreamTooLong;
        }
        if (options.stderr_limit.toInt()) |limit| {
            if (stderr_reader.buffered().len > limit)
                return error.StreamTooLong;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    try multi_reader.checkAnyError();

    const term = try child.wait(io);

    const stdout_slice = try multi_reader.toOwnedSlice(0);
    errdefer gpa.free(stdout_slice);

    const stderr_slice = try multi_reader.toOwnedSlice(1);
    errdefer gpa.free(stderr_slice);

    return .{
        .stdout = stdout_slice,
        .stderr = stderr_slice,
        .term = term,
    };
}

pub const TotalSystemMemoryError = error{
    UnknownTotalSystemMemory,
};

/// Returns the total system memory, in bytes as a u64.
/// We return a u64 instead of usize due to PAE on ARM
/// and Linux's /proc/meminfo reporting more memory when
/// using QEMU user mode emulation.
pub fn totalSystemMemory() TotalSystemMemoryError!u64 {
    switch (native_os) {
        .linux => {
            var info: std.os.linux.Sysinfo = undefined;
            const result: usize = std.os.linux.sysinfo(&info);
            if (std.os.linux.errno(result) != .SUCCESS) {
                return error.UnknownTotalSystemMemory;
            }
            // Promote to u64 to avoid overflow on systems where info.totalram is a 32-bit usize
            return @as(u64, info.totalram) * info.mem_unit;
        },
        .dragonfly, .freebsd, .netbsd => {
            const name = if (native_os == .netbsd) "hw.physmem64" else "hw.physmem";
            var physmem: c_ulong = undefined;
            var len: usize = @sizeOf(c_ulong);
            switch (posix.errno(posix.system.sysctlbyname(name, &physmem, &len, null, 0))) {
                .SUCCESS => return @intCast(physmem),
                .FAULT => unreachable,
                .PERM => unreachable, // only when setting values
                .NOMEM => unreachable, // memory already on the stack
                .NOENT => unreachable,
                else => return error.UnknownTotalSystemMemory,
            }
        },
        // whole Darwin family
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
            // "hw.memsize" returns uint64_t
            var physmem: u64 = undefined;
            var len: usize = @sizeOf(u64);
            switch (posix.errno(posix.system.sysctlbyname("hw.memsize", &physmem, &len, null, 0))) {
                .SUCCESS => return physmem,
                .FAULT => unreachable,
                .PERM => unreachable, // only when setting values
                .NOMEM => unreachable, // memory already on the stack
                .NOENT => unreachable, // constant, known good value
                else => return error.UnknownTotalSystemMemory,
            }
        },
        .openbsd => {
            const mib: [2]c_int = [_]c_int{
                posix.CTL.HW,
                posix.HW.PHYSMEM64,
            };
            var physmem: i64 = undefined;
            var len: usize = @sizeOf(@TypeOf(physmem));
            posix.sysctl(&mib, &physmem, &len, null, 0) catch |err| switch (err) {
                error.NameTooLong => unreachable, // constant, known good value
                error.PermissionDenied => unreachable, // only when setting values,
                error.SystemResources => unreachable, // memory already on the stack
                error.UnknownName => unreachable, // constant, known good value
                else => return error.UnknownTotalSystemMemory,
            };
            assert(physmem >= 0);
            return @as(u64, @bitCast(physmem));
        },
        .windows => {
            var sbi: windows.SYSTEM.BASIC_INFORMATION = undefined;
            const rc = windows.ntdll.NtQuerySystemInformation(
                .Basic,
                &sbi,
                @sizeOf(windows.SYSTEM.BASIC_INFORMATION),
                null,
            );
            if (rc != .SUCCESS) {
                return error.UnknownTotalSystemMemory;
            }
            return @as(u64, sbi.NumberOfPhysicalPages) * sbi.PageSize;
        },
        else => return error.UnknownTotalSystemMemory,
    }
}

/// Indicate intent to terminate with a successful exit code.
///
/// In debug builds, this is a no-op, so that the calling code's cleanup
/// mechanisms are tested and so that external tools checking for resource
/// leaks can be accurate. In release builds, this calls `exit` with code zero,
/// and does not return.
pub fn cleanExit(io: Io) void {
    if (builtin.mode == .Debug) return;
    _ = io.lockStderr(&.{}, .no_color) catch {};
    exit(0);
}

/// Request ability to have more open file descriptors simultaneously.
///
/// On some systems, this raises the limit before seeing ProcessFdQuotaExceeded
/// errors. On other systems, this does nothing.
pub fn raiseFileDescriptorLimit() void {
    const have_rlimit = posix.rlimit_resource != void;
    if (!have_rlimit) return;

    var lim = posix.getrlimit(.NOFILE) catch return; // Oh well; we tried.
    if (native_os.isDarwin()) {
        // On Darwin, `NOFILE` is bounded by a hardcoded value `OPEN_MAX`.
        // According to the man pages for setrlimit():
        //   setrlimit() now returns with errno set to EINVAL in places that historically succeeded.
        //   It no longer accepts "rlim_cur = RLIM.INFINITY" for RLIM.NOFILE.
        //   Use "rlim_cur = min(OPEN_MAX, rlim_max)".
        lim.max = @min(std.c.OPEN_MAX, lim.max);
    }
    if (lim.cur == lim.max) return;

    // Do a binary search for the limit.
    var min: posix.rlim_t = lim.cur;
    var max: posix.rlim_t = 1 << 20;
    // But if there's a defined upper bound, don't search, just set it.
    if (lim.max != posix.RLIM.INFINITY) {
        min = lim.max;
        max = lim.max;
    }

    while (true) {
        lim.cur = min + @divTrunc(max - min, 2); // on freebsd rlim_t is signed
        if (posix.setrlimit(.NOFILE, lim)) |_| {
            min = lim.cur;
        } else |_| {
            max = lim.cur;
        }
        if (min + 1 >= max) break;
    }
}

test raiseFileDescriptorLimit {
    raiseFileDescriptorLimit();
}

/// Logs an error and then terminates the process with exit code 1.
pub fn fatal(comptime format: []const u8, format_arguments: anytype) noreturn {
    std.log.err(format, format_arguments);
    exit(1);
}

pub const ExecutablePathBaseError = error{
    FileNotFound,
    AccessDenied,
    /// The operating system does not support an executable learning its own
    /// path.
    OperationUnsupported,
    NotDir,
    SymLinkLoop,
    InputOutput,
    FileTooBig,
    IsDir,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    SystemResources,
    NoSpaceLeft,
    FileSystem,
    BadPathName,
    DeviceBusy,
    PipeBusy,
    NotLink,
    PathAlreadyExists,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
    ProcessNotFound,
    /// On Windows, antivirus software is enabled by default. It can be
    /// disabled, but Windows Update sometimes ignores the user's preference
    /// and re-enables it. When enabled, antivirus software on Windows
    /// intercepts file system operations and makes them significantly slower
    /// in addition to possibly failing with this error code.
    AntivirusInterference,
    /// On Windows, the volume does not contain a recognized file system. File
    /// system drivers might not be loaded, or the volume may be corrupt.
    UnrecognizedVolume,
    PermissionDenied,
} || Io.Cancelable || Io.UnexpectedError;

pub const ExecutablePathAllocError = ExecutablePathBaseError || Allocator.Error;

pub fn executablePathAlloc(io: Io, allocator: Allocator) ExecutablePathAllocError![:0]u8 {
    var buffer: [max_path_bytes]u8 = undefined;
    const n = executablePath(io, &buffer) catch |err| switch (err) {
        error.NameTooLong => unreachable,
        else => |e| return e,
    };
    return allocator.dupeZ(u8, buffer[0..n]);
}

pub const ExecutablePathError = ExecutablePathBaseError || error{NameTooLong};

/// Get the path to the current executable, following symlinks.
///
/// This function may return an error if the current executable
/// was deleted after spawning.
///
/// Returned value is a slice of out_buffer.
///
/// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On other platforms, the result is an opaque sequence of bytes with no particular encoding.
///
/// On Linux, depends on procfs being mounted. If the currently executing binary has
/// been deleted, the file path looks something like "/a/b/c/exe (deleted)".
///
/// See also:
/// * `executableDirPath` - to obtain only the directory
/// * `openExecutable` - to obtain only an open file handle
pub fn executablePath(io: Io, out_buffer: []u8) ExecutablePathError!usize {
    return io.vtable.processExecutablePath(io.userdata, out_buffer);
}

/// Get the directory path that contains the current executable.
///
/// Returns index into `out_buffer`.
///
/// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On other platforms, the result is an opaque sequence of bytes with no particular encoding.
pub fn executableDirPath(io: Io, out_buffer: []u8) ExecutablePathError!usize {
    const n = try executablePath(io, out_buffer);
    // Assert that the OS APIs return absolute paths, and therefore dirname
    // will not return null.
    return std.fs.path.dirname(out_buffer[0..n]).?.len;
}

/// Same as `executableDirPath` except allocates the result.
pub fn executableDirPathAlloc(io: Io, allocator: Allocator) ExecutablePathAllocError![]u8 {
    var buffer: [max_path_bytes]u8 = undefined;
    const dir_path_len = executableDirPath(io, &buffer) catch |err| switch (err) {
        error.NameTooLong => unreachable,
        else => |e| return e,
    };
    return allocator.dupe(u8, buffer[0..dir_path_len]);
}

pub const OpenExecutableError = File.OpenError || ExecutablePathError || File.LockError;

pub fn openExecutable(io: Io, flags: File.OpenFlags) OpenExecutableError!File {
    return io.vtable.processExecutableOpen(io.userdata, flags);
}

/// Causes abnormal process termination.
///
/// If linking against libc, this calls `std.c.abort`. Otherwise it raises
/// SIGABRT followed by SIGKILL.
///
/// Invokes the current signal handler for SIGABRT, if any.
pub fn abort() noreturn {
    @branchHint(.cold);
    // MSVCRT abort() sometimes opens a popup window which is undesirable, so
    // even when linking libc on Windows we use our own abort implementation.
    // See https://github.com/ziglang/zig/issues/2071 for more details.
    if (native_os == .windows) {
        if (builtin.mode == .Debug and windows.peb().BeingDebugged.toBool()) {
            @breakpoint();
        }
        windows.ntdll.RtlExitUserProcess(3);
    }
    if (!builtin.link_libc and native_os == .linux) {
        // The Linux man page says that the libc abort() function
        // "first unblocks the SIGABRT signal", but this is a footgun
        // for user-defined signal handlers that want to restore some state in
        // some program sections and crash in others.
        // So, the user-installed SIGABRT handler is run, if present.
        posix.raise(.ABRT) catch {};

        // Disable all signal handlers.
        const filledset = std.os.linux.sigfillset();
        posix.sigprocmask(posix.SIG.BLOCK, &filledset, null);

        // Only one thread may proceed to the rest of abort().
        if (!builtin.single_threaded) {
            const global = struct {
                var abort_entered: bool = false;
            };
            while (@cmpxchgWeak(bool, &global.abort_entered, false, true, .seq_cst, .seq_cst)) |_| {}
        }

        // Install default handler so that the tkill below will terminate.
        const sigact: posix.Sigaction = .{
            .handler = .{ .handler = posix.SIG.DFL },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(.ABRT, &sigact, null);

        _ = std.os.linux.tkill(std.os.linux.gettid(), .ABRT);

        var sigabrtmask = posix.sigemptyset();
        posix.sigaddset(&sigabrtmask, .ABRT);
        posix.sigprocmask(posix.SIG.UNBLOCK, &sigabrtmask, null);

        // Beyond this point should be unreachable.
        @as(*allowzero volatile u8, @ptrFromInt(0)).* = 0;
        posix.raise(.KILL) catch {};
        exit(127); // Pid 1 might not be signalled in some containers.
    }
    switch (native_os) {
        .uefi, .wasi, .emscripten, .cuda, .amdhsa => @trap(),
        else => posix.system.abort(),
    }
}

/// Exits all threads of the program with the specified status code.
pub fn exit(status: u8) noreturn {
    if (builtin.link_libc) {
        std.c.exit(status);
    } else switch (native_os) {
        .windows => windows.ntdll.RtlExitUserProcess(status),
        .wasi => std.os.wasi.proc_exit(status),
        .linux => {
            if (!builtin.single_threaded) std.os.linux.exit_group(status);
            posix.system.exit(status);
        },
        .uefi => {
            const uefi = std.os.uefi;
            // exit() is only available if exitBootServices() has not been called yet.
            // This call to exit should not fail, so we catch-ignore errors.
            if (uefi.system_table.boot_services) |bs| {
                bs.exit(uefi.handle, @enumFromInt(status), null) catch {};
            }
            // If we can't exit, reboot the system instead.
            uefi.system_table.runtime_services.resetSystem(.cold, @enumFromInt(status), null);
        },
        else => posix.system.exit(status),
    }
}

pub const SetCurrentDirError = error{
    AccessDenied,
    BadPathName,
    FileNotFound,
    FileSystem,
    NameTooLong,
    NoDevice,
    NotDir,
    OperationUnsupported,
    UnrecognizedVolume,
} || Io.Cancelable || Io.UnexpectedError;

/// Changes the current working directory to the open directory handle.
/// Corresponds to "fchdir" in libc.
///
/// This modifies global process state and can have surprising effects in
/// multithreaded applications. Most applications and especially libraries
/// should not call this function as a general rule, however it can have use
/// cases in, for example, implementing a shell, or child process execution.
///
/// Calling this function makes code less portable and less reusable.
pub fn setCurrentDir(io: Io, dir: Io.Dir) !void {
    return io.vtable.processSetCurrentDir(io.userdata, dir);
}

pub const SetCurrentPathError = error{
    AccessDenied,
    SymLinkLoop,
    SystemResources,
    BadPathName,
    FileNotFound,
    FileSystem,
    NoDevice,
    NotDir,
    NameTooLong,
    OperationUnsupported,
    /// Windows-only. The path is invalid WTF-8.
    /// https://wtf-8.codeberg.page/
    InvalidWtf8,
} || Io.Cancelable || Io.UnexpectedError;

/// Changes the current working directory to the given path.
/// Corresponds to "chdir" in libc.
///
/// This modifies global process state and can have surprising effects in
/// multithreaded applications. Most applications and especially libraries
/// should not call this function as a general rule, however it can have use
/// cases in, for example, implementing a shell, or child process execution.
///
/// Calling this function makes code less portable and less reusable.
pub fn setCurrentPath(io: Io, path: []const u8) !void {
    return io.vtable.processSetCurrentPath(io.userdata, path);
}

pub const LockMemoryError = error{
    UnsupportedOperation,
    PermissionDenied,
    LockedMemoryLimitExceeded,
    SystemResources,
} || Io.UnexpectedError;

pub const LockMemoryOptions = struct {
    /// Lock pages that are currently resident and mark the entire range so
    /// that the remaining nonresident pages are locked when they are populated
    /// by a page fault.
    on_fault: bool = false,
};

/// Request part of the calling process's virtual address space to be in RAM,
/// preventing that memory from being paged to the swap area.
///
/// Corresponds to "mlock" or "mlock2" in libc.
///
/// See also:
/// * unlockMemory
pub fn lockMemory(memory: []align(std.heap.page_size_min) const u8, options: LockMemoryOptions) LockMemoryError!void {
    if (native_os == .windows) {
        // TODO call VirtualLock
    }
    if (!options.on_fault and @TypeOf(posix.system.mlock) != void) {
        switch (posix.errno(posix.system.mlock(memory.ptr, memory.len))) {
            .SUCCESS => return,
            .INVAL => |err| return std.Io.Threaded.errnoBug(err), // unaligned, negative, runs off end of addrspace
            .PERM => return error.PermissionDenied,
            .NOMEM => return error.LockedMemoryLimitExceeded,
            .AGAIN => return error.SystemResources,
            else => |err| return posix.unexpectedErrno(err),
        }
    }
    if (@TypeOf(posix.system.mlock2) != void) {
        const flags: posix.MLOCK = .{ .ONFAULT = options.on_fault };
        switch (posix.errno(posix.system.mlock2(memory.ptr, memory.len, flags))) {
            .SUCCESS => return,
            .INVAL => |err| return std.Io.Threaded.errnoBug(err), // unaligned, negative, runs off end of addrspace
            .PERM => return error.PermissionDenied,
            .NOMEM => return error.LockedMemoryLimitExceeded,
            .AGAIN => return error.SystemResources,
            else => |err| return posix.unexpectedErrno(err),
        }
    }
    return error.UnsupportedOperation;
}

pub const UnlockMemoryError = error{
    PermissionDenied,
    OutOfMemory,
    SystemResources,
} || Io.UnexpectedError;

/// Withdraw request for process's virtual address space to be in RAM.
///
/// Corresponds to "munlock" in libc.
///
/// See also:
/// * `lockMemory`
pub fn unlockMemory(memory: []align(std.heap.page_size_min) const u8) UnlockMemoryError!void {
    if (@TypeOf(posix.system.munlock) == void) return;
    switch (posix.errno(posix.system.munlock(memory.ptr, memory.len))) {
        .SUCCESS => return,
        .INVAL => |err| return std.Io.Threaded.errnoBug(err), // unaligned or runs off end of addr space
        .PERM => return error.PermissionDenied,
        .NOMEM => return error.OutOfMemory,
        .AGAIN => return error.SystemResources,
        else => |err| return posix.unexpectedErrno(err),
    }
}

pub const LockMemoryAllOptions = struct {
    current: bool = false,
    future: bool = false,
    /// Asserted to be used together with `current` or `future`, or both.
    on_fault: bool = false,
};

pub fn lockMemoryAll(options: LockMemoryAllOptions) LockMemoryError!void {
    if (@TypeOf(posix.system.mlockall) == void) return error.UnsupportedOperation;
    var flags: posix.MCL = .{
        .CURRENT = options.current,
        .FUTURE = options.future,
    };
    if (options.on_fault) {
        assert(options.current or options.future);
        if (@hasField(posix.MCL, "ONFAULT")) {
            flags.ONFAULT = true;
        } else {
            return error.UnsupportedOperation;
        }
    }
    switch (posix.errno(posix.system.mlockall(flags))) {
        .SUCCESS => return,
        .INVAL => |err| return std.Io.Threaded.errnoBug(err),
        .PERM => return error.PermissionDenied,
        .NOMEM => return error.LockedMemoryLimitExceeded,
        .AGAIN => return error.SystemResources,
        else => |err| return posix.unexpectedErrno(err),
    }
}

pub fn unlockMemoryAll() UnlockMemoryError!void {
    if (@TypeOf(posix.system.munlockall) == void) return;
    switch (posix.errno(posix.system.munlockall())) {
        .SUCCESS => return,
        .PERM => return error.PermissionDenied,
        .NOMEM => return error.OutOfMemory,
        .AGAIN => return error.SystemResources,
        else => |err| return posix.unexpectedErrno(err),
    }
}

pub const ProtectMemoryError = error{
    UnsupportedOperation,
    /// OpenBSD will refuse to change memory protection if the specified region
    /// contains any pages that have previously been marked immutable using the
    /// `mimmutable` function.
    PermissionDenied,
    /// The memory cannot be given the specified access. This can happen, for
    /// example, if you memory map a file to which you have read-only access,
    /// then use `protectMemory` to mark it writable.
    AccessDenied,
    /// Changing the protection of a memory region would result in the total
    /// number of mappings with distinct attributes exceeding the allowed
    /// maximum.
    OutOfMemory,
} || Io.UnexpectedError;

pub const MemoryProtection = packed struct(u3) {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
};

pub fn protectMemory(memory: []align(std.heap.page_size_min) u8, protection: MemoryProtection) ProtectMemoryError!void {
    if (native_os == .windows) {
        var addr = memory.ptr; // ntdll takes an extra level of indirection here
        var size = memory.len; // ntdll takes an extra level of indirection here
        var old: windows.PAGE = undefined;
        const current_process: windows.HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
        const new = windows.PAGE.fromProtection(protection) orelse return error.AccessDenied;
        switch (windows.ntdll.NtProtectVirtualMemory(current_process, @ptrCast(&addr), &size, new, &old)) {
            .SUCCESS => return,
            .INVALID_ADDRESS => return error.AccessDenied,
            else => |st| return windows.unexpectedStatus(st),
        }
    } else if (posix.PROT != void) {
        const flags: posix.PROT = .{
            .READ = protection.read,
            .WRITE = protection.write,
            .EXEC = protection.execute,
        };
        switch (posix.errno(posix.system.mprotect(memory.ptr, memory.len, flags))) {
            .SUCCESS => return,
            .PERM => return error.PermissionDenied,
            .INVAL => |err| return std.Io.Threaded.errnoBug(err),
            .ACCES => return error.AccessDenied,
            .NOMEM => return error.OutOfMemory,
            else => |err| return posix.unexpectedErrno(err),
        }
    }
    return error.UnsupportedOperation;
}

var test_page: [std.heap.page_size_max]u8 align(std.heap.page_size_max) = undefined;

test lockMemory {
    lockMemory(&test_page, .{}) catch return error.SkipZigTest;
    unlockMemory(&test_page) catch return error.SkipZigTest;
}

test lockMemoryAll {
    lockMemoryAll(.{ .current = true }) catch return error.SkipZigTest;
    unlockMemoryAll() catch return error.SkipZigTest;
}

test protectMemory {
    protectMemory(&test_page, .{}) catch return error.SkipZigTest;
    protectMemory(&test_page, .{ .read = true, .write = true }) catch return error.SkipZigTest;
}
