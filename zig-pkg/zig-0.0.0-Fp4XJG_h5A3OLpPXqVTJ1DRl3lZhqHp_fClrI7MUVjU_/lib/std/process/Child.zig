const Child = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Io = std.Io;
const process = std.process;
const File = std.Io.File;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Id = switch (native_os) {
    .windows => std.os.windows.HANDLE,
    .wasi => void,
    else => std.posix.pid_t,
};

/// After `wait` or `kill` is called, this becomes `null`.
/// On Windows this is the hProcess.
/// On POSIX this is the pid.
id: ?Id,
thread_handle: if (native_os == .windows) std.os.windows.HANDLE else void,
/// The writing end of the child process's standard input pipe.
/// Usage requires `process.SpawnOptions.StdIo.pipe`.
stdin: ?File,
/// The reading end of the child process's standard output pipe.
/// Usage requires `process.SpawnOptions.StdIo.pipe`.
stdout: ?File,
/// The reading end of the child process's standard error pipe.
/// Usage requires `process.SpawnOptions.StdIo.pipe`.
stderr: ?File,
/// This is available after calling wait if
/// `request_resource_usage_statistics` was set to `true` before calling
/// `spawn`.
/// TODO move this data into `Term`
resource_usage_statistics: ResourceUsageStatistics = .{},
request_resource_usage_statistics: bool,

pub const ResourceUsageStatistics = struct {
    rusage: @TypeOf(rusage_init) = rusage_init,

    /// Returns the peak resident set size of the child process, in bytes,
    /// if available.
    pub inline fn getMaxRss(rus: ResourceUsageStatistics) ?usize {
        switch (native_os) {
            .dragonfly, .freebsd, .netbsd, .openbsd, .illumos, .linux, .serenity => {
                if (rus.rusage) |ru| {
                    return @as(usize, @intCast(ru.maxrss)) * 1024;
                } else {
                    return null;
                }
            },
            .windows => {
                if (rus.rusage) |ru| {
                    return ru.PeakWorkingSetSize;
                } else {
                    return null;
                }
            },
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
                if (rus.rusage) |ru| {
                    // Darwin oddly reports in bytes instead of kilobytes.
                    return @as(usize, @intCast(ru.maxrss));
                } else {
                    return null;
                }
            },
            else => return null,
        }
    }

    const rusage_init = switch (native_os) {
        .dragonfly,
        .freebsd,
        .netbsd,
        .openbsd,
        .illumos,
        .linux,
        .serenity,
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        => @as(?std.posix.rusage, null),
        .windows => @as(?std.os.windows.PROCESS.VM_COUNTERS, null),
        else => {},
    };
};

pub const Term = union(enum) {
    exited: u8,
    signal: std.posix.SIG,
    stopped: std.posix.SIG,
    unknown: u32,
};

pub const Cwd = union(enum) {
    /// CWD of the child is the same as the current CWD.
    inherit,
    /// On POSIX systems, `fchdir` is called after `fork` using this handle.
    /// On Windows, the path is inferred from the provided handle and that path is used when calling `CreateProcessW`.
    dir: Io.Dir,
    /// On POSIX systems, `chdir` is called after `fork` using this path.
    /// On Windows, this path is used when calling `CreateProcessW`.
    path: []const u8,
};

/// Requests for the operating system to forcibly terminate the child process,
/// then blocks until it terminates, then cleans up all resources.
///
/// Idempotent and does nothing after `wait` returns.
///
/// Uncancelable. Ignores unexpected errors from the operating system.
pub fn kill(child: *Child, io: Io) void {
    if (child.id == null) {
        assert(child.stdin == null);
        assert(child.stdout == null);
        assert(child.stderr == null);
        return;
    }
    io.vtable.childKill(io.userdata, child);
    assert(child.id == null);
}

pub const WaitError = error{
    AccessDenied,
} || Io.Cancelable || Io.UnexpectedError;

/// Blocks until child process terminates and then cleans up all resources.
pub fn wait(child: *Child, io: Io) WaitError!Term {
    assert(child.id != null);
    return io.vtable.childWait(io.userdata, child);
}
