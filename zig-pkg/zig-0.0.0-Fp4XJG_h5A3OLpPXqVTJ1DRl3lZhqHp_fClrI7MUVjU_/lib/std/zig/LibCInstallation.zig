//! See the render function implementation for documentation of the fields.
const LibCInstallation = @This();

const builtin = @import("builtin");
const is_darwin = builtin.target.os.tag.isDarwin();
const is_windows = builtin.target.os.tag == .windows;
const is_haiku = builtin.target.os.tag == .haiku;

const std = @import("std");
const Io = std.Io;
const Target = std.Target;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const Path = std.Build.Cache.Path;
const log = std.log.scoped(.libc_installation);
const Environ = std.process.Environ;

include_dir: ?[]const u8 = null,
sys_include_dir: ?[]const u8 = null,
crt_dir: ?[]const u8 = null,
msvc_lib_dir: ?[]const u8 = null,
kernel32_lib_dir: ?[]const u8 = null,
gcc_dir: ?[]const u8 = null,

pub const FindError = error{
    OutOfMemory,
    FileSystem,
    UnableToSpawnCCompiler,
    CCompilerExitCode,
    CCompilerCrashed,
    CCompilerCannotFindHeaders,
    LibCRuntimeNotFound,
    LibCStdLibHeaderNotFound,
    LibCKernel32LibNotFound,
    UnsupportedArchitecture,
    WindowsSdkNotFound,
    DarwinSdkNotFound,
    ZigIsTheCCompiler,
};

pub fn parse(allocator: Allocator, io: Io, libc_file: []const u8, target: *const std.Target) !LibCInstallation {
    var self: LibCInstallation = .{};

    const fields = std.meta.fields(LibCInstallation);
    const FoundKey = struct {
        found: bool,
        allocated: ?[:0]u8,
    };
    var found_keys = [1]FoundKey{FoundKey{ .found = false, .allocated = null }} ** fields.len;
    errdefer {
        self = .{};
        for (found_keys) |found_key| {
            if (found_key.allocated) |s| allocator.free(s);
        }
    }

    const contents = try Io.Dir.cwd().readFileAlloc(io, libc_file, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(contents);

    var it = std.mem.tokenizeScalar(u8, contents, '\n');
    while (it.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var line_it = std.mem.splitScalar(u8, line, '=');
        const name = line_it.first();
        const value = line_it.rest();
        inline for (fields, 0..) |field, i| {
            if (std.mem.eql(u8, name, field.name)) {
                found_keys[i].found = true;
                if (value.len == 0) {
                    @field(self, field.name) = null;
                } else {
                    found_keys[i].allocated = try allocator.dupeZ(u8, value);
                    @field(self, field.name) = found_keys[i].allocated;
                }
                break;
            }
        }
    }
    inline for (fields, 0..) |field, i| {
        if (!found_keys[i].found) {
            log.err("missing field: {s}", .{field.name});
            return error.ParseError;
        }
    }
    if (self.include_dir == null) {
        log.err("include_dir may not be empty", .{});
        return error.ParseError;
    }
    if (self.sys_include_dir == null) {
        log.err("sys_include_dir may not be empty", .{});
        return error.ParseError;
    }

    const os_tag = target.os.tag;
    if (self.crt_dir == null and !target.os.tag.isDarwin()) {
        log.err("crt_dir may not be empty for {s}", .{@tagName(os_tag)});
        return error.ParseError;
    }

    if (self.msvc_lib_dir == null and os_tag == .windows and (target.abi == .msvc or target.abi == .itanium)) {
        log.err("msvc_lib_dir may not be empty for {s}-{s}", .{
            @tagName(os_tag),
            @tagName(target.abi),
        });
        return error.ParseError;
    }
    if (self.kernel32_lib_dir == null and os_tag == .windows and (target.abi == .msvc or target.abi == .itanium)) {
        log.err("kernel32_lib_dir may not be empty for {s}-{s}", .{
            @tagName(os_tag),
            @tagName(target.abi),
        });
        return error.ParseError;
    }

    if (self.gcc_dir == null and os_tag == .haiku) {
        log.err("gcc_dir may not be empty for {s}", .{@tagName(os_tag)});
        return error.ParseError;
    }

    return self;
}

pub fn render(self: LibCInstallation, out: *std.Io.Writer) !void {
    @setEvalBranchQuota(4000);
    const include_dir = self.include_dir orelse "";
    const sys_include_dir = self.sys_include_dir orelse "";
    const crt_dir = self.crt_dir orelse "";
    const msvc_lib_dir = self.msvc_lib_dir orelse "";
    const kernel32_lib_dir = self.kernel32_lib_dir orelse "";
    const gcc_dir = self.gcc_dir orelse "";

    try out.print(
        \\# The directory that contains `stdlib.h`.
        \\# On POSIX-like systems, include directories be found with: `cc -E -Wp,-v -xc /dev/null`
        \\include_dir={s}
        \\
        \\# The system-specific include directory. May be the same as `include_dir`.
        \\# On Windows it's the directory that includes `vcruntime.h`.
        \\# On POSIX it's the directory that includes `sys/errno.h`.
        \\sys_include_dir={s}
        \\
        \\# The directory that contains `crt1.o` or `crt2.o`.
        \\# On POSIX, can be found with `cc -print-file-name=crt1.o`.
        \\# Not needed when targeting MacOS.
        \\crt_dir={s}
        \\
        \\# The directory that contains `vcruntime.lib`.
        \\# Only needed when targeting MSVC on Windows.
        \\msvc_lib_dir={s}
        \\
        \\# The directory that contains `kernel32.lib`.
        \\# Only needed when targeting MSVC on Windows.
        \\kernel32_lib_dir={s}
        \\
        \\# The directory that contains `crtbeginS.o` and `crtendS.o`
        \\# Only needed when targeting Haiku.
        \\gcc_dir={s}
        \\
    , .{
        include_dir,
        sys_include_dir,
        crt_dir,
        msvc_lib_dir,
        kernel32_lib_dir,
        gcc_dir,
    });
}

pub const FindNativeOptions = struct {
    target: *const std.Target,
    environ_map: *const Environ.Map,

    /// If enabled, will print human-friendly errors to stderr.
    verbose: bool = false,
};

/// Finds the default, native libc.
pub fn findNative(gpa: Allocator, io: Io, args: FindNativeOptions) FindError!LibCInstallation {
    var self: LibCInstallation = .{};

    if (is_darwin and args.target.os.tag.isDarwin()) {
        if (!std.zig.system.darwin.isSdkInstalled(gpa, io))
            return error.DarwinSdkNotFound;
        const sdk = std.zig.system.darwin.getSdk(gpa, io, args.target) orelse
            return error.DarwinSdkNotFound;
        defer gpa.free(sdk);

        self.include_dir = try fs.path.join(gpa, &.{
            sdk, "usr/include",
        });
        self.sys_include_dir = try fs.path.join(gpa, &.{
            sdk, "usr/include",
        });
        return self;
    } else if (is_windows) {
        const sdk = std.zig.WindowsSdk.find(gpa, io, args.target.cpu.arch, args.environ_map) catch |err| switch (err) {
            error.NotFound => return error.WindowsSdkNotFound,
            error.PathTooLong => return error.WindowsSdkNotFound,
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer sdk.free(gpa);

        try self.findNativeMsvcIncludeDir(gpa, io, sdk);
        try self.findNativeMsvcLibDir(gpa, sdk);
        try self.findNativeKernel32LibDir(gpa, io, args, sdk);
        try self.findNativeIncludeDirWindows(gpa, io, sdk);
        try self.findNativeCrtDirWindows(gpa, io, args.target, sdk);
    } else if (is_haiku) {
        try self.findNativeIncludeDirPosix(gpa, io, args);
        try self.findNativeGccDirHaiku(gpa, io, args);
        self.crt_dir = try gpa.dupe(u8, "/system/develop/lib");
    } else if (builtin.target.os.tag == .illumos) {
        // There is only one libc, and its headers/libraries are always in the same spot.
        self.include_dir = try gpa.dupe(u8, "/usr/include");
        self.sys_include_dir = try gpa.dupe(u8, "/usr/include");
        self.crt_dir = try gpa.dupe(u8, "/usr/lib/64");
    } else if (std.process.can_spawn) {
        try self.findNativeIncludeDirPosix(gpa, io, args);
        switch (builtin.target.os.tag) {
            .freebsd, .netbsd, .openbsd, .dragonfly => self.crt_dir = try gpa.dupe(u8, "/usr/lib"),
            .linux => try self.findNativeCrtDirPosix(gpa, io, args),
            else => {},
        }
    } else {
        return error.LibCRuntimeNotFound;
    }
    return self;
}

/// Must be the same allocator passed to `parse` or `findNative`.
pub fn deinit(self: *LibCInstallation, allocator: Allocator) void {
    const fields = std.meta.fields(LibCInstallation);
    inline for (fields) |field| {
        if (@field(self, field.name)) |payload| {
            allocator.free(payload);
        }
    }
    self.* = undefined;
}

fn findNativeIncludeDirPosix(self: *LibCInstallation, gpa: Allocator, io: Io, args: FindNativeOptions) FindError!void {
    // Detect infinite loops.
    var environ_map = try args.environ_map.clone(gpa);
    defer environ_map.deinit();
    const skip_cc_env_var = if (environ_map.get(inf_loop_env_key)) |phase| blk: {
        if (std.mem.eql(u8, phase, "1")) {
            try environ_map.put(inf_loop_env_key, "2");
            break :blk true;
        } else {
            return error.ZigIsTheCCompiler;
        }
    } else blk: {
        try environ_map.put(inf_loop_env_key, "1");
        break :blk false;
    };

    const dev_null = if (is_windows) "nul" else "/dev/null";

    var argv = std.array_list.Managed([]const u8).init(gpa);
    defer argv.deinit();

    try appendCcExe(&argv, skip_cc_env_var, &environ_map);
    try argv.appendSlice(&.{
        "-E",
        "-Wp,-v",
        "-xc",
        dev_null,
    });

    const run_res = std.process.run(gpa, io, .{
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .argv = argv.items,
        .environ_map = &environ_map,
        // Some C compilers, such as Clang, are known to rely on argv[0] to find the path
        // to their own executable, without even bothering to resolve PATH. This results in the message:
        // error: unable to execute command: Executable "" doesn't exist!
        // So we use the expandArg0 variant of ChildProcess to give them a helping hand.
        .expand_arg0 = .expand,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            printVerboseInvocation(argv.items, null, args.verbose, null);
            return error.UnableToSpawnCCompiler;
        },
    };
    defer {
        gpa.free(run_res.stdout);
        gpa.free(run_res.stderr);
    }
    switch (run_res.term) {
        .exited => |code| if (code != 0) {
            printVerboseInvocation(argv.items, null, args.verbose, run_res.stderr);
            return error.CCompilerExitCode;
        },
        else => {
            printVerboseInvocation(argv.items, null, args.verbose, run_res.stderr);
            return error.CCompilerCrashed;
        },
    }

    var it = std.mem.tokenizeAny(u8, run_res.stderr, "\n\r");
    var search_paths = std.array_list.Managed([]const u8).init(gpa);
    defer search_paths.deinit();
    while (it.next()) |line| {
        if (line.len != 0 and line[0] == ' ') {
            try search_paths.append(line);
        }
    }
    if (search_paths.items.len == 0) {
        return error.CCompilerCannotFindHeaders;
    }

    const include_dir_example_file = if (is_haiku) "posix/stdlib.h" else "stdlib.h";
    const sys_include_dir_example_file = if (is_windows)
        "sys\\types.h"
    else if (is_haiku)
        "errno.h"
    else
        "sys/errno.h";

    var path_i: usize = 0;
    while (path_i < search_paths.items.len) : (path_i += 1) {
        // search in reverse order
        const search_path_untrimmed = search_paths.items[search_paths.items.len - path_i - 1];
        const search_path = std.mem.trimStart(u8, search_path_untrimmed, " ");
        var search_dir = Io.Dir.cwd().openDir(io, search_path, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.NoDevice,
            => continue,

            else => return error.FileSystem,
        };
        defer search_dir.close(io);

        if (self.include_dir == null) {
            if (search_dir.access(io, include_dir_example_file, .{})) |_| {
                self.include_dir = try gpa.dupe(u8, search_path);
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => return error.FileSystem,
            }
        }

        if (self.sys_include_dir == null) {
            if (search_dir.access(io, sys_include_dir_example_file, .{})) |_| {
                self.sys_include_dir = try gpa.dupe(u8, search_path);
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => return error.FileSystem,
            }
        }

        if (self.include_dir != null and self.sys_include_dir != null) {
            // Success.
            return;
        }
    }

    return error.LibCStdLibHeaderNotFound;
}

fn findNativeIncludeDirWindows(
    self: *LibCInstallation,
    gpa: Allocator,
    io: Io,
    sdk: std.zig.WindowsSdk,
) FindError!void {
    var install_buf: [2]std.zig.WindowsSdk.Installation = undefined;
    const installs = fillInstallations(&install_buf, sdk);

    var result_buf = std.array_list.Managed(u8).init(gpa);
    defer result_buf.deinit();

    for (installs) |install| {
        result_buf.shrinkAndFree(0);
        try result_buf.print("{s}\\Include\\{s}\\ucrt", .{ install.path, install.version });

        var dir = Io.Dir.cwd().openDir(io, result_buf.items, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.NoDevice,
            => continue,

            else => return error.FileSystem,
        };
        defer dir.close(io);

        dir.access(io, "stdlib.h", .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return error.FileSystem,
        };

        self.include_dir = try result_buf.toOwnedSlice();
        return;
    }

    return error.LibCStdLibHeaderNotFound;
}

fn findNativeCrtDirWindows(
    self: *LibCInstallation,
    gpa: Allocator,
    io: Io,
    target: *const std.Target,
    sdk: std.zig.WindowsSdk,
) FindError!void {
    var install_buf: [2]std.zig.WindowsSdk.Installation = undefined;
    const installs = fillInstallations(&install_buf, sdk);

    var result_buf = std.array_list.Managed(u8).init(gpa);
    defer result_buf.deinit();

    const arch_sub_dir = switch (target.cpu.arch) {
        .x86 => "x86",
        .x86_64 => "x64",
        .arm, .armeb => "arm",
        .aarch64 => "arm64",
        else => return error.UnsupportedArchitecture,
    };

    for (installs) |install| {
        result_buf.shrinkAndFree(0);
        try result_buf.print("{s}\\Lib\\{s}\\ucrt\\{s}", .{ install.path, install.version, arch_sub_dir });

        var dir = Io.Dir.cwd().openDir(io, result_buf.items, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.NoDevice,
            => continue,

            else => return error.FileSystem,
        };
        defer dir.close(io);

        dir.access(io, "ucrt.lib", .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return error.FileSystem,
        };

        self.crt_dir = try result_buf.toOwnedSlice();
        return;
    }
    return error.LibCRuntimeNotFound;
}

fn findNativeCrtDirPosix(self: *LibCInstallation, gpa: Allocator, io: Io, args: FindNativeOptions) FindError!void {
    self.crt_dir = try ccPrintFileName(gpa, io, .{
        .environ_map = args.environ_map,
        .search_basename = switch (args.target.os.tag) {
            .linux => if (args.target.abi.isAndroid()) "crtbegin_dynamic.o" else "crt1.o",
            else => "crt1.o",
        },
        .want_dirname = .only_dir,
        .verbose = args.verbose,
    });
}

fn findNativeGccDirHaiku(self: *LibCInstallation, gpa: Allocator, io: Io, args: FindNativeOptions) FindError!void {
    self.gcc_dir = try ccPrintFileName(gpa, io, .{
        .search_basename = "crtbeginS.o",
        .want_dirname = .only_dir,
        .verbose = args.verbose,
    });
}

fn findNativeKernel32LibDir(
    self: *LibCInstallation,
    gpa: Allocator,
    io: Io,
    args: FindNativeOptions,
    sdk: std.zig.WindowsSdk,
) FindError!void {
    var install_buf: [2]std.zig.WindowsSdk.Installation = undefined;
    const installs = fillInstallations(&install_buf, sdk);

    var result_buf = std.array_list.Managed(u8).init(gpa);
    defer result_buf.deinit();

    const arch_sub_dir = switch (args.target.cpu.arch) {
        .x86 => "x86",
        .x86_64 => "x64",
        .arm, .armeb => "arm",
        .aarch64 => "arm64",
        else => return error.UnsupportedArchitecture,
    };

    for (installs) |install| {
        result_buf.shrinkAndFree(0);
        try result_buf.print("{s}\\Lib\\{s}\\um\\{s}", .{ install.path, install.version, arch_sub_dir });

        var dir = Io.Dir.cwd().openDir(io, result_buf.items, .{}) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.NoDevice,
            => continue,

            else => return error.FileSystem,
        };
        defer dir.close(io);

        dir.access(io, "kernel32.lib", .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return error.FileSystem,
        };

        self.kernel32_lib_dir = try result_buf.toOwnedSlice();
        return;
    }
    return error.LibCKernel32LibNotFound;
}

fn findNativeMsvcIncludeDir(
    self: *LibCInstallation,
    gpa: Allocator,
    io: Io,
    sdk: std.zig.WindowsSdk,
) FindError!void {
    const msvc_lib_dir = sdk.msvc_lib_dir orelse return error.LibCStdLibHeaderNotFound;
    const up1 = fs.path.dirname(msvc_lib_dir) orelse return error.LibCStdLibHeaderNotFound;
    const up2 = fs.path.dirname(up1) orelse return error.LibCStdLibHeaderNotFound;

    const dir_path = try fs.path.join(gpa, &[_][]const u8{ up2, "include" });
    errdefer gpa.free(dir_path);

    var dir = Io.Dir.cwd().openDir(io, dir_path, .{}) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        error.NoDevice,
        => return error.LibCStdLibHeaderNotFound,

        else => return error.FileSystem,
    };
    defer dir.close(io);

    dir.access(io, "vcruntime.h", .{}) catch |err| switch (err) {
        error.FileNotFound => return error.LibCStdLibHeaderNotFound,
        else => return error.FileSystem,
    };

    self.sys_include_dir = dir_path;
}

fn findNativeMsvcLibDir(
    self: *LibCInstallation,
    gpa: Allocator,
    sdk: std.zig.WindowsSdk,
) FindError!void {
    const msvc_lib_dir = sdk.msvc_lib_dir orelse return error.LibCRuntimeNotFound;
    self.msvc_lib_dir = try gpa.dupe(u8, msvc_lib_dir);
}

pub const CCPrintFileNameOptions = struct {
    environ_map: *const Environ.Map,
    search_basename: []const u8,
    want_dirname: enum { full_path, only_dir },
    verbose: bool = false,
};

/// caller owns returned memory
fn ccPrintFileName(gpa: Allocator, io: Io, args: CCPrintFileNameOptions) ![]u8 {
    // Detect infinite loops.
    var environ_map = try args.environ_map.clone(gpa);
    defer environ_map.deinit();
    const skip_cc_env_var = if (environ_map.get(inf_loop_env_key)) |phase| blk: {
        if (std.mem.eql(u8, phase, "1")) {
            try environ_map.put(inf_loop_env_key, "2");
            break :blk true;
        } else {
            return error.ZigIsTheCCompiler;
        }
    } else blk: {
        try environ_map.put(inf_loop_env_key, "1");
        break :blk false;
    };

    var argv = std.array_list.Managed([]const u8).init(gpa);
    defer argv.deinit();

    const arg1 = try std.fmt.allocPrint(gpa, "-print-file-name={s}", .{args.search_basename});
    defer gpa.free(arg1);

    try appendCcExe(&argv, skip_cc_env_var, &environ_map);
    try argv.append(arg1);

    const run_res = std.process.run(gpa, io, .{
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .argv = argv.items,
        .environ_map = &environ_map,
        // Some C compilers, such as Clang, are known to rely on argv[0] to find the path
        // to their own executable, without even bothering to resolve PATH. This results in the message:
        // error: unable to execute command: Executable "" doesn't exist!
        // So we use the expandArg0 variant of ChildProcess to give them a helping hand.
        .expand_arg0 = .expand,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.UnableToSpawnCCompiler,
    };
    defer {
        gpa.free(run_res.stdout);
        gpa.free(run_res.stderr);
    }
    switch (run_res.term) {
        .exited => |code| if (code != 0) {
            printVerboseInvocation(argv.items, args.search_basename, args.verbose, run_res.stderr);
            return error.CCompilerExitCode;
        },
        else => {
            printVerboseInvocation(argv.items, args.search_basename, args.verbose, run_res.stderr);
            return error.CCompilerCrashed;
        },
    }

    var it = std.mem.tokenizeAny(u8, run_res.stdout, "\n\r");
    const line = it.next() orelse return error.LibCRuntimeNotFound;
    // When this command fails, it returns exit code 0 and duplicates the input file name.
    // So we detect failure by checking if the output matches exactly the input.
    if (std.mem.eql(u8, line, args.search_basename)) return error.LibCRuntimeNotFound;
    switch (args.want_dirname) {
        .full_path => return gpa.dupe(u8, line),
        .only_dir => {
            const dirname = fs.path.dirname(line) orelse return error.LibCRuntimeNotFound;
            return gpa.dupe(u8, dirname);
        },
    }
}

fn printVerboseInvocation(
    argv: []const []const u8,
    search_basename: ?[]const u8,
    verbose: bool,
    stderr: ?[]const u8,
) void {
    if (!verbose) return;

    if (search_basename) |s| {
        std.debug.print("Zig attempted to find the file '{s}' by executing this command:\n", .{s});
    } else {
        std.debug.print("Zig attempted to find the path to native system libc headers by executing this command:\n", .{});
    }
    for (argv, 0..) |arg, i| {
        if (i != 0) std.debug.print(" ", .{});
        std.debug.print("{s}", .{arg});
    }
    std.debug.print("\n", .{});
    if (stderr) |s| {
        std.debug.print("Output:\n==========\n{s}\n==========\n", .{s});
    }
}

fn fillInstallations(
    installs: *[2]std.zig.WindowsSdk.Installation,
    sdk: std.zig.WindowsSdk,
) []std.zig.WindowsSdk.Installation {
    var installs_len: usize = 0;
    if (sdk.windows10sdk) |windows10sdk| {
        installs[installs_len] = windows10sdk;
        installs_len += 1;
    }
    if (sdk.windows81sdk) |windows81sdk| {
        installs[installs_len] = windows81sdk;
        installs_len += 1;
    }
    return installs[0..installs_len];
}

const inf_loop_env_key = "ZIG_IS_DETECTING_LIBC_PATHS";

fn appendCcExe(
    args: *std.array_list.Managed([]const u8),
    skip_cc_env_var: bool,
    environ_map: *const Environ.Map,
) !void {
    const default_cc_exe = if (is_windows) "cc.exe" else "cc";
    try args.ensureUnusedCapacity(1);
    if (skip_cc_env_var) {
        args.appendAssumeCapacity(default_cc_exe);
        return;
    }
    const cc_env_var = std.zig.EnvVar.CC.get(environ_map) orelse {
        args.appendAssumeCapacity(default_cc_exe);
        return;
    };
    // Respect space-separated flags to the C compiler.
    var it = std.mem.tokenizeScalar(u8, cc_env_var, ' ');
    while (it.next()) |arg| {
        try args.append(arg);
    }
}

/// These are basenames. This data is produced with a pure function. See also
/// `CsuPaths`.
pub const CrtBasenames = struct {
    crt0: ?[]const u8 = null,
    crti: ?[]const u8 = null,
    crtbegin: ?[]const u8 = null,
    crtend: ?[]const u8 = null,
    crtn: ?[]const u8 = null,

    pub const GetArgs = struct {
        target: *const std.Target,
        link_libc: bool,
        output_mode: std.builtin.OutputMode,
        link_mode: std.builtin.LinkMode,
        pie: bool,
    };

    /// Determine file system path names of C runtime startup objects for supported
    /// link modes.
    pub fn get(args: GetArgs) CrtBasenames {
        // crt objects are only required for libc.
        if (!args.link_libc) return .{};

        // Flatten crt cases.
        const mode: enum {
            dynamic_lib,
            dynamic_exe,
            dynamic_pie,
            static_exe,
            static_pie,
        } = switch (args.output_mode) {
            .Obj => return .{},
            .Lib => switch (args.link_mode) {
                .dynamic => .dynamic_lib,
                .static => return .{},
            },
            .Exe => switch (args.link_mode) {
                .dynamic => if (args.pie) .dynamic_pie else .dynamic_exe,
                .static => if (args.pie) .static_pie else .static_exe,
            },
        };

        const target = args.target;

        if (target.abi.isAndroid()) return switch (mode) {
            .dynamic_lib => .{
                .crtbegin = "crtbegin_so.o",
                .crtend = "crtend_so.o",
            },
            .dynamic_exe, .dynamic_pie => .{
                .crtbegin = "crtbegin_dynamic.o",
                .crtend = "crtend_android.o",
            },
            .static_exe, .static_pie => .{
                .crtbegin = "crtbegin_static.o",
                .crtend = "crtend_android.o",
            },
        };

        return switch (target.os.tag) {
            .linux => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .dynamic_pie => .{
                    .crt0 = "Scrt1.o",
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .static_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .static_pie => .{
                    .crt0 = "rcrt1.o",
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
            },
            .dragonfly => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .dynamic_pie => .{
                    .crt0 = "Scrt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .static_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .static_pie => .{
                    .crt0 = "Scrt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
            },
            .freebsd => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .dynamic_pie => .{
                    .crt0 = "Scrt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .static_exe => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginT.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .static_pie => .{
                    .crt0 = "Scrt1.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
            },
            .netbsd => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe => .{
                    .crt0 = "crt0.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .dynamic_pie => .{
                    .crt0 = "crt0.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .static_exe => .{
                    .crt0 = "crt0.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginT.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .static_pie => .{
                    .crt0 = "crt0.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginT.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
            },
            .openbsd => switch (mode) {
                .dynamic_lib => .{
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                },
                .dynamic_exe, .dynamic_pie => .{
                    .crt0 = "crt0.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                },
                .static_exe, .static_pie => .{
                    .crt0 = "rcrt0.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                },
            },
            .haiku => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe => .{
                    .crt0 = "start_dyn.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .dynamic_pie => .{
                    .crt0 = "start_dyn.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
                .static_exe => .{
                    .crt0 = "start_dyn.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbegin.o",
                    .crtend = "crtend.o",
                    .crtn = "crtn.o",
                },
                .static_pie => .{
                    .crt0 = "start_dyn.o",
                    .crti = "crti.o",
                    .crtbegin = "crtbeginS.o",
                    .crtend = "crtendS.o",
                    .crtn = "crtn.o",
                },
            },
            .illumos => switch (mode) {
                .dynamic_lib => .{
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .dynamic_exe, .dynamic_pie => .{
                    .crt0 = "crt1.o",
                    .crti = "crti.o",
                    .crtn = "crtn.o",
                },
                .static_exe, .static_pie => .{},
            },
            else => .{},
        };
    }
};

pub const CrtPaths = struct {
    crt0: ?Path = null,
    crti: ?Path = null,
    crtbegin: ?Path = null,
    crtend: ?Path = null,
    crtn: ?Path = null,
};

pub fn resolveCrtPaths(
    lci: LibCInstallation,
    arena: Allocator,
    crt_basenames: CrtBasenames,
    target: *const std.Target,
) error{ OutOfMemory, LibCInstallationMissingCrtDir }!CrtPaths {
    const crt_dir_path: Path = .{
        .root_dir = std.Build.Cache.Directory.cwd(),
        .sub_path = lci.crt_dir orelse return error.LibCInstallationMissingCrtDir,
    };
    switch (target.os.tag) {
        .dragonfly => {
            const gccv: []const u8 = if (target.os.version_range.semver.isAtLeast(.{
                .major = 5,
                .minor = 4,
                .patch = 0,
            }) orelse true) "gcc80" else "gcc54";
            return .{
                .crt0 = if (crt_basenames.crt0) |basename| try crt_dir_path.join(arena, basename) else null,
                .crti = if (crt_basenames.crti) |basename| try crt_dir_path.join(arena, basename) else null,
                .crtbegin = if (crt_basenames.crtbegin) |basename| .{
                    .root_dir = crt_dir_path.root_dir,
                    .sub_path = try fs.path.join(arena, &.{ crt_dir_path.sub_path, gccv, basename }),
                } else null,
                .crtend = if (crt_basenames.crtend) |basename| .{
                    .root_dir = crt_dir_path.root_dir,
                    .sub_path = try fs.path.join(arena, &.{ crt_dir_path.sub_path, gccv, basename }),
                } else null,
                .crtn = if (crt_basenames.crtn) |basename| try crt_dir_path.join(arena, basename) else null,
            };
        },
        .haiku => {
            const gcc_dir_path: Path = .{
                .root_dir = std.Build.Cache.Directory.cwd(),
                .sub_path = lci.gcc_dir orelse return error.LibCInstallationMissingCrtDir,
            };
            return .{
                .crt0 = if (crt_basenames.crt0) |basename| try crt_dir_path.join(arena, basename) else null,
                .crti = if (crt_basenames.crti) |basename| try crt_dir_path.join(arena, basename) else null,
                .crtbegin = if (crt_basenames.crtbegin) |basename| try gcc_dir_path.join(arena, basename) else null,
                .crtend = if (crt_basenames.crtend) |basename| try gcc_dir_path.join(arena, basename) else null,
                .crtn = if (crt_basenames.crtn) |basename| try crt_dir_path.join(arena, basename) else null,
            };
        },
        else => {
            return .{
                .crt0 = if (crt_basenames.crt0) |basename| try crt_dir_path.join(arena, basename) else null,
                .crti = if (crt_basenames.crti) |basename| try crt_dir_path.join(arena, basename) else null,
                .crtbegin = if (crt_basenames.crtbegin) |basename| try crt_dir_path.join(arena, basename) else null,
                .crtend = if (crt_basenames.crtend) |basename| try crt_dir_path.join(arena, basename) else null,
                .crtn = if (crt_basenames.crtn) |basename| try crt_dir_path.join(arena, basename) else null,
            };
        },
    }
}
