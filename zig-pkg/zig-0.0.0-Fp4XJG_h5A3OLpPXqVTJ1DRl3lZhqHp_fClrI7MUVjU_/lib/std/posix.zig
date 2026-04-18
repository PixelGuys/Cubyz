//! POSIX API layer.
//!
//! This is more cross platform than using OS-specific APIs, however, it is
//! lower-level and less portable than other namespaces such as `std.Io` and
//! `std.process`.
//!
//! These APIs are generally lowered to libc function calls if and only if libc
//! is linked. Most operating systems other than Windows, Linux, and WASI
//! require always linking libc because they use it as the stable syscall ABI.
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std.zig");
const Io = std.Io;
const mem = std.mem;
const maxInt = std.math.maxInt;
const cast = std.math.cast;
const assert = std.debug.assert;
const page_size_min = std.heap.page_size_min;

test {
    _ = @import("posix/test.zig");
}

/// Whether to use libc for the POSIX API layer.
const use_libc = builtin.link_libc or switch (native_os) {
    .windows, .wasi => true,
    else => false,
};

const linux = std.os.linux;
const windows = std.os.windows;
const wasi = std.os.wasi;

/// A libc-compatible API layer.
pub const system = if (use_libc)
    std.c
else switch (native_os) {
    .linux => linux,
    .plan9 => std.os.plan9,
    .psp => struct {
        pub const fd_t = i32;
        pub const pid_t = void;
        pub const pollfd = void;
        pub const uid_t = void;
        pub const gid_t = void;
        pub const mode_t = u32;
        pub const nlink_t = u32;
        pub const blksize_t = u32;
        pub const ino_t = u64;
        pub const IFNAMESIZE = {};
        pub const SIG = void;

        // https://github.com/pspdev/newlib/blob/9e0a073634ad73e8e088f2e071c55a9fe5d39709/newlib/libc/sys/psp/sys/dirent.h#L19
        pub const NAME_MAX = 255;
    },
    else => struct {
        pub const pid_t = void;
        pub const pollfd = void;
        pub const fd_t = void;
        pub const uid_t = void;
        pub const gid_t = void;
        pub const mode_t = u0;
        pub const nlink_t = u0;
        pub const blksize_t = void;
        pub const ino_t = void;
        pub const IFNAMESIZE = {};
        pub const SIG = void;
    },
};

pub const AF = system.AF;
pub const AF_SUN = system.AF_SUN;
pub const AI = system.AI;
pub const ARCH = system.ARCH;
pub const AT = system.AT;
pub const AT_SUN = system.AT_SUN;
pub const CLOCK = system.CLOCK;
pub const CPU_COUNT = system.CPU_COUNT;
pub const CTL = system.CTL;
pub const DT = system.DT;
pub const E = system.E;
pub const Elf_Symndx = system.Elf_Symndx;
pub const F = system.F;
pub const FD_CLOEXEC = system.FD_CLOEXEC;
pub const Flock = system.Flock;
pub const HOST_NAME_MAX = system.HOST_NAME_MAX;
pub const HW = system.HW;
pub const IFNAMESIZE = system.IFNAMESIZE;
pub const IOV_MAX = system.IOV_MAX;
pub const IP = system.IP;
pub const IPV6 = system.IPV6;
pub const IPPROTO = system.IPPROTO;
pub const IPTOS = system.IPTOS;
pub const KERN = system.KERN;
pub const Kevent = system.Kevent;
pub const MADV = system.MADV;
pub const MAP = system.MAP;
pub const MAX_ADDR_LEN = system.MAX_ADDR_LEN;
pub const MCL = system.MCL;
pub const MFD = system.MFD;
pub const MLOCK = system.MLOCK;
pub const MREMAP = system.MREMAP;
pub const MSF = system.MSF;
pub const MSG = system.MSG;
pub const NAME_MAX = system.NAME_MAX;
pub const NSIG = system.NSIG;
pub const O = system.O;
pub const PATH_MAX = system.PATH_MAX;
pub const POLL = system.POLL;
pub const POSIX_FADV = system.POSIX_FADV;
pub const PR = system.PR;
pub const PROT = system.PROT;
pub const RLIM = system.RLIM;
pub const S = system.S;
pub const SA = system.SA;
pub const SC = system.SC;
pub const SCM = system.SCM;
pub const SEEK = system.SEEK;
pub const SHUT = system.SHUT;
pub const SIG = system.SIG;
pub const SIOCGIFINDEX = system.SIOCGIFINDEX;
pub const SO = system.SO;
pub const SOCK = system.SOCK;
pub const SOL = system.SOL;
pub const IFF = system.IFF;
pub const STDERR_FILENO = system.STDERR_FILENO;
pub const STDIN_FILENO = system.STDIN_FILENO;
pub const STDOUT_FILENO = system.STDOUT_FILENO;
pub const SYS = system.SYS;
pub const Sigaction = system.Sigaction;
/// Windows has no concept of `stat`.
///
/// On Linux, the `stat` bits/wrappers are removed due to having to maintain
/// the different varying stat structs per target and libc, leading to runtime
/// errors. Users targeting Linux should add a comptime check and use statx,
/// similar to how `Io.File.stat` does.
pub const Stat = switch (native_os) {
    .windows => void,
    .linux => void,
    else => system.Stat,
};
pub const T = system.T;
pub const TCP = system.TCP;
pub const VDSO = system.VDSO;
pub const W = system.W;
pub const _SC = system._SC;
pub const addrinfo = system.addrinfo;
pub const blkcnt_t = system.blkcnt_t;
pub const blksize_t = system.blksize_t;
pub const clock_t = system.clock_t;
pub const clockid_t = system.clockid_t;
pub const timerfd_clockid_t = system.timerfd_clockid_t;
pub const cpu_set_t = system.cpu_set_t;
pub const dev_t = system.dev_t;
pub const dl_phdr_info = system.dl_phdr_info;
pub const fd_t = system.fd_t;
pub const file_obj = system.file_obj;
pub const gid_t = system.gid_t;
pub const ifreq = system.ifreq;
pub const in_pktinfo = system.in_pktinfo;
pub const in6_pktinfo = system.in6_pktinfo;
pub const ino_t = system.ino_t;
pub const linger = system.linger;
pub const mode_t = system.mode_t;
pub const msghdr = system.msghdr;
pub const msghdr_const = system.msghdr_const;
pub const nfds_t = system.nfds_t;
pub const nlink_t = system.nlink_t;
pub const off_t = system.off_t;
pub const pid_t = system.pid_t;
pub const pollfd = system.pollfd;
pub const port_event = system.port_event;
pub const port_notify = system.port_notify;
pub const port_t = system.port_t;
pub const rlim_t = system.rlim_t;
pub const rlimit = system.rlimit;
pub const rlimit_resource = system.rlimit_resource;
pub const rusage = system.rusage;
pub const sa_family_t = system.sa_family_t;
pub const siginfo_t = system.siginfo_t;
pub const sigset_t = system.sigset_t;
pub const sigrtmin = system.sigrtmin;
pub const sigrtmax = system.sigrtmax;
pub const sockaddr = system.sockaddr;
pub const socklen_t = system.socklen_t;
pub const stack_t = system.stack_t;
pub const time_t = system.time_t;
pub const timespec = system.timespec;
pub const timestamp_t = system.timestamp_t;
pub const timeval = system.timeval;
pub const timezone = system.timezone;
pub const UTIME = system.UTIME;
pub const uid_t = system.uid_t;
pub const user_desc = system.user_desc;
pub const utsname = system.utsname;

pub const termios = system.termios;
pub const CSIZE = system.CSIZE;
pub const NCCS = system.NCCS;
pub const cc_t = system.cc_t;
pub const V = system.V;
pub const speed_t = system.speed_t;
pub const tc_iflag_t = system.tc_iflag_t;
pub const tc_oflag_t = system.tc_oflag_t;
pub const tc_cflag_t = system.tc_cflag_t;
pub const tc_lflag_t = system.tc_lflag_t;

pub const F_OK = system.F_OK;
pub const R_OK = system.R_OK;
pub const W_OK = system.W_OK;
pub const X_OK = system.X_OK;

pub const iovec = extern struct {
    base: [*]u8,
    len: usize,
};

pub const iovec_const = extern struct {
    base: [*]const u8,
    len: usize,
};

pub const ACCMODE = switch (native_os) {
    // POSIX has a note about the access mode values:
    //
    // In historical implementations the value of O_RDONLY is zero. Because of
    // that, it is not possible to detect the presence of O_RDONLY and another
    // option. Future implementations should encode O_RDONLY and O_WRONLY as
    // bit flags so that: O_RDONLY | O_WRONLY == O_RDWR
    //
    // In practice SerenityOS is the only system supported by Zig that
    // implements this suggestion.
    // https://github.com/SerenityOS/serenity/blob/4adc51fdf6af7d50679c48b39362e062f5a3b2cb/Kernel/API/POSIX/fcntl.h#L28-L30
    .serenity => enum(u2) {
        NONE = 0,
        RDONLY = 1,
        WRONLY = 2,
        RDWR = 3,
    },
    else => enum(u2) {
        RDONLY = 0,
        WRONLY = 1,
        RDWR = 2,
    },
};

pub const TCSA = enum(c_uint) {
    NOW,
    DRAIN,
    FLUSH,
    _,
};

pub const winsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

pub const LOCK = struct {
    pub const SH = 1;
    pub const EX = 2;
    pub const NB = 4;
    pub const UN = 8;
};

pub const LOG = struct {
    /// system is unusable
    pub const EMERG = 0;
    /// action must be taken immediately
    pub const ALERT = 1;
    /// critical conditions
    pub const CRIT = 2;
    /// error conditions
    pub const ERR = 3;
    /// warning conditions
    pub const WARNING = 4;
    /// normal but significant condition
    pub const NOTICE = 5;
    /// informational
    pub const INFO = 6;
    /// debug-level messages
    pub const DEBUG = 7;
};

pub const socket_t = fd_t;

/// Obtains errno from the return value of a system function call.
///
/// For some systems this will obtain the value directly from the syscall return value;
/// for others it will use a thread-local errno variable. Therefore, this
/// function only returns a well-defined value when it is called directly after
/// the system function call whose errno value is intended to be observed.
pub const errno = system.errno;

pub const RebootError = error{
    PermissionDenied,
} || UnexpectedError;

pub const RebootCommand = switch (native_os) {
    .linux => union(linux.LINUX_REBOOT.CMD) {
        RESTART: void,
        HALT: void,
        CAD_ON: void,
        CAD_OFF: void,
        POWER_OFF: void,
        RESTART2: [*:0]const u8,
        SW_SUSPEND: void,
        KEXEC: void,
    },
    else => @compileError("Unsupported OS"),
};

pub fn reboot(cmd: RebootCommand) RebootError!void {
    switch (native_os) {
        .linux => {
            switch (linux.errno(linux.reboot(
                .MAGIC1,
                .MAGIC2,
                cmd,
                switch (cmd) {
                    .RESTART2 => |s| s,
                    else => null,
                },
            ))) {
                .SUCCESS => {},
                .PERM => return error.PermissionDenied,
                else => |err| return std.posix.unexpectedErrno(err),
            }
            switch (cmd) {
                .CAD_OFF => {},
                .CAD_ON => {},
                .SW_SUSPEND => {},

                .HALT => unreachable,
                .KEXEC => unreachable,
                .POWER_OFF => unreachable,
                .RESTART => unreachable,
                .RESTART2 => unreachable,
            }
        },
        else => @compileError("Unsupported OS"),
    }
}

pub const RaiseError = UnexpectedError;

pub fn raise(sig: SIG) RaiseError!void {
    if (builtin.link_libc) {
        switch (errno(system.raise(sig))) {
            .SUCCESS => return,
            else => |err| return unexpectedErrno(err),
        }
    }

    if (native_os == .linux) {
        // Block all signals so a `fork` (from a signal handler) between the gettid() and kill() syscalls
        // cannot trigger an extra, unexpected, inter-process signal.  Signal paranoia inherited from Musl.
        const filled = linux.sigfillset();
        var orig: sigset_t = undefined;
        sigprocmask(SIG.BLOCK, &filled, &orig);
        const rc = linux.tkill(linux.gettid(), sig);
        sigprocmask(SIG.SETMASK, &orig, null);

        switch (errno(rc)) {
            .SUCCESS => return,
            else => |err| return unexpectedErrno(err),
        }
    }

    @compileError("std.posix.raise unimplemented for this target");
}

pub const KillError = error{ ProcessNotFound, PermissionDenied } || UnexpectedError;

pub fn kill(pid: pid_t, sig: SIG) KillError!void {
    switch (errno(system.kill(pid, sig))) {
        .SUCCESS => return,
        .INVAL => unreachable, // invalid signal
        .PERM => return error.PermissionDenied,
        .SRCH => return error.ProcessNotFound,
        else => |err| return unexpectedErrno(err),
    }
}

pub const ReadError = std.Io.File.Reader.Error;

/// Returns the number of bytes that were read, which can be less than
/// buf.len. If 0 bytes were read, that means EOF.
/// If `fd` is opened in non blocking mode, the function will return error.WouldBlock
/// when EAGAIN is received.
///
/// Linux has a limit on how many bytes may be transferred in one `read` call, which is `0x7ffff000`
/// on both 64-bit and 32-bit systems. This is due to using a signed C int as the return value, as
/// well as stuffing the errno codes into the last `4096` values. This is noted on the `read` man page.
/// The limit on Darwin is `0x7fffffff`, trying to read more than that returns EINVAL.
/// The corresponding POSIX limit is `maxInt(isize)`.
pub fn read(fd: fd_t, buf: []u8) ReadError!usize {
    if (buf.len == 0) return 0;
    if (native_os == .windows) @compileError("unsupported OS");
    if (native_os == .wasi) @compileError("unsupported OS");

    // Prevents EINVAL.
    const max_count = switch (native_os) {
        .linux => 0x7ffff000,
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => maxInt(i32),
        else => maxInt(isize),
    };
    while (true) {
        const rc = system.read(fd, buf.ptr, @min(buf.len, max_count));
        switch (errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .INVAL => unreachable,
            .FAULT => unreachable,
            .AGAIN => return error.WouldBlock,
            .CANCELED => return error.Canceled,
            .BADF => return error.Unexpected, // use after free
            .IO => return error.InputOutput,
            .ISDIR => return error.IsDir,
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOTCONN => return error.SocketUnconnected,
            .CONNRESET => return error.ConnectionResetByPeer,
            .TIMEDOUT => return error.Unexpected,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const OpenError = std.Io.File.OpenError || error{WouldBlock};

/// Open and possibly create a file. Keeps trying if it gets interrupted.
/// `file_path` is relative to the open directory handle `dir_fd`.
/// On Windows, `file_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `file_path` should be encoded as valid UTF-8.
/// On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.
/// See also `openatZ`.
pub fn openat(dir_fd: fd_t, file_path: []const u8, flags: O, mode: mode_t) OpenError!fd_t {
    if (native_os == .windows) {
        @compileError("Windows does not support POSIX; use Windows-specific API or cross-platform std.fs API");
    } else if (native_os == .wasi and !builtin.link_libc) {
        @compileError("use std.Io instead");
    }
    const file_path_c = try toPosixPath(file_path);
    return openatZ(dir_fd, &file_path_c, flags, mode);
}

/// Open and possibly create a file. Keeps trying if it gets interrupted.
/// `file_path` is relative to the open directory handle `dir_fd`.
/// On Windows, `file_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `file_path` should be encoded as valid UTF-8.
/// On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.
/// See also `openat`.
pub fn openatZ(dir_fd: fd_t, file_path: [*:0]const u8, flags: O, mode: mode_t) OpenError!fd_t {
    if (native_os == .windows) {
        @compileError("Windows does not support POSIX; use Windows-specific API or cross-platform std.fs API");
    } else if (native_os == .wasi and !builtin.link_libc) {
        return openat(dir_fd, mem.sliceTo(file_path, 0), flags, mode);
    }

    const openat_sym = if (lfs64_abi) system.openat64 else system.openat;
    while (true) {
        const rc = openat_sym(dir_fd, file_path, flags, mode);
        switch (errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,

            .FAULT => unreachable,
            .INVAL => return error.BadPathName,
            .BADF => unreachable,
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
            .SRCH => return error.FileNotFound,
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
            .ILSEQ => return error.BadPathName,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub fn getppid() pid_t {
    return system.getppid();
}

pub const GetSockNameError = error{
    /// Insufficient resources were available in the system to perform the operation.
    SystemResources,

    /// The network subsystem has failed.
    NetworkDown,

    /// Socket hasn't been bound yet
    SocketNotBound,

    FileDescriptorNotASocket,

    /// The socket is not connected (connection-oriented sockets only).
    SocketUnconnected,
} || UnexpectedError;

pub fn getpeername(sock: socket_t, addr: *sockaddr, addrlen: *socklen_t) GetSockNameError!void {
    if (native_os == .windows) {
        @compileError("use std.Io instead");
    } else {
        const rc = system.getpeername(sock, addr, addrlen);
        switch (errno(rc)) {
            .SUCCESS => return,
            else => |err| return unexpectedErrno(err),

            .BADF => unreachable, // always a race condition
            .FAULT => unreachable,
            .INVAL => unreachable, // invalid parameters
            .NOTSOCK => return error.FileDescriptorNotASocket,
            .NOBUFS => return error.SystemResources,
            .NOTCONN => return error.SocketUnconnected,
        }
    }
}

pub const FanotifyInitError = error{
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    SystemResources,
    PermissionDenied,
    /// The kernel does not recognize the flags passed, likely because it is an
    /// older version.
    UnsupportedFlags,
} || UnexpectedError;

pub fn fanotify_init(flags: std.os.linux.fanotify.InitFlags, event_f_flags: u32) FanotifyInitError!i32 {
    const rc = system.fanotify_init(flags, event_f_flags);
    switch (errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .INVAL => return error.UnsupportedFlags,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM => return error.SystemResources,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const FanotifyMarkError = error{
    MarkAlreadyExists,
    IsDir,
    NotAssociatedWithFileSystem,
    FileNotFound,
    SystemResources,
    UserMarkQuotaExceeded,
    NotDir,
    OperationUnsupported,
    PermissionDenied,
    CrossDevice,
    NameTooLong,
} || UnexpectedError;

pub fn fanotify_mark(
    fanotify_fd: fd_t,
    flags: std.os.linux.fanotify.MarkFlags,
    mask: std.os.linux.fanotify.MarkMask,
    dirfd: fd_t,
    pathname: ?[]const u8,
) FanotifyMarkError!void {
    if (pathname) |path| {
        const path_c = try toPosixPath(path);
        return fanotify_markZ(fanotify_fd, flags, mask, dirfd, &path_c);
    } else {
        return fanotify_markZ(fanotify_fd, flags, mask, dirfd, null);
    }
}

pub fn fanotify_markZ(
    fanotify_fd: fd_t,
    flags: std.os.linux.fanotify.MarkFlags,
    mask: std.os.linux.fanotify.MarkMask,
    dirfd: fd_t,
    pathname: ?[*:0]const u8,
) FanotifyMarkError!void {
    const rc = system.fanotify_mark(fanotify_fd, flags, mask, dirfd, pathname);
    switch (errno(rc)) {
        .SUCCESS => return,
        .BADF => unreachable,
        .EXIST => return error.MarkAlreadyExists,
        .INVAL => unreachable,
        .ISDIR => return error.IsDir,
        .NODEV => return error.NotAssociatedWithFileSystem,
        .NOENT => return error.FileNotFound,
        .NOMEM => return error.SystemResources,
        .NOSPC => return error.UserMarkQuotaExceeded,
        .NOTDIR => return error.NotDir,
        .OPNOTSUPP => return error.OperationUnsupported,
        .PERM => return error.PermissionDenied,
        .XDEV => return error.CrossDevice,
        else => |err| return unexpectedErrno(err),
    }
}

pub const MMapError = error{
    /// The underlying filesystem of the specified file does not support memory mapping.
    MemoryMappingNotSupported,
    /// A file descriptor refers to a non-regular file. Or a file mapping was requested,
    /// but the file descriptor is not open for reading. Or `MAP.SHARED` was requested
    /// and `PROT_WRITE` is set, but the file descriptor is not open in `RDWR` mode.
    /// Or `PROT_WRITE` is set, but the file is append-only.
    AccessDenied,
    /// The `prot` argument asks for `PROT_EXEC` but the mapped area belongs to a file on
    /// a filesystem that was mounted no-exec.
    PermissionDenied,
    LockedMemoryLimitExceeded,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    OutOfMemory,
    /// Using FIXED_NOREPLACE flag and the process has already mapped memory at the given address
    MappingAlreadyExists,
} || UnexpectedError;

/// Map files or devices into memory.
/// `length` does not need to be aligned.
/// Use of a mapped region can result in these signals:
/// * SIGSEGV - Attempted write into a region mapped as read-only.
/// * SIGBUS - Attempted  access to a portion of the buffer that does not correspond to the file
pub fn mmap(
    ptr: ?[*]align(page_size_min) u8,
    length: usize,
    prot: PROT,
    flags: MAP,
    fd: fd_t,
    offset: u64,
) MMapError![]align(page_size_min) u8 {
    const mmap_sym = if (lfs64_abi) system.mmap64 else system.mmap;
    const rc = mmap_sym(ptr, length, prot, @bitCast(flags), fd, @bitCast(offset));
    const err: E = if (builtin.link_libc) blk: {
        if (rc != std.c.MAP_FAILED) return @as([*]align(page_size_min) u8, @ptrCast(@alignCast(rc)))[0..length];
        break :blk @enumFromInt(system._errno().*);
    } else blk: {
        const err = errno(rc);
        if (err == .SUCCESS) return @as([*]align(page_size_min) u8, @ptrFromInt(rc))[0..length];
        break :blk err;
    };
    switch (err) {
        .SUCCESS => unreachable,
        .TXTBSY => return error.AccessDenied,
        .ACCES => return error.AccessDenied,
        .PERM => return error.PermissionDenied,
        .AGAIN => return error.LockedMemoryLimitExceeded,
        .BADF => unreachable, // Always a race condition.
        .OVERFLOW => unreachable, // The number of pages used for length + offset would overflow.
        .NODEV => return error.MemoryMappingNotSupported,
        .INVAL => unreachable, // Invalid parameters to mmap()
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM => return error.OutOfMemory,
        .EXIST => return error.MappingAlreadyExists,
        else => return unexpectedErrno(err),
    }
}

/// Deletes the mappings for the specified address range, causing
/// further references to addresses within the range to generate invalid memory references.
/// Note that while POSIX allows unmapping a region in the middle of an existing mapping,
/// Zig's munmap function does not, for two reasons:
/// * It violates the Zig principle that resource deallocation must succeed.
/// * The Windows function, NtFreeVirtualMemory, has this restriction.
pub fn munmap(memory: []align(page_size_min) const u8) void {
    switch (errno(system.munmap(memory.ptr, memory.len))) {
        .SUCCESS => return,
        .INVAL => unreachable, // Invalid parameters.
        .NOMEM => unreachable, // Attempted to unmap a region in the middle of an existing mapping.
        else => |e| if (std.options.unexpected_error_tracing) {
            std.debug.panic("unexpected errno: {d} ({t})", .{ @intFromEnum(e), e });
        } else unreachable,
    }
}

pub const MRemapError = error{
    LockedMemoryLimitExceeded,
    /// Either a bug in the calling code, or the operating system abused the
    /// EINVAL error code.
    InvalidSyscallParameters,
    OutOfMemory,
} || UnexpectedError;

pub fn mremap(
    old_address: ?[*]align(page_size_min) u8,
    old_len: usize,
    new_len: usize,
    flags: system.MREMAP,
    new_address: ?[*]align(page_size_min) u8,
) MRemapError![]align(page_size_min) u8 {
    const rc = system.mremap(old_address, old_len, new_len, flags, new_address);
    const err: E = if (builtin.link_libc) blk: {
        if (rc != std.c.MAP_FAILED) return @as([*]align(page_size_min) u8, @ptrCast(@alignCast(rc)))[0..new_len];
        break :blk @enumFromInt(system._errno().*);
    } else blk: {
        const err = errno(rc);
        if (err == .SUCCESS) return @as([*]align(page_size_min) u8, @ptrFromInt(rc))[0..new_len];
        break :blk err;
    };
    switch (err) {
        .SUCCESS => unreachable,
        .AGAIN => return error.LockedMemoryLimitExceeded,
        .INVAL => return error.InvalidSyscallParameters,
        .NOMEM => return error.OutOfMemory,
        .FAULT => unreachable,
        else => return unexpectedErrno(err),
    }
}

pub const MSyncError = error{
    UnmappedMemory,
    PermissionDenied,
} || UnexpectedError;

pub fn msync(memory: []align(page_size_min) u8, flags: i32) MSyncError!void {
    switch (errno(system.msync(memory.ptr, memory.len, flags))) {
        .SUCCESS => return,
        .PERM => return error.PermissionDenied,
        .NOMEM => return error.UnmappedMemory, // Unsuccessful, provided pointer does not point mapped memory
        .INVAL => unreachable, // Invalid parameters.
        else => unreachable,
    }
}

pub const SysCtlError = error{
    PermissionDenied,
    SystemResources,
    NameTooLong,
    UnknownName,
} || UnexpectedError;

pub fn sysctl(
    name: []const c_int,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) SysCtlError!void {
    if (native_os == .wasi) {
        @compileError("sysctl not supported on WASI");
    }
    if (native_os == .haiku) {
        @compileError("sysctl not supported on Haiku");
    }

    const name_len = cast(c_uint, name.len) orelse return error.NameTooLong;
    switch (errno(system.sysctl(name.ptr, name_len, oldp, oldlenp, newp, newlen))) {
        .SUCCESS => return,
        .FAULT => unreachable,
        .PERM => return error.PermissionDenied,
        .NOMEM => return error.SystemResources,
        .NOENT => return error.UnknownName,
        else => |err| return unexpectedErrno(err),
    }
}

pub fn getSelfPhdrs() []std.elf.ElfN.Phdr {
    const getauxval = if (builtin.link_libc) std.c.getauxval else std.os.linux.getauxval;
    assert(getauxval(std.elf.AT_PHENT) == @sizeOf(std.elf.ElfN.Phdr));
    const phdrs: [*]std.elf.ElfN.Phdr = @ptrFromInt(getauxval(std.elf.AT_PHDR));
    return phdrs[0..getauxval(std.elf.AT_PHNUM)];
}

pub fn dl_iterate_phdr(
    context: anytype,
    comptime Error: type,
    comptime callback: fn (info: *dl_phdr_info, size: usize, context: @TypeOf(context)) Error!void,
) Error!void {
    const Context = @TypeOf(context);
    const elf = std.elf;
    const dl = @import("dynamic_library.zig");

    switch (builtin.object_format) {
        .elf, .c => {},
        else => @compileError("dl_iterate_phdr is not available for this target"),
    }

    if (builtin.link_libc) {
        switch (system.dl_iterate_phdr(struct {
            fn callbackC(info: *dl_phdr_info, size: usize, data: ?*anyopaque) callconv(.c) c_int {
                const context_ptr: *const Context = @ptrCast(@alignCast(data));
                callback(info, size, context_ptr.*) catch |err| return @intFromError(err);
                return 0;
            }
        }.callbackC, @ptrCast(@constCast(&context)))) {
            0 => return,
            else => |err| return @as(Error, @errorCast(@errorFromInt(@as(std.meta.Int(.unsigned, @bitSizeOf(anyerror)), @intCast(err))))),
        }
    }

    var it = dl.linkmap_iterator() catch unreachable;

    // The executable has no dynamic link segment, create a single entry for
    // the whole ELF image.
    if (it.end()) {
        const getauxval = if (builtin.link_libc) std.c.getauxval else std.os.linux.getauxval;
        const phdrs = getSelfPhdrs();
        var info: dl_phdr_info = .{
            .addr = for (phdrs) |phdr| switch (phdr.type) {
                .PHDR => break @intFromPtr(phdrs.ptr) - phdr.vaddr,
                else => {},
            } else unreachable,
            .name = switch (getauxval(std.elf.AT_EXECFN)) {
                0 => "/proc/self/exe",
                else => |name| @ptrFromInt(name),
            },
            .phdr = phdrs.ptr,
            .phnum = @intCast(phdrs.len),
        };

        return callback(&info, @sizeOf(dl_phdr_info), context);
    }

    // Last return value from the callback function.
    while (it.next()) |entry| {
        const phdrs: []elf.ElfN.Phdr = if (entry.addr != 0) phdrs: {
            const ehdr: *elf.ElfN.Ehdr = @ptrFromInt(entry.addr);
            assert(mem.eql(u8, ehdr.ident[0..4], elf.MAGIC));
            const phdrs: [*]elf.ElfN.Phdr = @ptrFromInt(entry.addr + ehdr.phoff);
            break :phdrs phdrs[0..ehdr.phnum];
        } else getSelfPhdrs();

        var info: dl_phdr_info = .{
            .addr = entry.addr,
            .name = entry.name,
            .phdr = phdrs.ptr,
            .phnum = @intCast(phdrs.len),
        };

        try callback(&info, @sizeOf(dl_phdr_info), context);
    }
}

pub const SchedGetAffinityError = error{PermissionDenied} || UnexpectedError;

pub fn sched_getaffinity(pid: pid_t) SchedGetAffinityError!cpu_set_t {
    var set: cpu_set_t = undefined;
    switch (errno(system.sched_getaffinity(pid, @sizeOf(cpu_set_t), &set))) {
        .SUCCESS => return set,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .SRCH => unreachable,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const SigaltstackError = error{
    /// The supplied stack size was less than MINSIGSTKSZ.
    SizeTooSmall,

    /// Attempted to change the signal stack while it was active.
    PermissionDenied,
} || UnexpectedError;

pub fn sigaltstack(ss: ?*const stack_t, old_ss: ?*stack_t) SigaltstackError!void {
    switch (errno(system.sigaltstack(ss, old_ss))) {
        .SUCCESS => return,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .NOMEM => return error.SizeTooSmall,
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

/// Return a filled sigset_t.
pub fn sigfillset() sigset_t {
    if (builtin.link_libc) {
        var set: sigset_t = undefined;
        switch (errno(system.sigfillset(&set))) {
            .SUCCESS => return set,
            else => unreachable,
        }
    }
    return system.sigfillset();
}

/// Return an empty sigset_t.
pub fn sigemptyset() sigset_t {
    if (builtin.link_libc) {
        var set: sigset_t = undefined;
        switch (errno(system.sigemptyset(&set))) {
            .SUCCESS => return set,
            else => unreachable,
        }
    }
    return system.sigemptyset();
}

pub fn sigaddset(set: *sigset_t, sig: SIG) void {
    if (builtin.link_libc) {
        switch (errno(system.sigaddset(set, sig))) {
            .SUCCESS => return,
            else => unreachable,
        }
    }
    system.sigaddset(set, sig);
}

pub fn sigdelset(set: *sigset_t, sig: SIG) void {
    if (builtin.link_libc) {
        switch (errno(system.sigdelset(set, sig))) {
            .SUCCESS => return,
            else => unreachable,
        }
    }
    system.sigdelset(set, sig);
}

pub fn sigismember(set: *const sigset_t, sig: SIG) bool {
    if (builtin.link_libc) {
        const rc = system.sigismember(set, sig);
        switch (errno(rc)) {
            .SUCCESS => return rc == 1,
            else => unreachable,
        }
    }
    return system.sigismember(set, sig);
}

/// Examine and change a signal action.
pub fn sigaction(sig: SIG, noalias act: ?*const Sigaction, noalias oact: ?*Sigaction) void {
    switch (errno(system.sigaction(sig, act, oact))) {
        .SUCCESS => return,
        // EINVAL means the signal is either invalid or some signal that cannot have its action
        // changed. For POSIX, this means SIGKILL/SIGSTOP. For e.g. illumos, this also includes the
        // non-standard SIGWAITING, SIGCANCEL, and SIGLWP. Either way, programmer error.
        .INVAL => unreachable,
        else => unreachable,
    }
}

/// Sets the thread signal mask.
pub fn sigprocmask(flags: u32, noalias set: ?*const sigset_t, noalias oldset: ?*sigset_t) void {
    switch (errno(system.sigprocmask(@bitCast(flags), set, oldset))) {
        .SUCCESS => return,
        .FAULT => unreachable,
        .INVAL => unreachable,
        else => unreachable,
    }
}

pub const GetHostNameError = error{PermissionDenied} || UnexpectedError;

pub fn gethostname(name_buffer: *[HOST_NAME_MAX]u8) GetHostNameError![]u8 {
    if (builtin.link_libc) {
        switch (errno(system.gethostname(name_buffer, name_buffer.len))) {
            .SUCCESS => return mem.sliceTo(name_buffer, 0),
            .FAULT => unreachable,
            .NAMETOOLONG => unreachable, // HOST_NAME_MAX prevents this
            .PERM => return error.PermissionDenied,
            else => |err| return unexpectedErrno(err),
        }
    }
    if (native_os == .linux) {
        const uts = uname();
        const hostname = mem.sliceTo(&uts.nodename, 0);
        const result = name_buffer[0..hostname.len];
        @memcpy(result, hostname);
        return result;
    }

    @compileError("TODO implement gethostname for this OS");
}

pub fn uname() utsname {
    var uts: utsname = undefined;
    switch (errno(system.uname(&uts))) {
        .SUCCESS => return uts,
        .FAULT => unreachable,
        else => unreachable,
    }
}

pub const PollError = error{
    /// The network subsystem has failed.
    NetworkDown,

    /// The kernel had no space to allocate file descriptor tables.
    SystemResources,
} || UnexpectedError;

pub fn poll(fds: []pollfd, timeout: i32) PollError!usize {
    if (native_os == .windows) {
        @compileError("use std.Io instead");
    }
    while (true) {
        const fds_count = cast(nfds_t, fds.len) orelse return error.SystemResources;
        const rc = system.poll(fds.ptr, fds_count, timeout);
        switch (errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .FAULT => unreachable,
            .INTR => continue,
            .INVAL => unreachable,
            .NOMEM => return error.SystemResources,
            else => |err| return unexpectedErrno(err),
        }
    }
    unreachable;
}

pub const PPollError = error{
    /// The operation was interrupted by a delivery of a signal before it could complete.
    SignalInterrupt,

    /// The kernel had no space to allocate file descriptor tables.
    SystemResources,
} || UnexpectedError;

pub fn ppoll(fds: []pollfd, timeout: ?*const timespec, mask: ?*const sigset_t) PPollError!usize {
    var ts: timespec = undefined;
    var ts_ptr: ?*timespec = null;
    if (timeout) |timeout_ns| {
        ts_ptr = &ts;
        ts = timeout_ns.*;
    }
    const fds_count = cast(nfds_t, fds.len) orelse return error.SystemResources;
    const rc = system.ppoll(fds.ptr, fds_count, ts_ptr, mask);
    switch (errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .FAULT => unreachable,
        .INTR => return error.SignalInterrupt,
        .INVAL => unreachable,
        .NOMEM => return error.SystemResources,
        else => |err| return unexpectedErrno(err),
    }
}

pub const SetSockOptError = error{
    /// The socket is already connected, and a specified option cannot be set while the socket is connected.
    AlreadyConnected,

    /// The option is not supported by the protocol.
    InvalidProtocolOption,

    /// The send and receive timeout values are too big to fit into the timeout fields in the socket structure.
    TimeoutTooBig,

    /// Insufficient resources are available in the system to complete the call.
    SystemResources,

    /// Setting the socket option requires more elevated permissions.
    PermissionDenied,

    OperationUnsupported,
    NetworkDown,
    FileDescriptorNotASocket,
    SocketNotBound,
    NoDevice,
} || UnexpectedError;

/// Set a socket's options.
pub fn setsockopt(fd: socket_t, level: i32, optname: u32, opt: []const u8) SetSockOptError!void {
    if (native_os == .windows) {
        @compileError("use std.Io instead");
    } else {
        switch (errno(system.setsockopt(fd, level, optname, opt.ptr, @intCast(opt.len)))) {
            .SUCCESS => {},
            .BADF => unreachable, // always a race condition
            .NOTSOCK => unreachable, // always a race condition
            .INVAL => unreachable,
            .FAULT => unreachable,
            .DOM => return error.TimeoutTooBig,
            .ISCONN => return error.AlreadyConnected,
            .NOPROTOOPT => return error.InvalidProtocolOption,
            .NOMEM => return error.SystemResources,
            .NOBUFS => return error.SystemResources,
            .PERM => return error.PermissionDenied,
            .NODEV => return error.NoDevice,
            .OPNOTSUPP => return error.OperationUnsupported,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const MemFdCreateError = error{
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
    OutOfMemory,
    /// Either the name provided exceeded `NAME_MAX`, or invalid flags were passed.
    NameTooLong,
    SystemOutdated,
} || UnexpectedError;

pub fn memfd_createZ(name: [*:0]const u8, flags: u32) MemFdCreateError!fd_t {
    switch (native_os) {
        .linux => {
            // memfd_create is available only in glibc versions starting with 2.27 and bionic versions starting with 30.
            const use_c = std.c.versionCheck(if (builtin.abi.isAndroid()) .{ .major = 30, .minor = 0, .patch = 0 } else .{ .major = 2, .minor = 27, .patch = 0 });
            const sys = if (use_c) std.c else linux;
            const rc = sys.memfd_create(name, flags);
            switch (sys.errno(rc)) {
                .SUCCESS => return @intCast(rc),
                .FAULT => unreachable, // name has invalid memory
                .INVAL => return error.NameTooLong, // or, program has a bug and flags are faulty
                .NFILE => return error.SystemFdQuotaExceeded,
                .MFILE => return error.ProcessFdQuotaExceeded,
                .NOMEM => return error.OutOfMemory,
                else => |err| return unexpectedErrno(err),
            }
        },
        .freebsd => {
            if (comptime builtin.os.version_range.semver.max.order(.{ .major = 13, .minor = 0, .patch = 0 }) == .lt)
                @compileError("memfd_create is unavailable on FreeBSD < 13.0");
            const rc = system.memfd_create(name, flags);
            switch (errno(rc)) {
                .SUCCESS => return rc,
                .BADF => unreachable, // name argument NULL
                .INVAL => unreachable, // name too long or invalid/unsupported flags.
                .MFILE => return error.ProcessFdQuotaExceeded,
                .NFILE => return error.SystemFdQuotaExceeded,
                .NOSYS => return error.SystemOutdated,
                else => |err| return unexpectedErrno(err),
            }
        },
        else => @compileError("target OS does not support memfd_create()"),
    }
}

pub fn memfd_create(name: []const u8, flags: u32) MemFdCreateError!fd_t {
    var buffer: [NAME_MAX - "memfd:".len - 1:0]u8 = undefined;
    if (name.len > buffer.len) return error.NameTooLong;
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return memfd_createZ(&buffer, flags);
}

pub fn getrusage(who: i32) rusage {
    var result: rusage = undefined;
    const rc = system.getrusage(who, &result);
    switch (errno(rc)) {
        .SUCCESS => return result,
        .INVAL => unreachable,
        .FAULT => unreachable,
        else => unreachable,
    }
}

pub const TIOCError = error{NotATerminal};

pub const TermiosGetError = TIOCError || UnexpectedError;

pub fn tcgetattr(handle: fd_t) TermiosGetError!termios {
    while (true) {
        var term: termios = undefined;
        switch (errno(system.tcgetattr(handle, &term))) {
            .SUCCESS => return term,
            .INTR => continue,
            .BADF => unreachable,
            .NOTTY => return error.NotATerminal,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const TermiosSetError = TermiosGetError || error{ProcessOrphaned};

pub fn tcsetattr(handle: fd_t, optional_action: TCSA, termios_p: termios) TermiosSetError!void {
    while (true) {
        switch (errno(system.tcsetattr(handle, optional_action, &termios_p))) {
            .SUCCESS => return,
            .BADF => unreachable,
            .INTR => continue,
            .INVAL => unreachable,
            .NOTTY => return error.NotATerminal,
            .IO => return error.ProcessOrphaned,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const TermioGetPgrpError = TIOCError || UnexpectedError;

/// Returns the process group ID for the TTY associated with the given handle.
pub fn tcgetpgrp(handle: fd_t) TermioGetPgrpError!pid_t {
    while (true) {
        var pgrp: pid_t = undefined;
        switch (errno(system.tcgetpgrp(handle, &pgrp))) {
            .SUCCESS => return pgrp,
            .BADF => unreachable,
            .INVAL => unreachable,
            .INTR => continue,
            .NOTTY => return error.NotATerminal,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const TermioSetPgrpError = TermioGetPgrpError || error{NotAPgrpMember};

/// Sets the controlling process group ID for given TTY.
/// handle must be valid fd_t to a TTY associated with calling process.
/// pgrp must be a valid process group, and the calling process must be a member
/// of that group.
pub fn tcsetpgrp(handle: fd_t, pgrp: pid_t) TermioSetPgrpError!void {
    while (true) {
        switch (errno(system.tcsetpgrp(handle, &pgrp))) {
            .SUCCESS => return,
            .BADF => unreachable,
            .INVAL => unreachable,
            .INTR => continue,
            .NOTTY => return error.NotATerminal,
            .PERM => return TermioSetPgrpError.NotAPgrpMember,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub fn signalfd(fd: fd_t, mask: *const sigset_t, flags: u32) !fd_t {
    const rc = system.signalfd(fd, mask, flags);
    switch (errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .BADF, .INVAL => unreachable,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM => return error.SystemResources,
        .MFILE => return error.ProcessResources,
        .NODEV => return error.InodeMountFail,
        else => |err| return unexpectedErrno(err),
    }
}

pub const SyncError = std.Io.File.SyncError;

/// Write all pending file contents and metadata modifications to all filesystems.
pub fn sync() void {
    system.sync();
}

/// Write all pending file contents and metadata modifications to the filesystem which contains the specified file.
pub fn syncfs(fd: fd_t) SyncError!void {
    const rc = system.syncfs(fd);
    switch (errno(rc)) {
        .SUCCESS => return,
        .BADF, .INVAL, .ROFS => unreachable,
        .IO => return error.InputOutput,
        .NOSPC => return error.NoSpaceLeft,
        .DQUOT => return error.DiskQuota,
        else => |err| return unexpectedErrno(err),
    }
}

/// Write all pending file contents for the specified file descriptor to the underlying filesystem, but not necessarily the metadata.
pub fn fdatasync(fd: fd_t) SyncError!void {
    const rc = system.fdatasync(fd);
    switch (errno(rc)) {
        .SUCCESS => return,
        .BADF, .INVAL, .ROFS => unreachable,
        .IO => return error.InputOutput,
        .NOSPC => return error.NoSpaceLeft,
        .DQUOT => return error.DiskQuota,
        else => |err| return unexpectedErrno(err),
    }
}

pub const PrctlError = error{
    /// Can only occur with PR_SET_SECCOMP/SECCOMP_MODE_FILTER or
    /// PR_SET_MM/PR_SET_MM_EXE_FILE
    AccessDenied,
    /// Can only occur with PR_SET_MM/PR_SET_MM_EXE_FILE
    InvalidFileDescriptor,
    InvalidAddress,
    /// Can only occur with PR_SET_SPECULATION_CTRL, PR_MPX_ENABLE_MANAGEMENT,
    /// or PR_MPX_DISABLE_MANAGEMENT
    UnsupportedFeature,
    /// Can only occur with PR_SET_FP_MODE
    OperationUnsupported,
    PermissionDenied,
} || UnexpectedError;

pub fn prctl(option: PR, args: anytype) PrctlError!u31 {
    if (@typeInfo(@TypeOf(args)) != .@"struct")
        @compileError("Expected tuple or struct argument, found " ++ @typeName(@TypeOf(args)));
    if (args.len > 4)
        @compileError("prctl takes a maximum of 4 optional arguments");

    var buf: [4]usize = undefined;
    {
        comptime var i = 0;
        inline while (i < args.len) : (i += 1) buf[i] = args[i];
    }

    const rc = system.prctl(@intFromEnum(option), buf[0], buf[1], buf[2], buf[3]);
    switch (errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .ACCES => return error.AccessDenied,
        .BADF => return error.InvalidFileDescriptor,
        .FAULT => return error.InvalidAddress,
        .INVAL => unreachable,
        .NODEV, .NXIO => return error.UnsupportedFeature,
        .OPNOTSUPP => return error.OperationUnsupported,
        .PERM, .BUSY => return error.PermissionDenied,
        .RANGE => unreachable,
        else => |err| return unexpectedErrno(err),
    }
}

pub const GetrlimitError = UnexpectedError;

pub fn getrlimit(resource: rlimit_resource) GetrlimitError!rlimit {
    const getrlimit_sym = if (lfs64_abi) system.getrlimit64 else system.getrlimit;

    var limits: rlimit = undefined;
    switch (errno(getrlimit_sym(resource, &limits))) {
        .SUCCESS => return limits,
        .FAULT => unreachable, // bogus pointer
        .INVAL => unreachable,
        else => |err| return unexpectedErrno(err),
    }
}

pub const SetrlimitError = error{ PermissionDenied, LimitTooBig } || UnexpectedError;

pub fn setrlimit(resource: rlimit_resource, limits: rlimit) SetrlimitError!void {
    const setrlimit_sym = if (lfs64_abi) system.setrlimit64 else system.setrlimit;

    switch (errno(setrlimit_sym(resource, &limits))) {
        .SUCCESS => return,
        .FAULT => unreachable, // bogus pointer
        .INVAL => return error.LimitTooBig, // this could also mean "invalid resource", but that would be unreachable
        .PERM => return error.PermissionDenied,
        else => |err| return unexpectedErrno(err),
    }
}

pub const MincoreError = error{
    /// A kernel resource was temporarily unavailable.
    SystemResources,
    /// vec points to an invalid address.
    InvalidAddress,
    /// addr is not page-aligned.
    InvalidSyscall,
    /// One of the following:
    /// * length is greater than user space TASK_SIZE - addr
    /// * addr + length contains unmapped memory
    OutOfMemory,
    /// The mincore syscall is not available on this version and configuration
    /// of this UNIX-like kernel.
    MincoreUnavailable,
} || UnexpectedError;

/// Determine whether pages are resident in memory.
pub fn mincore(ptr: [*]align(page_size_min) u8, length: usize, vec: [*]u8) MincoreError!void {
    return switch (errno(system.mincore(ptr, length, vec))) {
        .SUCCESS => {},
        .AGAIN => error.SystemResources,
        .FAULT => error.InvalidAddress,
        .INVAL => error.InvalidSyscall,
        .NOMEM => error.OutOfMemory,
        .NOSYS => error.MincoreUnavailable,
        else => |err| unexpectedErrno(err),
    };
}

pub const MadviseError = error{
    /// advice is MADV.REMOVE, but the specified address range is not a shared writable mapping.
    AccessDenied,
    /// advice is MADV.HWPOISON, but the caller does not have the CAP_SYS_ADMIN capability.
    PermissionDenied,
    /// A kernel resource was temporarily unavailable.
    SystemResources,
    /// One of the following:
    /// * addr is not page-aligned or length is negative
    /// * advice is not valid
    /// * advice is MADV.DONTNEED or MADV.REMOVE and the specified address range
    ///   includes locked, Huge TLB pages, or VM_PFNMAP pages.
    /// * advice is MADV.MERGEABLE or MADV.UNMERGEABLE, but the kernel was not
    ///   configured with CONFIG_KSM.
    /// * advice is MADV.FREE or MADV.WIPEONFORK but the specified address range
    ///   includes file, Huge TLB, MAP.SHARED, or VM_PFNMAP ranges.
    InvalidSyscall,
    /// (for MADV.WILLNEED) Paging in this area would exceed the process's
    /// maximum resident set size.
    WouldExceedMaximumResidentSetSize,
    /// One of the following:
    /// * (for MADV.WILLNEED) Not enough memory: paging in failed.
    /// * Addresses in the specified range are not currently mapped, or
    ///   are outside the address space of the process.
    OutOfMemory,
    /// The madvise syscall is not available on this version and configuration
    /// of the Linux kernel.
    MadviseUnavailable,
    /// The operating system returned an undocumented error code.
    Unexpected,
};

/// Give advice about use of memory.
/// This syscall is optional and is sometimes configured to be disabled.
pub fn madvise(ptr: [*]align(page_size_min) u8, length: usize, advice: u32) MadviseError!void {
    switch (errno(system.madvise(ptr, length, advice))) {
        .SUCCESS => return,
        .PERM => return error.PermissionDenied,
        .ACCES => return error.AccessDenied,
        .AGAIN => return error.SystemResources,
        .BADF => unreachable, // The map exists, but the area maps something that isn't a file.
        .INVAL => return error.InvalidSyscall,
        .IO => return error.WouldExceedMaximumResidentSetSize,
        .NOMEM => return error.OutOfMemory,
        .NOSYS => return error.MadviseUnavailable,
        else => |err| return unexpectedErrno(err),
    }
}

pub const PerfEventOpenError = error{
    /// Returned if the perf_event_attr size value is too small (smaller
    /// than PERF_ATTR_SIZE_VER0), too big (larger than the page  size),
    /// or  larger  than the kernel supports and the extra bytes are not
    /// zero.  When E2BIG is returned, the perf_event_attr size field is
    /// overwritten by the kernel to be the size of the structure it was
    /// expecting.
    TooBig,
    /// Returned when the requested event requires CAP_SYS_ADMIN permis‐
    /// sions  (or a more permissive perf_event paranoid setting).  Some
    /// common cases where an unprivileged process  may  encounter  this
    /// error:  attaching  to a process owned by a different user; moni‐
    /// toring all processes on a given CPU (i.e.,  specifying  the  pid
    /// argument  as  -1); and not setting exclude_kernel when the para‐
    /// noid setting requires it.
    /// Also:
    /// Returned on many (but not all) architectures when an unsupported
    /// exclude_hv,  exclude_idle,  exclude_user, or exclude_kernel set‐
    /// ting is specified.
    /// It can also happen, as with EACCES, when the requested event re‐
    /// quires   CAP_SYS_ADMIN   permissions   (or   a  more  permissive
    /// perf_event paranoid setting).  This includes  setting  a  break‐
    /// point on a kernel address, and (since Linux 3.13) setting a ker‐
    /// nel function-trace tracepoint.
    PermissionDenied,
    /// Returned if another event already has exclusive  access  to  the
    /// PMU.
    DeviceBusy,
    /// Each  opened  event uses one file descriptor.  If a large number
    /// of events are opened, the per-process limit  on  the  number  of
    /// open file descriptors will be reached, and no more events can be
    /// created.
    ProcessResources,
    EventRequiresUnsupportedCpuFeature,
    /// Returned if  you  try  to  add  more  breakpoint
    /// events than supported by the hardware.
    TooManyBreakpoints,
    /// Returned  if PERF_SAMPLE_STACK_USER is set in sample_type and it
    /// is not supported by hardware.
    SampleStackNotSupported,
    /// Returned if an event requiring a specific  hardware  feature  is
    /// requested  but  there is no hardware support.  This includes re‐
    /// questing low-skid events if not supported, branch tracing if  it
    /// is not available, sampling if no PMU interrupt is available, and
    /// branch stacks for software events.
    EventNotSupported,
    /// Returned  if  PERF_SAMPLE_CALLCHAIN  is   requested   and   sam‐
    /// ple_max_stack   is   larger   than   the  maximum  specified  in
    /// /proc/sys/kernel/perf_event_max_stack.
    SampleMaxStackOverflow,
    /// Returned if attempting to attach to a process that does not  exist.
    ProcessNotFound,
} || UnexpectedError;

pub fn perf_event_open(
    attr: *system.perf_event_attr,
    pid: pid_t,
    cpu: i32,
    group_fd: fd_t,
    flags: usize,
) PerfEventOpenError!fd_t {
    if (native_os == .linux) {
        // There is no syscall wrapper for this function exposed by libcs
        const rc = linux.perf_event_open(attr, pid, cpu, group_fd, flags);
        switch (linux.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .@"2BIG" => return error.TooBig,
            .ACCES => return error.PermissionDenied,
            .BADF => unreachable, // group_fd file descriptor is not valid.
            .BUSY => return error.DeviceBusy,
            .FAULT => unreachable, // Segmentation fault.
            .INVAL => unreachable, // Bad attr settings.
            .INTR => unreachable, // Mixed perf and ftrace handling for a uprobe.
            .MFILE => return error.ProcessResources,
            .NODEV => return error.EventRequiresUnsupportedCpuFeature,
            .NOENT => unreachable, // Invalid type setting.
            .NOSPC => return error.TooManyBreakpoints,
            .NOSYS => return error.SampleStackNotSupported,
            .OPNOTSUPP => return error.EventNotSupported,
            .OVERFLOW => return error.SampleMaxStackOverflow,
            .PERM => return error.PermissionDenied,
            .SRCH => return error.ProcessNotFound,
            else => |err| return unexpectedErrno(err),
        }
    }
}

pub const PtraceError = error{
    DeadLock,
    DeviceBusy,
    InputOutput,
    NameTooLong,
    OperationUnsupported,
    OutOfMemory,
    ProcessNotFound,
    PermissionDenied,
} || UnexpectedError;

pub fn ptrace(request: u32, pid: pid_t, addr: usize, data: usize) PtraceError!void {
    return switch (native_os) {
        .windows,
        .wasi,
        .emscripten,
        .haiku,
        .illumos,
        .plan9,
        => @compileError("ptrace unsupported by target OS"),

        .linux => switch (errno(if (builtin.link_libc) std.c.ptrace(
            @intCast(request),
            pid,
            @ptrFromInt(addr),
            @ptrFromInt(data),
        ) else linux.ptrace(request, pid, addr, data, 0))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .FAULT => unreachable,
            .INVAL => unreachable,
            .IO => return error.InputOutput,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            else => |err| return unexpectedErrno(err),
        },

        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (errno(std.c.ptrace(
            @enumFromInt(request),
            pid,
            @ptrFromInt(addr),
            @intCast(data),
        ))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .INVAL => unreachable,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            else => |err| return unexpectedErrno(err),
        },

        .dragonfly => switch (errno(std.c.ptrace(
            @intCast(request),
            pid,
            @ptrFromInt(addr),
            @intCast(data),
        ))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .INVAL => unreachable,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            else => |err| return unexpectedErrno(err),
        },

        .freebsd => switch (errno(std.c.ptrace(
            @intCast(request),
            pid,
            @ptrFromInt(addr),
            @intCast(data),
        ))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .INVAL => unreachable,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            .NOENT, .NOMEM => error.OutOfMemory,
            .NAMETOOLONG => error.NameTooLong,
            else => |err| return unexpectedErrno(err),
        },

        .netbsd => switch (errno(std.c.ptrace(
            @intCast(request),
            pid,
            @ptrFromInt(addr),
            @intCast(data),
        ))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .INVAL => unreachable,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            .DEADLK => error.DeadLock,
            else => |err| return unexpectedErrno(err),
        },

        .openbsd => switch (errno(std.c.ptrace(
            @intCast(request),
            pid,
            @ptrFromInt(addr),
            @intCast(data),
        ))) {
            .SUCCESS => {},
            .SRCH => error.ProcessNotFound,
            .INVAL => unreachable,
            .PERM => error.PermissionDenied,
            .BUSY => error.DeviceBusy,
            .NOTSUP => error.OperationUnsupported,
            else => |err| return unexpectedErrno(err),
        },

        else => @compileError("std.posix.ptrace unimplemented for target OS"),
    };
}

pub const NameToFileHandleAtError = error{
    FileNotFound,
    NotDir,
    OperationUnsupported,
    NameTooLong,
    Unexpected,
};

pub fn name_to_handle_at(
    dirfd: fd_t,
    pathname: []const u8,
    handle: *std.os.linux.file_handle,
    mount_id: *i32,
    flags: u32,
) NameToFileHandleAtError!void {
    const pathname_c = try toPosixPath(pathname);
    return name_to_handle_atZ(dirfd, &pathname_c, handle, mount_id, flags);
}

pub fn name_to_handle_atZ(
    dirfd: fd_t,
    pathname_z: [*:0]const u8,
    handle: *std.os.linux.file_handle,
    mount_id: *i32,
    flags: u32,
) NameToFileHandleAtError!void {
    switch (errno(system.name_to_handle_at(dirfd, pathname_z, handle, mount_id, flags))) {
        .SUCCESS => {},
        .FAULT => unreachable, // pathname, mount_id, or handle outside accessible address space
        .INVAL => unreachable, // bad flags, or handle_bytes too big
        .NOENT => return error.FileNotFound,
        .NOTDIR => return error.NotDir,
        .OPNOTSUPP => return error.OperationUnsupported,
        .OVERFLOW => return error.NameTooLong,
        else => |err| return unexpectedErrno(err),
    }
}

pub const lfs64_abi = native_os == .linux and builtin.link_libc and (builtin.abi.isGnu() or builtin.abi.isAndroid());

pub const UnexpectedError = std.Io.UnexpectedError;

/// Call this when you made a syscall or something that sets errno
/// and you get an unexpected error.
pub fn unexpectedErrno(err: E) UnexpectedError {
    if (std.options.unexpected_error_tracing) {
        std.debug.print("unexpected errno: {d}\n", .{@intFromEnum(err)});
        std.debug.dumpCurrentStackTrace(.{});
    }
    return error.Unexpected;
}

/// Used to convert a slice to a null terminated slice on the stack.
pub fn toPosixPath(file_path: []const u8) error{NameTooLong}![PATH_MAX - 1:0]u8 {
    if (std.debug.runtime_safety) assert(mem.findScalar(u8, file_path, 0) == null);
    var path_with_null: [PATH_MAX - 1:0]u8 = undefined;
    // >= rather than > to make room for the null byte
    if (file_path.len >= PATH_MAX) return error.NameTooLong;
    @memcpy(path_with_null[0..file_path.len], file_path);
    path_with_null[file_path.len] = 0;
    return path_with_null;
}
