const Step = @This();
const builtin = @import("builtin");

const std = @import("../std.zig");
const Io = std.Io;
const Build = std.Build;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Cache = Build.Cache;
const Path = Cache.Path;
const ArrayList = std.ArrayList;

id: Id,
name: []const u8,
owner: *Build,
makeFn: MakeFn,

dependencies: std.array_list.Managed(*Step),
/// This field is empty during execution of the user's build script, and
/// then populated during dependency loop checking in the build runner.
dependants: ArrayList(*Step),
/// Collects the set of files that retrigger this step to run.
///
/// This is used by the build system's implementation of `--watch` but it can
/// also be potentially useful for IDEs to know what effects editing a
/// particular file has.
///
/// Populated within `make`. Implementation may choose to clear and repopulate,
/// retain previous value, or update.
inputs: Inputs,

/// Set this field to declare an upper bound on the amount of bytes of memory it will
/// take to run the step. Zero means no limit.
///
/// The idea to annotate steps that might use a high amount of RAM with an
/// upper bound. For example, perhaps a particular set of unit tests require 4
/// GiB of RAM, and those tests will be run under 4 different build
/// configurations at once. This would potentially require 16 GiB of memory on
/// the system if all 4 steps executed simultaneously, which could easily be
/// greater than what is actually available, potentially causing the system to
/// crash when using `zig build` at the default concurrency level.
///
/// This field causes the build runner to do two things:
/// 1. ulimit child processes, so that they will fail if it would exceed this
/// memory limit. This serves to enforce that this upper bound value is
/// correct.
/// 2. Ensure that the set of concurrent steps at any given time have a total
/// max_rss value that does not exceed the `max_total_rss` value of the build
/// runner. This value is configurable on the command line, and defaults to the
/// total system memory available.
max_rss: usize,

state: State,
pending_deps: u32,

result_error_msgs: ArrayList([]const u8),
result_error_bundle: std.zig.ErrorBundle,
result_stderr: []const u8,
result_cached: bool,
result_duration_ns: ?u64,
/// 0 means unavailable or not reported.
result_peak_rss: usize,
/// If the step is failed and this field is populated, this is the command which failed.
/// This field may be populated even if the step succeeded.
result_failed_command: ?[]const u8,
test_results: TestResults,

/// The return address associated with creation of this step that can be useful
/// to print along with debugging messages.
debug_stack_trace: std.debug.StackTrace,

pub const TestResults = struct {
    /// The total number of tests in the step. Every test has a "status" from the following:
    /// * passed
    /// * skipped
    /// * failed cleanly
    /// * crashed
    /// * timed out
    test_count: u32 = 0,

    /// The number of tests which were skipped (`error.SkipZigTest`).
    skip_count: u32 = 0,
    /// The number of tests which failed cleanly.
    fail_count: u32 = 0,
    /// The number of tests which terminated unexpectedly, i.e. crashed.
    crash_count: u32 = 0,
    /// The number of tests which timed out.
    timeout_count: u32 = 0,

    /// The number of detected memory leaks. The associated test may still have passed; indeed, *all*
    /// individual tests may have passed. However, the step as a whole fails if any test has leaks.
    leak_count: u32 = 0,
    /// The number of detected error logs. The associated test may still have passed; indeed, *all*
    /// individual tests may have passed. However, the step as a whole fails if any test logs errors.
    log_err_count: u32 = 0,

    pub fn isSuccess(tr: TestResults) bool {
        // all steps are success or skip
        return tr.fail_count == 0 and
            tr.crash_count == 0 and
            tr.timeout_count == 0 and
            // no (otherwise successful) step leaked memory or logged errors
            tr.leak_count == 0 and
            tr.log_err_count == 0;
    }

    /// Computes the number of tests which passed from the other values.
    pub fn passCount(tr: TestResults) u32 {
        return tr.test_count - tr.skip_count - tr.fail_count - tr.crash_count - tr.timeout_count;
    }
};

pub const MakeOptions = struct {
    progress_node: std.Progress.Node,
    watch: bool,
    web_server: ?*Build.WebServer,
    /// If set, this is a timeout to enforce on all individual unit tests, in nanoseconds.
    unit_test_timeout_ns: ?u64,
    /// Not to be confused with `Build.allocator`, which is an alias of `Build.graph.arena`.
    gpa: Allocator,
};

pub const MakeFn = *const fn (step: *Step, options: MakeOptions) anyerror!void;

pub const State = enum {
    precheck_unstarted,
    precheck_started,
    /// This is also used to indicate "dirty" steps that have been modified
    /// after a previous build completed, in which case, the step may or may
    /// not have been completed before. Either way, one or more of its direct
    /// file system inputs have been modified, meaning that the step needs to
    /// be re-evaluated.
    precheck_done,
    dependency_failure,
    success,
    failure,
    /// This state indicates that the step did not complete, however, it also did not fail,
    /// and it is safe to continue executing its dependencies.
    skipped,
    /// This step was skipped because it specified a max_rss that exceeded the runner's maximum.
    /// It is not safe to run its dependencies.
    skipped_oom,
};

pub const Id = enum {
    top_level,
    compile,
    install_artifact,
    install_file,
    install_dir,
    remove_dir,
    fail,
    fmt,
    translate_c,
    write_file,
    update_source_files,
    run,
    check_file,
    check_object,
    config_header,
    objcopy,
    options,
    custom,

    pub fn Type(comptime id: Id) type {
        return switch (id) {
            .top_level => Build.TopLevelStep,
            .compile => Compile,
            .install_artifact => InstallArtifact,
            .install_file => InstallFile,
            .install_dir => InstallDir,
            .fail => Fail,
            .fmt => Fmt,
            .translate_c => TranslateC,
            .write_file => WriteFile,
            .update_source_files => UpdateSourceFiles,
            .run => Run,
            .check_file => CheckFile,
            .check_object => CheckObject,
            .config_header => ConfigHeader,
            .objcopy => ObjCopy,
            .options => Options,
            .custom => @compileError("no type available for custom step"),
        };
    }
};

pub const CheckFile = @import("Step/CheckFile.zig");
pub const CheckObject = @import("Step/CheckObject.zig");
pub const ConfigHeader = @import("Step/ConfigHeader.zig");
pub const Fail = @import("Step/Fail.zig");
pub const Fmt = @import("Step/Fmt.zig");
pub const InstallArtifact = @import("Step/InstallArtifact.zig");
pub const InstallDir = @import("Step/InstallDir.zig");
pub const InstallFile = @import("Step/InstallFile.zig");
pub const ObjCopy = @import("Step/ObjCopy.zig");
pub const Compile = @import("Step/Compile.zig");
pub const Options = @import("Step/Options.zig");
pub const Run = @import("Step/Run.zig");
pub const TranslateC = @import("Step/TranslateC.zig");
pub const WriteFile = @import("Step/WriteFile.zig");
pub const UpdateSourceFiles = @import("Step/UpdateSourceFiles.zig");

pub const Inputs = struct {
    table: Table,

    pub const init: Inputs = .{
        .table = .{},
    };

    pub const Table = std.ArrayHashMapUnmanaged(Build.Cache.Path, Files, Build.Cache.Path.TableAdapter, false);
    /// The special file name "." means any changes inside the directory.
    pub const Files = ArrayList([]const u8);

    pub fn populated(inputs: *Inputs) bool {
        return inputs.table.count() != 0;
    }

    pub fn clear(inputs: *Inputs, gpa: Allocator) void {
        for (inputs.table.values()) |*files| files.deinit(gpa);
        inputs.table.clearRetainingCapacity();
    }
};

pub const StepOptions = struct {
    id: Id,
    name: []const u8,
    owner: *Build,
    makeFn: MakeFn = makeNoOp,
    first_ret_addr: ?usize = null,
    max_rss: usize = 0,
};

pub fn init(options: StepOptions) Step {
    const arena = options.owner.allocator;

    return .{
        .id = options.id,
        .name = arena.dupe(u8, options.name) catch @panic("OOM"),
        .owner = options.owner,
        .makeFn = options.makeFn,
        .dependencies = std.array_list.Managed(*Step).init(arena),
        .dependants = .empty,
        .inputs = Inputs.init,
        .state = .precheck_unstarted,
        .pending_deps = undefined, // initialized by build runner
        .max_rss = options.max_rss,
        .debug_stack_trace = blk: {
            const addr_buf = arena.alloc(usize, options.owner.debug_stack_frames_count) catch @panic("OOM");
            const first_ret_addr = options.first_ret_addr orelse @returnAddress();
            break :blk std.debug.captureCurrentStackTrace(.{ .first_address = first_ret_addr }, addr_buf);
        },
        .result_error_msgs = .empty,
        .result_error_bundle = std.zig.ErrorBundle.empty,
        .result_stderr = "",
        .result_cached = false,
        .result_duration_ns = null,
        .result_peak_rss = 0,
        .result_failed_command = null,
        .test_results = .{},
    };
}

/// If the Step's `make` function reports `error.MakeFailed`, it indicates they
/// have already reported the error. Otherwise, we add a simple error report
/// here.
pub fn make(s: *Step, options: MakeOptions) error{ MakeFailed, MakeSkipped }!void {
    const arena = s.owner.allocator;
    const graph = s.owner.graph;
    const io = graph.io;

    var start_ts: ?Io.Timestamp = t: {
        if (!graph.time_report) break :t null;
        if (s.id == .compile) break :t null;
        if (s.id == .run and s.cast(Run).?.stdio == .zig_test) break :t null;
        break :t Io.Clock.awake.now(io);
    };
    const make_result = s.makeFn(s, options);
    if (start_ts) |*ts| {
        const duration = ts.untilNow(io, .awake);
        options.web_server.?.updateTimeReportGeneric(s, duration);
    }

    make_result catch |err| switch (err) {
        error.MakeFailed => return error.MakeFailed,
        error.MakeSkipped => return error.MakeSkipped,
        else => {
            s.result_error_msgs.append(arena, @errorName(err)) catch @panic("OOM");
            return error.MakeFailed;
        },
    };

    if (!s.test_results.isSuccess()) {
        return error.MakeFailed;
    }

    if (s.max_rss != 0 and s.result_peak_rss > s.max_rss) {
        const msg = std.fmt.allocPrint(arena, "memory usage peaked at {0B:.2} ({0d} bytes), exceeding the declared upper bound of {1B:.2} ({1d} bytes)", .{
            s.result_peak_rss, s.max_rss,
        }) catch @panic("OOM");
        s.result_error_msgs.append(arena, msg) catch @panic("OOM");
    }
}

pub fn dependOn(step: *Step, other: *Step) void {
    step.dependencies.append(other) catch @panic("OOM");
}

fn makeNoOp(step: *Step, options: MakeOptions) anyerror!void {
    _ = options;

    var all_cached = true;

    for (step.dependencies.items) |dep| {
        all_cached = all_cached and dep.result_cached;
    }

    step.result_cached = all_cached;
}

pub fn cast(step: *Step, comptime T: type) ?*T {
    if (step.id == T.base_id) {
        return @fieldParentPtr("step", step);
    }
    return null;
}

/// For debugging purposes, prints identifying information about this Step.
pub fn dump(step: *Step, t: Io.Terminal) void {
    const w = t.writer;
    if (step.debug_stack_trace.return_addresses.len > 0) {
        w.print("name: '{s}'. creation stack trace:\n", .{step.name}) catch {};
        std.debug.writeStackTrace(&step.debug_stack_trace, t) catch {};
    } else {
        const field = "debug_stack_frames_count";
        comptime assert(@hasField(Build, field));
        t.setColor(.yellow) catch {};
        w.print("name: '{s}'. no stack trace collected for this step, see std.Build." ++ field ++ "\n", .{step.name}) catch {};
        t.setColor(.reset) catch {};
    }
}

/// Populates `s.result_failed_command`.
pub fn captureChildProcess(
    s: *Step,
    gpa: Allocator,
    progress_node: std.Progress.Node,
    argv: []const []const u8,
) !std.process.RunResult {
    const graph = s.owner.graph;
    const arena = graph.arena;
    const io = graph.io;

    // If an error occurs, it's happened in this command:
    assert(s.result_failed_command == null);
    s.result_failed_command = try allocPrintCmd(gpa, .inherit, null, argv);

    try handleChildProcUnsupported(s);
    try handleVerbose(s.owner, .inherit, argv);

    const result = std.process.run(arena, io, .{
        .argv = argv,
        .environ_map = &graph.environ_map,
        .progress_node = progress_node,
    }) catch |err| return s.fail("failed to run {s}: {t}", .{ argv[0], err });

    if (result.stderr.len > 0) {
        try s.result_error_msgs.append(arena, result.stderr);
    }

    return result;
}

pub fn fail(step: *Step, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, MakeFailed } {
    try step.addError(fmt, args);
    return error.MakeFailed;
}

pub fn addError(step: *Step, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
    const arena = step.owner.allocator;
    const msg = try std.fmt.allocPrint(arena, fmt, args);
    try step.result_error_msgs.append(arena, msg);
}

pub const ZigProcess = struct {
    child: std.process.Child,
    multi_reader_buffer: Io.File.MultiReader.Buffer(2),
    multi_reader: Io.File.MultiReader,
    progress_ipc_index: ?if (std.Progress.have_ipc) std.Progress.Ipc.Index else noreturn,

    pub const StreamEnum = enum { stdout, stderr };

    pub fn saveState(zp: *ZigProcess, prog_node: std.Progress.Node) void {
        zp.progress_ipc_index = if (std.Progress.have_ipc) prog_node.takeIpcIndex() else null;
    }

    pub fn deinit(zp: *ZigProcess, io: Io) void {
        zp.child.kill(io);
        zp.multi_reader.deinit();
        zp.* = undefined;
    }
};

/// Assumes that argv contains `--listen=-` and that the process being spawned
/// is the zig compiler - the same version that compiled the build runner.
/// Populates `s.result_failed_command`.
pub fn evalZigProcess(
    s: *Step,
    argv: []const []const u8,
    prog_node: std.Progress.Node,
    watch: bool,
    web_server: ?*Build.WebServer,
    gpa: Allocator,
) !?Path {
    const b = s.owner;
    const io = b.graph.io;

    // If an error occurs, it's happened in this command:
    assert(s.result_failed_command == null);
    s.result_failed_command = try allocPrintCmd(gpa, .inherit, null, argv);

    if (s.getZigProcess()) |zp| update: {
        assert(watch);
        if (zp.progress_ipc_index) |ipc_index| prog_node.setIpcIndex(ipc_index);
        zp.progress_ipc_index = null;
        var exited = false;
        defer if (exited) {
            s.cast(Compile).?.zig_process = null;
            zp.deinit(io);
            gpa.destroy(zp);
        } else zp.saveState(prog_node);
        const result = zigProcessUpdate(s, zp, watch, web_server, gpa) catch |err| switch (err) {
            error.BrokenPipe, error.EndOfStream => |reason| {
                std.log.info("{s} restart required: {t}", .{ argv[0], reason });
                // Process restart required.
                const term = zp.child.wait(io) catch |e| {
                    return s.fail("unable to wait for {s}: {t}", .{ argv[0], e });
                };
                _ = term;
                exited = true;
                break :update;
            },
            else => |e| return e,
        };

        if (s.result_error_bundle.errorMessageCount() > 0) {
            return s.fail("{d} compilation errors", .{s.result_error_bundle.errorMessageCount()});
        }

        if (s.result_error_msgs.items.len > 0 and result == null) {
            // Crash detected.
            const term = zp.child.wait(io) catch |e| {
                return s.fail("unable to wait for {s}: {t}", .{ argv[0], e });
            };
            s.result_peak_rss = zp.child.resource_usage_statistics.getMaxRss() orelse 0;
            exited = true;
            try handleChildProcessTerm(s, term);
            return error.MakeFailed;
        }

        return result;
    }
    assert(argv.len != 0);

    try handleChildProcUnsupported(s);
    try handleVerbose(s.owner, .inherit, argv);

    const zp = try gpa.create(ZigProcess);
    defer if (!watch) gpa.destroy(zp);

    zp.child = std.process.spawn(io, .{
        .argv = argv,
        .environ_map = &b.graph.environ_map,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .request_resource_usage_statistics = true,
        .progress_node = prog_node,
    }) catch |err| return s.fail("failed to spawn zig compiler {s}: {t}", .{ argv[0], err });

    zp.multi_reader.init(gpa, io, zp.multi_reader_buffer.toStreams(), &.{
        zp.child.stdout.?, zp.child.stderr.?,
    });
    if (watch) s.cast(Compile).?.zig_process = zp;
    defer if (!watch) zp.deinit(io);

    const result = result: {
        defer if (watch) zp.saveState(prog_node);
        break :result try zigProcessUpdate(s, zp, watch, web_server, gpa);
    };

    if (!watch) {
        // Send EOF to stdin.
        zp.child.stdin.?.close(io);
        zp.child.stdin = null;

        const term = zp.child.wait(io) catch |err| {
            return s.fail("unable to wait for {s}: {t}", .{ argv[0], err });
        };
        s.result_peak_rss = zp.child.resource_usage_statistics.getMaxRss() orelse 0;

        // Special handling for Compile step that is expecting compile errors.
        if (s.cast(Compile)) |compile| switch (term) {
            .exited => {
                // Note that the exit code may be 0 in this case due to the
                // compiler server protocol.
                if (compile.expect_errors != null) {
                    return error.NeedCompileErrorCheck;
                }
            },
            else => {},
        };

        try handleChildProcessTerm(s, term);
    }

    if (s.result_error_bundle.errorMessageCount() > 0) {
        return s.fail("{d} compilation errors", .{s.result_error_bundle.errorMessageCount()});
    }

    return result;
}

/// Wrapper around `Io.Dir.updateFile` that handles verbose and error output.
pub fn installFile(s: *Step, src_lazy_path: Build.LazyPath, dest_path: []const u8) !Io.Dir.PrevStatus {
    const b = s.owner;
    const io = b.graph.io;
    const src_path = src_lazy_path.getPath3(b, s);
    try handleVerbose(b, .inherit, &.{ "install", "-C", b.fmt("{f}", .{src_path}), dest_path });
    return Io.Dir.updateFile(src_path.root_dir.handle, io, src_path.sub_path, .cwd(), dest_path, .{}) catch |err|
        return s.fail("unable to update file from '{f}' to '{s}': {t}", .{ src_path, dest_path, err });
}

/// Wrapper around `Io.Dir.createDirPathStatus` that handles verbose and error output.
pub fn installDir(s: *Step, dest_path: []const u8) !Io.Dir.CreatePathStatus {
    const b = s.owner;
    const io = b.graph.io;
    try handleVerbose(b, .inherit, &.{ "install", "-d", dest_path });
    return Io.Dir.cwd().createDirPathStatus(io, dest_path, .default_dir) catch |err|
        return s.fail("unable to create dir '{s}': {t}", .{ dest_path, err });
}

fn zigProcessUpdate(s: *Step, zp: *ZigProcess, watch: bool, web_server: ?*Build.WebServer, gpa: Allocator) !?Path {
    const b = s.owner;
    const arena = b.allocator;
    const io = b.graph.io;

    const start_ts = Io.Clock.awake.now(io);

    try sendMessage(io, zp.child.stdin.?, .update);
    if (!watch) try sendMessage(io, zp.child.stdin.?, .exit);

    var result: ?Path = null;
    var eos_err: error{EndOfStream}!void = {};

    const stdout = zp.multi_reader.fileReader(0);

    while (true) {
        const Header = std.zig.Server.Message.Header;
        const header = stdout.interface.takeStruct(Header, .little) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdout.err.?,
        };
        const body = stdout.interface.take(header.bytes_len) catch |err| switch (err) {
            error.EndOfStream => |e| {
                // Better to report the crash with stderr below, but we set
                // this in case the child exits successfully while violating
                // this protocol.
                eos_err = e;
                break;
            },
            error.ReadFailed => return stdout.err.?,
        };
        switch (header.tag) {
            .zig_version => {
                if (!std.mem.eql(u8, builtin.zig_version_string, body)) {
                    return s.fail(
                        "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                        .{ builtin.zig_version_string, body },
                    );
                }
            },
            .error_bundle => {
                s.result_error_bundle = try std.zig.Server.allocErrorBundle(gpa, body);
                // This message indicates the end of the update.
                if (watch) break;
            },
            .emit_digest => {
                const EmitDigest = std.zig.Server.Message.EmitDigest;
                const emit_digest: *align(1) const EmitDigest = @ptrCast(body);
                s.result_cached = emit_digest.flags.cache_hit;
                const digest = body[@sizeOf(EmitDigest)..][0..Cache.bin_digest_len];
                result = .{
                    .root_dir = b.cache_root,
                    .sub_path = try arena.dupe(u8, "o" ++ std.fs.path.sep_str ++ Cache.binToHex(digest.*)),
                };
            },
            .file_system_inputs => {
                s.clearWatchInputs();
                var it = std.mem.splitScalar(u8, body, 0);
                while (it.next()) |prefixed_path| {
                    const prefix_index: std.zig.Server.Message.PathPrefix = @enumFromInt(prefixed_path[0] - 1);
                    const sub_path = try arena.dupe(u8, prefixed_path[1..]);
                    const sub_path_dirname = std.fs.path.dirname(sub_path) orelse "";
                    switch (prefix_index) {
                        .cwd => {
                            const path: Build.Cache.Path = .{
                                .root_dir = Build.Cache.Directory.cwd(),
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, path, std.fs.path.basename(sub_path));
                        },
                        .zig_lib => zl: {
                            if (s.cast(Step.Compile)) |compile| {
                                if (compile.zig_lib_dir) |zig_lib_dir| {
                                    const lp = try zig_lib_dir.join(arena, sub_path);
                                    try addWatchInput(s, lp);
                                    break :zl;
                                }
                            }
                            const path: Build.Cache.Path = .{
                                .root_dir = s.owner.graph.zig_lib_directory,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, path, std.fs.path.basename(sub_path));
                        },
                        .local_cache => {
                            const path: Build.Cache.Path = .{
                                .root_dir = b.cache_root,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, path, std.fs.path.basename(sub_path));
                        },
                        .global_cache => {
                            const path: Build.Cache.Path = .{
                                .root_dir = s.owner.graph.global_cache_root,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, path, std.fs.path.basename(sub_path));
                        },
                    }
                }
            },
            .time_report => if (web_server) |ws| {
                const TimeReport = std.zig.Server.Message.TimeReport;
                const tr: *align(1) const TimeReport = @ptrCast(body[0..@sizeOf(TimeReport)]);
                ws.updateTimeReportCompile(.{
                    .compile = s.cast(Step.Compile).?,
                    .use_llvm = tr.flags.use_llvm,
                    .stats = tr.stats,
                    .ns_total = @intCast(start_ts.untilNow(io, .awake).toNanoseconds()),
                    .llvm_pass_timings_len = tr.llvm_pass_timings_len,
                    .files_len = tr.files_len,
                    .decls_len = tr.decls_len,
                    .trailing = body[@sizeOf(TimeReport)..],
                });
            },
            else => {}, // ignore other messages
        }
    }

    s.result_duration_ns = @intCast(start_ts.untilNow(io, .awake).toNanoseconds());

    const stderr_contents = zp.multi_reader.reader(1).buffered();
    if (stderr_contents.len > 0) {
        try s.result_error_msgs.append(arena, try arena.dupe(u8, stderr_contents));
    }

    try eos_err;

    return result;
}

pub fn getZigProcess(s: *Step) ?*ZigProcess {
    return switch (s.id) {
        .compile => s.cast(Compile).?.zig_process,
        else => null,
    };
}

fn sendMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 0,
    };
    var w = file.writer(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

pub fn handleVerbose(
    b: *Build,
    cwd: std.process.Child.Cwd,
    argv: []const []const u8,
) error{OutOfMemory}!void {
    return handleVerbose2(b, cwd, null, argv);
}

pub fn handleVerbose2(
    b: *Build,
    cwd: std.process.Child.Cwd,
    opt_env: ?*const std.process.Environ.Map,
    argv: []const []const u8,
) error{OutOfMemory}!void {
    if (b.verbose) {
        const graph = b.graph;
        // Intention of verbose is to print all sub-process command lines to
        // stderr before spawning them.
        const text = try allocPrintCmd(b.allocator, cwd, if (opt_env) |env| .{
            .child = env,
            .parent = &graph.environ_map,
        } else null, argv);
        std.debug.print("{s}\n", .{text});
    }
}

/// Asserts that the caller has already populated `s.result_failed_command`.
pub inline fn handleChildProcUnsupported(s: *Step) error{ OutOfMemory, MakeFailed }!void {
    if (!std.process.can_spawn) {
        return s.fail("unable to spawn process: host cannot spawn child processes", .{});
    }
}

/// Asserts that the caller has already populated `s.result_failed_command`.
pub fn handleChildProcessTerm(s: *Step, term: std.process.Child.Term) error{ MakeFailed, OutOfMemory }!void {
    assert(s.result_failed_command != null);
    return switch (term) {
        .exited => |code| if (code != 0) s.fail("process exited with error code {d}", .{code}),
        .signal => |sig| s.fail("process terminated with signal {t}", .{sig}),
        .stopped => |sig| s.fail("process stopped with signal {t}", .{sig}),
        .unknown => s.fail("process terminated unexpectedly", .{}),
    };
}

pub fn allocPrintCmd(
    gpa: Allocator,
    cwd: std.process.Child.Cwd,
    opt_env: ?struct {
        child: *const std.process.Environ.Map,
        parent: *const std.process.Environ.Map,
    },
    argv: []const []const u8,
) Allocator.Error![]u8 {
    const shell = struct {
        fn escape(writer: *Io.Writer, string: []const u8, is_argv0: bool) !void {
            for (string) |c| {
                if (switch (c) {
                    else => true,
                    '%', '+'...':', '@'...'Z', '_', 'a'...'z' => false,
                    '=' => is_argv0,
                }) break;
            } else return writer.writeAll(string);

            try writer.writeByte('"');
            for (string) |c| {
                if (switch (c) {
                    std.ascii.control_code.nul => break,
                    '!', '"', '$', '\\', '`' => true,
                    else => !std.ascii.isPrint(c),
                }) try writer.writeByte('\\');
                switch (c) {
                    std.ascii.control_code.nul => unreachable,
                    std.ascii.control_code.bel => try writer.writeByte('a'),
                    std.ascii.control_code.bs => try writer.writeByte('b'),
                    std.ascii.control_code.ht => try writer.writeByte('t'),
                    std.ascii.control_code.lf => try writer.writeByte('n'),
                    std.ascii.control_code.vt => try writer.writeByte('v'),
                    std.ascii.control_code.ff => try writer.writeByte('f'),
                    std.ascii.control_code.cr => try writer.writeByte('r'),
                    std.ascii.control_code.esc => try writer.writeByte('E'),
                    ' '...'~' => try writer.writeByte(c),
                    else => try writer.print("{o:0>3}", .{c}),
                }
            }
            try writer.writeByte('"');
        }
    };

    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    const writer = &aw.writer;
    switch (cwd) {
        .inherit => {},
        .path => |path| writer.print("cd {s} && ", .{path}) catch return error.OutOfMemory,
        .dir => @panic("TODO"),
    }
    if (opt_env) |env| {
        var it = env.child.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (env.parent.get(key)) |process_value| {
                if (std.mem.eql(u8, value, process_value)) continue;
            }
            writer.print("{s}=", .{key}) catch return error.OutOfMemory;
            shell.escape(writer, value, false) catch return error.OutOfMemory;
            writer.writeByte(' ') catch return error.OutOfMemory;
        }
    }
    shell.escape(writer, argv[0], true) catch return error.OutOfMemory;
    for (argv[1..]) |arg| {
        writer.writeByte(' ') catch return error.OutOfMemory;
        shell.escape(writer, arg, false) catch return error.OutOfMemory;
    }
    return aw.toOwnedSlice();
}

/// Prefer `cacheHitAndWatch` unless you already added watch inputs
/// separately from using the cache system.
pub fn cacheHit(s: *Step, man: *Build.Cache.Manifest) !bool {
    s.result_cached = man.hit() catch |err| return failWithCacheError(s, man, err);
    return s.result_cached;
}

/// Clears previous watch inputs, if any, and then populates watch inputs from
/// the full set of files picked up by the cache manifest.
///
/// Must be accompanied with `writeManifestAndWatch`.
pub fn cacheHitAndWatch(s: *Step, man: *Build.Cache.Manifest) !bool {
    const is_hit = man.hit() catch |err| return failWithCacheError(s, man, err);
    s.result_cached = is_hit;
    // The above call to hit() populates the manifest with files, so in case of
    // a hit, we need to populate watch inputs.
    if (is_hit) try setWatchInputsFromManifest(s, man);
    return is_hit;
}

fn failWithCacheError(
    s: *Step,
    man: *const Build.Cache.Manifest,
    err: Build.Cache.Manifest.HitError,
) error{ OutOfMemory, Canceled, MakeFailed } {
    switch (err) {
        error.CacheCheckFailed => switch (man.diagnostic) {
            .none => unreachable,
            .manifest_create, .manifest_read, .manifest_lock => |e| return s.fail("failed to check cache: {t} {t}", .{
                man.diagnostic, e,
            }),
            .file_open, .file_stat, .file_read, .file_hash => |op| {
                const pp = man.files.keys()[op.file_index].prefixed_path;
                const prefix = man.cache.prefixes()[pp.prefix].path orelse "";
                return s.fail("failed to check cache: '{s}{c}{s}' {t} {t}", .{
                    prefix, std.fs.path.sep, pp.sub_path, man.diagnostic, op.err,
                });
            },
        },
        error.OutOfMemory => return error.OutOfMemory,
        error.Canceled => return error.Canceled,
        error.InvalidFormat => return s.fail("failed to check cache: invalid manifest file format", .{}),
    }
}

/// Prefer `writeManifestAndWatch` unless you already added watch inputs
/// separately from using the cache system.
pub fn writeManifest(s: *Step, man: *Build.Cache.Manifest) !void {
    if (s.test_results.isSuccess()) {
        man.writeManifest() catch |err| {
            try s.addError("unable to write cache manifest: {t}", .{err});
        };
    }
}

/// Clears previous watch inputs, if any, and then populates watch inputs from
/// the full set of files picked up by the cache manifest.
///
/// Must be accompanied with `cacheHitAndWatch`.
pub fn writeManifestAndWatch(s: *Step, man: *Build.Cache.Manifest) !void {
    try writeManifest(s, man);
    try setWatchInputsFromManifest(s, man);
}

fn setWatchInputsFromManifest(s: *Step, man: *Build.Cache.Manifest) !void {
    const arena = s.owner.allocator;
    const prefixes = man.cache.prefixes();
    clearWatchInputs(s);
    for (man.files.keys()) |file| {
        // The file path data is freed when the cache manifest is cleaned up at the end of `make`.
        const sub_path = try arena.dupe(u8, file.prefixed_path.sub_path);
        try addWatchInputFromPath(s, .{
            .root_dir = prefixes[file.prefixed_path.prefix],
            .sub_path = std.fs.path.dirname(sub_path) orelse "",
        }, std.fs.path.basename(sub_path));
    }
}

/// For steps that have a single input that never changes when re-running `make`.
pub fn singleUnchangingWatchInput(step: *Step, lazy_path: Build.LazyPath) Allocator.Error!void {
    if (!step.inputs.populated()) try step.addWatchInput(lazy_path);
}

pub fn clearWatchInputs(step: *Step) void {
    const gpa = step.owner.allocator;
    step.inputs.clear(gpa);
}

/// Places a *file* dependency on the path.
pub fn addWatchInput(step: *Step, lazy_file: Build.LazyPath) Allocator.Error!void {
    switch (lazy_file) {
        .src_path => |src_path| try addWatchInputFromBuilder(step, src_path.owner, src_path.sub_path),
        .dependency => |d| try addWatchInputFromBuilder(step, d.dependency.builder, d.sub_path),
        .cwd_relative => |path_string| {
            try addWatchInputFromPath(step, .{
                .root_dir = .{
                    .path = null,
                    .handle = Io.Dir.cwd(),
                },
                .sub_path = std.fs.path.dirname(path_string) orelse "",
            }, std.fs.path.basename(path_string));
        },
        // Nothing to watch because this dependency edge is modeled instead via `dependants`.
        .generated => {},
    }
}

/// Any changes inside the directory will trigger invalidation.
///
/// See also `addDirectoryWatchInputFromPath` which takes a `Build.Cache.Path` instead.
///
/// Paths derived from this directory should also be manually added via
/// `addDirectoryWatchInputFromPath` if and only if this function returns
/// `true`.
pub fn addDirectoryWatchInput(step: *Step, lazy_directory: Build.LazyPath) Allocator.Error!bool {
    switch (lazy_directory) {
        .src_path => |src_path| try addDirectoryWatchInputFromBuilder(step, src_path.owner, src_path.sub_path),
        .dependency => |d| try addDirectoryWatchInputFromBuilder(step, d.dependency.builder, d.sub_path),
        .cwd_relative => |path_string| {
            try addDirectoryWatchInputFromPath(step, .{
                .root_dir = .{
                    .path = null,
                    .handle = Io.Dir.cwd(),
                },
                .sub_path = path_string,
            });
        },
        // Nothing to watch because this dependency edge is modeled instead via `dependants`.
        .generated => return false,
    }
    return true;
}

/// Any changes inside the directory will trigger invalidation.
///
/// See also `addDirectoryWatchInput` which takes a `Build.LazyPath` instead.
///
/// This function should only be called when it has been verified that the
/// dependency on `path` is not already accounted for by a `Step` dependency.
/// In other words, before calling this function, first check that the
/// `Build.LazyPath` which this `path` is derived from is not `generated`.
pub fn addDirectoryWatchInputFromPath(step: *Step, path: Build.Cache.Path) !void {
    return addWatchInputFromPath(step, path, ".");
}

fn addWatchInputFromBuilder(step: *Step, builder: *Build, sub_path: []const u8) !void {
    return addWatchInputFromPath(step, .{
        .root_dir = builder.build_root,
        .sub_path = std.fs.path.dirname(sub_path) orelse "",
    }, std.fs.path.basename(sub_path));
}

fn addDirectoryWatchInputFromBuilder(step: *Step, builder: *Build, sub_path: []const u8) !void {
    return addDirectoryWatchInputFromPath(step, .{
        .root_dir = builder.build_root,
        .sub_path = sub_path,
    });
}

fn addWatchInputFromPath(step: *Step, path: Build.Cache.Path, basename: []const u8) !void {
    const gpa = step.owner.allocator;
    const gop = try step.inputs.table.getOrPut(gpa, path);
    if (!gop.found_existing) gop.value_ptr.* = .empty;
    try gop.value_ptr.append(gpa, basename);
}

/// Implementation detail of file watching and forced rebuilds. Prepares the step for being re-evaluated.
pub fn reset(step: *Step, gpa: Allocator) void {
    assert(step.state == .precheck_done);

    if (step.result_failed_command) |cmd| gpa.free(cmd);

    step.result_error_msgs.clearRetainingCapacity();
    step.result_stderr = "";
    step.result_cached = false;
    step.result_duration_ns = null;
    step.result_peak_rss = 0;
    step.result_failed_command = null;
    step.test_results = .{};

    step.result_error_bundle.deinit(gpa);
    step.result_error_bundle = std.zig.ErrorBundle.empty;
}

/// Implementation detail of file watching. Prepares the step for being re-evaluated.
/// Returns `true` if the step was newly invalidated, `false` if it was already invalidated.
pub fn invalidateResult(step: *Step, gpa: Allocator) bool {
    if (step.state == .precheck_done) return false;
    assert(step.pending_deps == 0);
    step.state = .precheck_done;
    step.reset(gpa);
    for (step.dependants.items) |dependant| {
        _ = dependant.invalidateResult(gpa);
        dependant.pending_deps += 1;
    }
    return true;
}

test {
    _ = CheckFile;
    _ = CheckObject;
    _ = Fail;
    _ = Fmt;
    _ = InstallArtifact;
    _ = InstallDir;
    _ = InstallFile;
    _ = ObjCopy;
    _ = Compile;
    _ = Options;
    _ = Run;
    _ = TranslateC;
    _ = WriteFile;
    _ = UpdateSourceFiles;
}
