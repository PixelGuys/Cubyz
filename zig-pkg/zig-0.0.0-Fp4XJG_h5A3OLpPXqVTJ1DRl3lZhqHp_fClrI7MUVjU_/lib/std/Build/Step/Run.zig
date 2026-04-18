const Run = @This();
const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Build = std.Build;
const Step = std.Build.Step;
const Dir = std.Io.Dir;
const mem = std.mem;
const process = std.process;
const EnvMap = std.process.Environ.Map;
const assert = std.debug.assert;
const Path = std.Build.Cache.Path;

pub const base_id: Step.Id = .run;

step: Step,

/// See also addArg and addArgs to modifying this directly
argv: std.ArrayList(Arg),

/// Use `setCwd` to set the initial current working directory
cwd: ?Build.LazyPath,

/// Override this field to modify the environment, or use setEnvironmentVariable
environ_map: ?*EnvMap,

/// Controls the `NO_COLOR` and `CLICOLOR_FORCE` environment variables.
color: Color = .auto,

/// When `true` prevents `ZIG_PROGRESS` environment variable from being passed
/// to the child process, which otherwise would be used for the child to send
/// progress updates to the parent.
disable_zig_progress: bool,

/// Configures whether the Run step is considered to have side-effects, and also
/// whether the Run step will inherit stdio streams, forwarding them to the
/// parent process, in which case will require a global lock to prevent other
/// steps from interfering with stdio while the subprocess associated with this
/// Run step is running.
/// If the Run step is determined to not have side-effects, then execution will
/// be skipped if all output files are up-to-date and input files are
/// unchanged.
stdio: StdIo,

/// This field must be `.none` if stdio is `inherit`.
/// It should be only set using `setStdIn`.
stdin: StdIn,

/// Additional input files that, when modified, indicate that the Run step
/// should be re-executed.
/// If the Run step is determined to have side-effects, the Run step is always
/// executed when it appears in the build graph, regardless of whether these
/// files have been modified.
file_inputs: std.ArrayList(std.Build.LazyPath),

/// After adding an output argument, this step will by default rename itself
/// for a better display name in the build summary.
/// This can be disabled by setting this to false.
rename_step_with_output_arg: bool,

/// If this is true, a Run step which is configured to check the output of the
/// executed binary will not fail the build if the binary cannot be executed
/// due to being for a foreign binary to the host system which is running the
/// build graph.
/// Command-line arguments such as -fqemu and -fwasmtime may affect whether a
/// binary is detected as foreign, as well as system configuration such as
/// Rosetta (macOS) and binfmt_misc (Linux).
/// If this Run step is considered to have side-effects, then this flag does
/// nothing.
skip_foreign_checks: bool,

/// If this is true, failing to execute a foreign binary will be considered an
/// error. However if this is false, the step will be skipped on failure instead.
///
/// This allows for a Run step to attempt to execute a foreign binary using an
/// external executor (such as qemu) but not fail if the executor is unavailable.
failing_to_execute_foreign_is_an_error: bool,

/// If stderr or stdout exceeds this amount, the child process is killed and
/// the step fails.
stdio_limit: std.Io.Limit,

captured_stdout: ?*CapturedStdIo,
captured_stderr: ?*CapturedStdIo,

dep_output_file: ?*Output,

has_side_effects: bool,

/// If this is a Zig unit test binary, this tracks the names of the unit
/// tests that are also fuzz tests. Indexes cannot be used as they may
/// change between reruns.
fuzz_tests: std.ArrayList([]const u8),
cached_test_metadata: ?CachedTestMetadata = null,

/// Populated during the fuzz phase if this run step corresponds to a unit test
/// executable that contains fuzz tests.
rebuilt_executable: ?Path,

/// If this Run step was produced by a Compile step, it is tracked here.
producer: ?*Step.Compile,

pub const Color = enum {
    /// `CLICOLOR_FORCE` is set, and `NO_COLOR` is unset.
    enable,
    /// `NO_COLOR` is set, and `CLICOLOR_FORCE` is unset.
    disable,
    /// If the build runner is using color, equivalent to `.enable`. Otherwise, equivalent to `.disable`.
    inherit,
    /// If stderr is captured or checked, equivalent to `.disable`. Otherwise, equivalent to `.inherit`.
    auto,
    /// The build runner does not modify the `CLICOLOR_FORCE` or `NO_COLOR` environment variables.
    /// They are treated like normal variables, so can be controlled through `setEnvironmentVariable`.
    manual,
};

pub const StdIn = union(enum) {
    none,
    bytes: []const u8,
    lazy_path: std.Build.LazyPath,
};

pub const StdIo = union(enum) {
    /// Whether the Run step has side-effects will be determined by whether or not one
    /// of the args is an output file (added with `addOutputFileArg`).
    /// If the Run step is determined to have side-effects, this is the same as `inherit`.
    /// The step will fail if the subprocess crashes or returns a non-zero exit code.
    infer_from_args,
    /// Causes the Run step to be considered to have side-effects, and therefore
    /// always execute when it appears in the build graph.
    /// It also means that this step will obtain a global lock to prevent other
    /// steps from running in the meantime.
    /// The step will fail if the subprocess crashes or returns a non-zero exit code.
    inherit,
    /// Causes the Run step to be considered to *not* have side-effects. The
    /// process will be re-executed if any of the input dependencies are
    /// modified. The exit code and standard I/O streams will be checked for
    /// certain conditions, and the step will succeed or fail based on these
    /// conditions.
    /// Note that an explicit check for exit code 0 needs to be added to this
    /// list if such a check is desirable.
    check: std.ArrayList(Check),
    /// This Run step is running a zig unit test binary and will communicate
    /// extra metadata over the IPC protocol.
    zig_test,

    pub const Check = union(enum) {
        expect_stderr_exact: []const u8,
        expect_stderr_match: []const u8,
        expect_stdout_exact: []const u8,
        expect_stdout_match: []const u8,
        expect_term: process.Child.Term,
    };
};

pub const Arg = union(enum) {
    artifact: PrefixedArtifact,
    lazy_path: PrefixedLazyPath,
    decorated_directory: DecoratedLazyPath,
    file_content: PrefixedLazyPath,
    bytes: []u8,
    output_file: *Output,
    output_directory: *Output,
};

pub const PrefixedArtifact = struct {
    prefix: []const u8,
    artifact: *Step.Compile,
};

pub const PrefixedLazyPath = struct {
    prefix: []const u8,
    lazy_path: std.Build.LazyPath,
};

pub const DecoratedLazyPath = struct {
    prefix: []const u8,
    lazy_path: std.Build.LazyPath,
    suffix: []const u8,
};

pub const Output = struct {
    generated_file: std.Build.GeneratedFile,
    prefix: []const u8,
    basename: []const u8,
};

pub const CapturedStdIo = struct {
    output: Output,
    trim_whitespace: TrimWhitespace,

    pub const Options = struct {
        /// `null` means `stdout`/`stderr`.
        basename: ?[]const u8 = null,
        /// Does not affect `expectStdOutEqual`/`expectStdErrEqual`.
        trim_whitespace: TrimWhitespace = .none,
    };

    pub const TrimWhitespace = enum {
        none,
        all,
        leading,
        trailing,
    };
};

pub fn create(owner: *std.Build, name: []const u8) *Run {
    const run = owner.allocator.create(Run) catch @panic("OOM");
    run.* = .{
        .step = .init(.{
            .id = base_id,
            .name = name,
            .owner = owner,
            .makeFn = make,
        }),
        .argv = .empty,
        .cwd = null,
        .environ_map = null,
        .disable_zig_progress = false,
        .stdio = .infer_from_args,
        .stdin = .none,
        .file_inputs = .empty,
        .rename_step_with_output_arg = true,
        .skip_foreign_checks = false,
        .failing_to_execute_foreign_is_an_error = true,
        .stdio_limit = .unlimited,
        .captured_stdout = null,
        .captured_stderr = null,
        .dep_output_file = null,
        .has_side_effects = false,
        .fuzz_tests = .empty,
        .rebuilt_executable = null,
        .producer = null,
    };
    return run;
}

pub fn setName(run: *Run, name: []const u8) void {
    run.step.name = name;
    run.rename_step_with_output_arg = false;
}

pub fn enableTestRunnerMode(run: *Run) void {
    const b = run.step.owner;
    run.stdio = .zig_test;
    run.addPrefixedDirectoryArg("--cache-dir=", .{ .cwd_relative = b.cache_root.path orelse "." });
    run.addArgs(&.{
        b.fmt("--seed=0x{x}", .{b.graph.random_seed}),
        "--listen=-",
    });
}

pub fn addArtifactArg(run: *Run, artifact: *Step.Compile) void {
    run.addPrefixedArtifactArg("", artifact);
}

pub fn addPrefixedArtifactArg(run: *Run, prefix: []const u8, artifact: *Step.Compile) void {
    const b = run.step.owner;

    const prefixed_artifact: PrefixedArtifact = .{
        .prefix = b.dupe(prefix),
        .artifact = artifact,
    };
    run.argv.append(b.allocator, .{ .artifact = prefixed_artifact }) catch @panic("OOM");

    const bin_file = artifact.getEmittedBin();
    bin_file.addStepDependencies(&run.step);
}

/// Provides a file path as a command line argument to the command being run.
///
/// Returns a `std.Build.LazyPath` which can be used as inputs to other APIs
/// throughout the build system.
///
/// Related:
/// * `addPrefixedOutputFileArg` - same thing but prepends a string to the argument
/// * `addFileArg` - for input files given to the child process
pub fn addOutputFileArg(run: *Run, basename: []const u8) std.Build.LazyPath {
    return run.addPrefixedOutputFileArg("", basename);
}

/// Provides a file path as a command line argument to the command being run.
/// Asserts `basename` is not empty.
///
/// For example, a prefix of "-o" and basename of "output.txt" will result in
/// the child process seeing something like this: "-ozig-cache/.../output.txt"
///
/// The child process will see a single argument, regardless of whether the
/// prefix or basename have spaces.
///
/// The returned `std.Build.LazyPath` can be used as inputs to other APIs
/// throughout the build system.
///
/// Related:
/// * `addOutputFileArg` - same thing but without the prefix
/// * `addFileArg` - for input files given to the child process
pub fn addPrefixedOutputFileArg(
    run: *Run,
    prefix: []const u8,
    basename: []const u8,
) std.Build.LazyPath {
    const b = run.step.owner;
    if (basename.len == 0) @panic("basename must not be empty");

    const output = b.allocator.create(Output) catch @panic("OOM");
    output.* = .{
        .prefix = b.dupe(prefix),
        .basename = b.dupe(basename),
        .generated_file = .{ .step = &run.step },
    };
    run.argv.append(b.allocator, .{ .output_file = output }) catch @panic("OOM");

    if (run.rename_step_with_output_arg) {
        run.setName(b.fmt("{s} ({s})", .{ run.step.name, basename }));
    }

    return .{ .generated = .{ .file = &output.generated_file } };
}

/// Appends an input file to the command line arguments.
///
/// The child process will see a file path. Modifications to this file will be
/// detected as a cache miss in subsequent builds, causing the child process to
/// be re-executed.
///
/// Related:
/// * `addPrefixedFileArg` - same thing but prepends a string to the argument
/// * `addOutputFileArg` - for files generated by the child process
pub fn addFileArg(run: *Run, lp: std.Build.LazyPath) void {
    run.addPrefixedFileArg("", lp);
}

/// Appends an input file to the command line arguments prepended with a string.
///
/// For example, a prefix of "-F" will result in the child process seeing something
/// like this: "-Fexample.txt"
///
/// The child process will see a single argument, even if the prefix has
/// spaces. Modifications to this file will be detected as a cache miss in
/// subsequent builds, causing the child process to be re-executed.
///
/// Related:
/// * `addFileArg` - same thing but without the prefix
/// * `addOutputFileArg` - for files generated by the child process
pub fn addPrefixedFileArg(run: *Run, prefix: []const u8, lp: std.Build.LazyPath) void {
    const b = run.step.owner;

    const prefixed_file_source: PrefixedLazyPath = .{
        .prefix = b.dupe(prefix),
        .lazy_path = lp.dupe(b),
    };
    run.argv.append(b.allocator, .{ .lazy_path = prefixed_file_source }) catch @panic("OOM");
    lp.addStepDependencies(&run.step);
}

/// Appends the content of an input file to the command line arguments.
///
/// The child process will see a single argument, even if the file contains whitespace.
/// This means that the entire file content up to EOF is rendered as one contiguous
/// string, including escape sequences. Notably, any (trailing) newlines will show up
/// like this: "hello,\nfile world!\n"
///
/// Modifications to the source file will be detected as a cache miss in subsequent
/// builds, causing the child process to be re-executed.
///
/// This function may not be used to supply the first argument of a `Run` step.
///
/// Related:
/// * `addPrefixedFileContentArg` - same thing but prepends a string to the argument
pub fn addFileContentArg(run: *Run, lp: std.Build.LazyPath) void {
    run.addPrefixedFileContentArg("", lp);
}

/// Appends the content of an input file to the command line arguments prepended with a string.
///
/// For example, a prefix of "-F" will result in the child process seeing something
/// like this: "-Fmy file content"
///
/// The child process will see a single argument, even if the prefix and/or the file
/// contain whitespace.
/// This means that the entire file content up to EOF is rendered as one contiguous
/// string, including escape sequences. Notably, any (trailing) newlines will show up
/// like this: "hello,\nfile world!\n"
///
/// Modifications to the source file will be detected as a cache miss in subsequent
/// builds, causing the child process to be re-executed.
///
/// This function may not be used to supply the first argument of a `Run` step.
///
/// Related:
/// * `addFileContentArg` - same thing but without the prefix
pub fn addPrefixedFileContentArg(run: *Run, prefix: []const u8, lp: std.Build.LazyPath) void {
    const b = run.step.owner;

    // Some parts of this step's configure phase API rely on the first argument being somewhat
    // transparent/readable, but the content of the file specified by `lp` remains completely
    // opaque until its path can be resolved during the make phase.
    if (run.argv.items.len == 0) {
        @panic("'addFileContentArg'/'addPrefixedFileContentArg' cannot be first argument");
    }

    const prefixed_file_source: PrefixedLazyPath = .{
        .prefix = b.dupe(prefix),
        .lazy_path = lp.dupe(b),
    };
    run.argv.append(b.allocator, .{ .file_content = prefixed_file_source }) catch @panic("OOM");
    lp.addStepDependencies(&run.step);
}

/// Provides a directory path as a command line argument to the command being run.
///
/// Returns a `std.Build.LazyPath` which can be used as inputs to other APIs
/// throughout the build system.
///
/// Related:
/// * `addPrefixedOutputDirectoryArg` - same thing but prepends a string to the argument
/// * `addDirectoryArg` - for input directories given to the child process
pub fn addOutputDirectoryArg(run: *Run, basename: []const u8) std.Build.LazyPath {
    return run.addPrefixedOutputDirectoryArg("", basename);
}

/// Provides a directory path as a command line argument to the command being run.
/// Asserts `basename` is not empty.
///
/// For example, a prefix of "-o" and basename of "output_dir" will result in
/// the child process seeing something like this: "-ozig-cache/.../output_dir"
///
/// The child process will see a single argument, regardless of whether the
/// prefix or basename have spaces.
///
/// The returned `std.Build.LazyPath` can be used as inputs to other APIs
/// throughout the build system.
///
/// Related:
/// * `addOutputDirectoryArg` - same thing but without the prefix
/// * `addDirectoryArg` - for input directories given to the child process
pub fn addPrefixedOutputDirectoryArg(
    run: *Run,
    prefix: []const u8,
    basename: []const u8,
) std.Build.LazyPath {
    if (basename.len == 0) @panic("basename must not be empty");
    const b = run.step.owner;

    const output = b.allocator.create(Output) catch @panic("OOM");
    output.* = .{
        .prefix = b.dupe(prefix),
        .basename = b.dupe(basename),
        .generated_file = .{ .step = &run.step },
    };
    run.argv.append(b.allocator, .{ .output_directory = output }) catch @panic("OOM");

    if (run.rename_step_with_output_arg) {
        run.setName(b.fmt("{s} ({s})", .{ run.step.name, basename }));
    }

    return .{ .generated = .{ .file = &output.generated_file } };
}

pub fn addDirectoryArg(run: *Run, lazy_directory: std.Build.LazyPath) void {
    run.addDecoratedDirectoryArg("", lazy_directory, "");
}

pub fn addPrefixedDirectoryArg(run: *Run, prefix: []const u8, lazy_directory: std.Build.LazyPath) void {
    const b = run.step.owner;
    run.argv.append(b.allocator, .{ .decorated_directory = .{
        .prefix = b.dupe(prefix),
        .lazy_path = lazy_directory.dupe(b),
        .suffix = "",
    } }) catch @panic("OOM");
    lazy_directory.addStepDependencies(&run.step);
}

pub fn addDecoratedDirectoryArg(
    run: *Run,
    prefix: []const u8,
    lazy_directory: std.Build.LazyPath,
    suffix: []const u8,
) void {
    const b = run.step.owner;
    run.argv.append(b.allocator, .{ .decorated_directory = .{
        .prefix = b.dupe(prefix),
        .lazy_path = lazy_directory.dupe(b),
        .suffix = b.dupe(suffix),
    } }) catch @panic("OOM");
    lazy_directory.addStepDependencies(&run.step);
}

/// Add a path argument to a dep file (.d) for the child process to write its
/// discovered additional dependencies.
/// Only one dep file argument is allowed by instance.
pub fn addDepFileOutputArg(run: *Run, basename: []const u8) std.Build.LazyPath {
    return run.addPrefixedDepFileOutputArg("", basename);
}

/// Add a prefixed path argument to a dep file (.d) for the child process to
/// write its discovered additional dependencies.
/// Only one dep file argument is allowed by instance.
pub fn addPrefixedDepFileOutputArg(run: *Run, prefix: []const u8, basename: []const u8) std.Build.LazyPath {
    const b = run.step.owner;
    assert(run.dep_output_file == null);

    const dep_file = b.allocator.create(Output) catch @panic("OOM");
    dep_file.* = .{
        .prefix = b.dupe(prefix),
        .basename = b.dupe(basename),
        .generated_file = .{ .step = &run.step },
    };

    run.dep_output_file = dep_file;

    run.argv.append(b.allocator, .{ .output_file = dep_file }) catch @panic("OOM");

    return .{ .generated = .{ .file = &dep_file.generated_file } };
}

pub fn addArg(run: *Run, arg: []const u8) void {
    const b = run.step.owner;
    run.argv.append(b.allocator, .{ .bytes = b.dupe(arg) }) catch @panic("OOM");
}

pub fn addArgs(run: *Run, args: []const []const u8) void {
    for (args) |arg| run.addArg(arg);
}

pub fn setStdIn(run: *Run, stdin: StdIn) void {
    switch (stdin) {
        .lazy_path => |lazy_path| lazy_path.addStepDependencies(&run.step),
        .bytes, .none => {},
    }
    run.stdin = stdin;
}

pub fn setCwd(run: *Run, cwd: Build.LazyPath) void {
    cwd.addStepDependencies(&run.step);
    run.cwd = cwd.dupe(run.step.owner);
}

pub fn clearEnvironment(run: *Run) void {
    const b = run.step.owner;
    const new_env_map = b.allocator.create(EnvMap) catch @panic("OOM");
    new_env_map.* = .init(b.allocator);
    run.environ_map = new_env_map;
}

pub fn addPathDir(run: *Run, search_path: []const u8) void {
    const b = run.step.owner;
    const environ_map = getEnvMapInternal(run);

    const use_wine = b.enable_wine and b.graph.host.result.os.tag != .windows and use_wine: switch (run.argv.items[0]) {
        .artifact => |p| p.artifact.rootModuleTarget().os.tag == .windows,
        .lazy_path => |p| {
            switch (p.lazy_path) {
                .generated => |g| if (g.file.step.cast(Step.Compile)) |cs| break :use_wine cs.rootModuleTarget().os.tag == .windows,
                else => {},
            }
            break :use_wine std.mem.endsWith(u8, p.lazy_path.basename(b, &run.step), ".exe");
        },
        .decorated_directory => false,
        .file_content => unreachable, // not allowed as first arg
        .bytes => |bytes| std.mem.endsWith(u8, bytes, ".exe"),
        .output_file, .output_directory => false,
    };
    const key = if (use_wine) "WINEPATH" else "PATH";
    const prev_path = environ_map.get(key);

    if (prev_path) |pp| {
        const new_path = b.fmt("{s}{c}{s}", .{
            pp,
            if (use_wine) Dir.path.delimiter_windows else Dir.path.delimiter,
            search_path,
        });
        environ_map.put(key, new_path) catch @panic("OOM");
    } else {
        environ_map.put(key, b.dupePath(search_path)) catch @panic("OOM");
    }
}

pub fn getEnvMap(run: *Run) *EnvMap {
    return getEnvMapInternal(run);
}

fn getEnvMapInternal(run: *Run) *EnvMap {
    const graph = run.step.owner.graph;
    const arena = graph.arena;
    return run.environ_map orelse {
        const cloned_map = arena.create(EnvMap) catch @panic("OOM");
        cloned_map.* = graph.environ_map.clone(arena) catch @panic("OOM");
        run.environ_map = cloned_map;
        return cloned_map;
    };
}

pub fn setEnvironmentVariable(run: *Run, key: []const u8, value: []const u8) void {
    const environ_map = run.getEnvMap();
    // This data structure already dupes keys and values.
    environ_map.put(key, value) catch @panic("OOM");
}

pub fn removeEnvironmentVariable(run: *Run, key: []const u8) void {
    _ = run.getEnvMap().swapRemove(key);
}

/// Adds a check for exact stderr match. Does not add any other checks.
pub fn expectStdErrEqual(run: *Run, bytes: []const u8) void {
    run.addCheck(.{ .expect_stderr_exact = run.step.owner.dupe(bytes) });
}

pub fn expectStdErrMatch(run: *Run, bytes: []const u8) void {
    run.addCheck(.{ .expect_stderr_match = run.step.owner.dupe(bytes) });
}

/// Adds a check for exact stdout match as well as a check for exit code 0, if
/// there is not already an expected termination check.
pub fn expectStdOutEqual(run: *Run, bytes: []const u8) void {
    run.addCheck(.{ .expect_stdout_exact = run.step.owner.dupe(bytes) });
    if (!run.hasTermCheck()) run.expectExitCode(0);
}

/// Adds a check for stdout match as well as a check for exit code 0, if there
/// is not already an expected termination check.
pub fn expectStdOutMatch(run: *Run, bytes: []const u8) void {
    run.addCheck(.{ .expect_stdout_match = run.step.owner.dupe(bytes) });
    if (!run.hasTermCheck()) run.expectExitCode(0);
}

pub fn expectExitCode(run: *Run, code: u8) void {
    const new_check: StdIo.Check = .{ .expect_term = .{ .exited = code } };
    run.addCheck(new_check);
}

pub fn hasTermCheck(run: Run) bool {
    for (run.stdio.check.items) |check| switch (check) {
        .expect_term => return true,
        else => continue,
    };
    return false;
}

pub fn addCheck(run: *Run, new_check: StdIo.Check) void {
    const b = run.step.owner;

    switch (run.stdio) {
        .infer_from_args => {
            run.stdio = .{ .check = .empty };
            run.stdio.check.append(b.allocator, new_check) catch @panic("OOM");
        },
        .check => |*checks| checks.append(b.allocator, new_check) catch @panic("OOM"),
        else => @panic("illegal call to addCheck: conflicting helper method calls. Suggest to directly set stdio field of Run instead"),
    }
}

pub fn captureStdErr(run: *Run, options: CapturedStdIo.Options) std.Build.LazyPath {
    assert(run.stdio != .inherit);
    assert(run.stdio != .zig_test);

    const b = run.step.owner;

    if (run.captured_stderr) |captured| return .{ .generated = .{ .file = &captured.output.generated_file } };

    const captured = b.allocator.create(CapturedStdIo) catch @panic("OOM");
    captured.* = .{
        .output = .{
            .prefix = "",
            .basename = if (options.basename) |basename| b.dupe(basename) else "stderr",
            .generated_file = .{ .step = &run.step },
        },
        .trim_whitespace = options.trim_whitespace,
    };
    run.captured_stderr = captured;
    return .{ .generated = .{ .file = &captured.output.generated_file } };
}

pub fn captureStdOut(run: *Run, options: CapturedStdIo.Options) std.Build.LazyPath {
    assert(run.stdio != .inherit);
    assert(run.stdio != .zig_test);

    const b = run.step.owner;

    if (run.captured_stdout) |captured| return .{ .generated = .{ .file = &captured.output.generated_file } };

    const captured = b.allocator.create(CapturedStdIo) catch @panic("OOM");
    captured.* = .{
        .output = .{
            .prefix = "",
            .basename = if (options.basename) |basename| b.dupe(basename) else "stdout",
            .generated_file = .{ .step = &run.step },
        },
        .trim_whitespace = options.trim_whitespace,
    };
    run.captured_stdout = captured;
    return .{ .generated = .{ .file = &captured.output.generated_file } };
}

/// Adds an additional input files that, when modified, indicates that this Run
/// step should be re-executed.
/// If the Run step is determined to have side-effects, the Run step is always
/// executed when it appears in the build graph, regardless of whether this
/// file has been modified.
pub fn addFileInput(self: *Run, file_input: std.Build.LazyPath) void {
    file_input.addStepDependencies(&self.step);
    self.file_inputs.append(self.step.owner.allocator, file_input.dupe(self.step.owner)) catch @panic("OOM");
}

/// Returns whether the Run step has side effects *other than* updating the output arguments.
fn hasSideEffects(run: Run) bool {
    if (run.has_side_effects) return true;
    return switch (run.stdio) {
        .infer_from_args => !run.hasAnyOutputArgs(),
        .inherit => true,
        .check => false,
        .zig_test => false,
    };
}

fn hasAnyOutputArgs(run: Run) bool {
    if (run.captured_stdout != null) return true;
    if (run.captured_stderr != null) return true;
    for (run.argv.items) |arg| switch (arg) {
        .output_file, .output_directory => return true,
        else => continue,
    };
    return false;
}

fn checksContainStdout(checks: []const StdIo.Check) bool {
    for (checks) |check| switch (check) {
        .expect_stderr_exact,
        .expect_stderr_match,
        .expect_term,
        => continue,

        .expect_stdout_exact,
        .expect_stdout_match,
        => return true,
    };
    return false;
}

fn checksContainStderr(checks: []const StdIo.Check) bool {
    for (checks) |check| switch (check) {
        .expect_stdout_exact,
        .expect_stdout_match,
        .expect_term,
        => continue,

        .expect_stderr_exact,
        .expect_stderr_match,
        => return true,
    };
    return false;
}

/// If `path` is cwd-relative, make it relative to the cwd of the child instead.
///
/// Whenever a path is included in the argv of a child, it should be put through this function first
/// to make sure the child doesn't see paths relative to a cwd other than its own.
fn convertPathArg(run: *Run, path: Build.Cache.Path) []const u8 {
    const b = run.step.owner;
    const graph = b.graph;
    const arena = graph.arena;

    const path_str = path.toString(arena) catch @panic("OOM");
    if (Dir.path.isAbsolute(path_str)) {
        // Absolute paths don't need changing.
        return path_str;
    }
    const child_cwd_rel: []const u8 = rel: {
        const child_lazy_cwd = run.cwd orelse break :rel path_str;
        const child_cwd = child_lazy_cwd.getPath3(b, &run.step).toString(arena) catch @panic("OOM");
        // Convert it from relative to *our* cwd, to relative to the *child's* cwd.
        break :rel Dir.path.relative(arena, graph.cache.cwd, &graph.environ_map, child_cwd, path_str) catch @panic("OOM");
    };
    // Not every path can be made relative, e.g. if the path and the child cwd are on different
    // disk designators on Windows. In that case, `relative` will return an absolute path which we can
    // just return.
    if (Dir.path.isAbsolute(child_cwd_rel)) return child_cwd_rel;

    // We're not done yet. In some cases this path must be prefixed with './':
    // * On POSIX, the executable name cannot be a single component like 'foo'
    // * Some executables might treat a leading '-' like a flag, which we must avoid
    // There's no harm in it, so just *always* apply this prefix.
    return Dir.path.join(arena, &.{ ".", child_cwd_rel }) catch @panic("OOM");
}

const IndexedOutput = struct {
    index: usize,
    tag: @typeInfo(Arg).@"union".tag_type.?,
    output: *Output,
};
fn make(step: *Step, options: Step.MakeOptions) !void {
    const b = step.owner;
    const io = b.graph.io;
    const arena = b.allocator;
    const run: *Run = @fieldParentPtr("step", step);
    const has_side_effects = run.hasSideEffects();

    var argv_list = std.array_list.Managed([]const u8).init(arena);
    var output_placeholders = std.array_list.Managed(IndexedOutput).init(arena);

    var man = b.graph.cache.obtain();
    defer man.deinit();

    if (run.environ_map) |environ_map| {
        for (environ_map.keys(), environ_map.values()) |key, value| {
            man.hash.addBytes(key);
            man.hash.addBytes(value);
        }
    }

    man.hash.add(run.color);
    man.hash.add(run.disable_zig_progress);

    for (run.argv.items) |arg| {
        switch (arg) {
            .bytes => |bytes| {
                try argv_list.append(bytes);
                man.hash.addBytes(bytes);
            },
            .lazy_path => |file| {
                const file_path = file.lazy_path.getPath3(b, step);
                try argv_list.append(b.fmt("{s}{s}", .{ file.prefix, run.convertPathArg(file_path) }));
                man.hash.addBytes(file.prefix);
                _ = try man.addFilePath(file_path, null);
            },
            .decorated_directory => |dd| {
                const file_path = dd.lazy_path.getPath3(b, step);
                const resolved_arg = b.fmt("{s}{s}{s}", .{ dd.prefix, run.convertPathArg(file_path), dd.suffix });
                try argv_list.append(resolved_arg);
                man.hash.addBytes(resolved_arg);
            },
            .file_content => |file_plp| {
                const file_path = file_plp.lazy_path.getPath3(b, step);

                var result: std.Io.Writer.Allocating = .init(arena);
                errdefer result.deinit();
                result.writer.writeAll(file_plp.prefix) catch return error.OutOfMemory;

                const file = file_path.root_dir.handle.openFile(io, file_path.subPathOrDot(), .{}) catch |err| {
                    return step.fail(
                        "unable to open input file '{f}': {t}",
                        .{ file_path, err },
                    );
                };
                defer file.close(io);

                var buf: [1024]u8 = undefined;
                var file_reader = file.reader(io, &buf);
                _ = file_reader.interface.streamRemaining(&result.writer) catch |err| switch (err) {
                    error.ReadFailed => return step.fail(
                        "failed to read from '{f}': {t}",
                        .{ file_path, file_reader.err.? },
                    ),
                    error.WriteFailed => return error.OutOfMemory,
                };

                try argv_list.append(result.written());
                man.hash.addBytes(file_plp.prefix);
                _ = try man.addFilePath(file_path, null);
            },
            .artifact => |pa| {
                const artifact = pa.artifact;

                if (artifact.rootModuleTarget().os.tag == .windows) {
                    // On Windows we don't have rpaths so we have to add .dll search paths to PATH
                    run.addPathForDynLibs(artifact);
                }
                const file_path = artifact.installed_path orelse artifact.generated_bin.?.path.?;

                try argv_list.append(b.fmt("{s}{s}", .{
                    pa.prefix,
                    run.convertPathArg(.{ .root_dir = .cwd(), .sub_path = file_path }),
                }));

                _ = try man.addFile(file_path, null);
            },
            .output_file, .output_directory => |output| {
                man.hash.addBytes(output.prefix);
                man.hash.addBytes(output.basename);
                // Add a placeholder into the argument list because we need the
                // manifest hash to be updated with all arguments before the
                // object directory is computed.
                try output_placeholders.append(.{
                    .index = argv_list.items.len,
                    .tag = arg,
                    .output = output,
                });
                _ = try argv_list.addOne();
            },
        }
    }

    switch (run.stdin) {
        .bytes => |bytes| {
            man.hash.addBytes(bytes);
        },
        .lazy_path => |lazy_path| {
            const file_path = lazy_path.getPath2(b, step);
            _ = try man.addFile(file_path, null);
        },
        .none => {},
    }

    if (run.captured_stdout) |captured| {
        man.hash.addBytes(captured.output.basename);
        man.hash.add(captured.trim_whitespace);
    }

    if (run.captured_stderr) |captured| {
        man.hash.addBytes(captured.output.basename);
        man.hash.add(captured.trim_whitespace);
    }

    hashStdIo(&man.hash, run.stdio);

    for (run.file_inputs.items) |lazy_path| {
        _ = try man.addFile(lazy_path.getPath2(b, step), null);
    }

    if (run.cwd) |cwd| {
        const cwd_path = cwd.getPath3(b, step);
        _ = man.hash.addBytes(try cwd_path.toString(arena));
    }

    if (!has_side_effects and try step.cacheHitAndWatch(&man)) {
        // cache hit, skip running command
        const digest = man.final();

        try populateGeneratedPaths(
            arena,
            output_placeholders.items,
            run.captured_stdout,
            run.captured_stderr,
            b.cache_root,
            &digest,
        );

        step.result_cached = true;
        return;
    }

    const dep_output_file = run.dep_output_file orelse {
        // We already know the final output paths, use them directly.
        const digest = if (has_side_effects)
            man.hash.final()
        else
            man.final();

        try populateGeneratedPaths(
            arena,
            output_placeholders.items,
            run.captured_stdout,
            run.captured_stderr,
            b.cache_root,
            &digest,
        );

        const output_dir_path = "o" ++ Dir.path.sep_str ++ &digest;
        for (output_placeholders.items) |placeholder| {
            const output_sub_path = b.pathJoin(&.{ output_dir_path, placeholder.output.basename });
            const output_sub_dir_path = switch (placeholder.tag) {
                .output_file => Dir.path.dirname(output_sub_path).?,
                .output_directory => output_sub_path,
                else => unreachable,
            };
            b.cache_root.handle.createDirPath(io, output_sub_dir_path) catch |err| {
                return step.fail("unable to make path '{f}{s}': {s}", .{
                    b.cache_root, output_sub_dir_path, @errorName(err),
                });
            };
            const arg_output_path = run.convertPathArg(.{
                .root_dir = .cwd(),
                .sub_path = placeholder.output.generated_file.getPath(),
            });
            argv_list.items[placeholder.index] = if (placeholder.output.prefix.len == 0)
                arg_output_path
            else
                b.fmt("{s}{s}", .{ placeholder.output.prefix, arg_output_path });
        }

        try runCommand(run, argv_list.items, has_side_effects, output_dir_path, options, null);
        if (!has_side_effects) try step.writeManifestAndWatch(&man);
        return;
    };

    // We do not know the final output paths yet, use temp paths to run the command.
    var rand_int: u64 = undefined;
    io.random(@ptrCast(&rand_int));
    const tmp_dir_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);

    for (output_placeholders.items) |placeholder| {
        const output_components = .{ tmp_dir_path, placeholder.output.basename };
        const output_sub_path = b.pathJoin(&output_components);
        const output_sub_dir_path = switch (placeholder.tag) {
            .output_file => Dir.path.dirname(output_sub_path).?,
            .output_directory => output_sub_path,
            else => unreachable,
        };
        b.cache_root.handle.createDirPath(io, output_sub_dir_path) catch |err| {
            return step.fail("unable to make path '{f}{s}': {s}", .{
                b.cache_root, output_sub_dir_path, @errorName(err),
            });
        };
        const raw_output_path: Build.Cache.Path = .{
            .root_dir = b.cache_root,
            .sub_path = b.pathJoin(&output_components),
        };
        placeholder.output.generated_file.path = raw_output_path.toString(b.graph.arena) catch @panic("OOM");
        argv_list.items[placeholder.index] = b.fmt("{s}{s}", .{
            placeholder.output.prefix,
            run.convertPathArg(raw_output_path),
        });
    }

    try runCommand(run, argv_list.items, has_side_effects, tmp_dir_path, options, null);

    const dep_file_dir = Dir.cwd();
    const dep_file_basename = dep_output_file.generated_file.getPath2(b, step);
    if (has_side_effects)
        try man.addDepFile(dep_file_dir, dep_file_basename)
    else
        try man.addDepFilePost(dep_file_dir, dep_file_basename);

    const digest = if (has_side_effects)
        man.hash.final()
    else
        man.final();

    const any_output = output_placeholders.items.len > 0 or
        run.captured_stdout != null or run.captured_stderr != null;

    // Rename into place
    if (any_output) {
        const o_sub_path = "o" ++ Dir.path.sep_str ++ &digest;

        b.cache_root.handle.rename(tmp_dir_path, b.cache_root.handle, o_sub_path, io) catch |err| switch (err) {
            Dir.RenameError.DirNotEmpty => {
                b.cache_root.handle.deleteTree(io, o_sub_path) catch |del_err| {
                    return step.fail("unable to remove dir '{f}'{s}: {t}", .{
                        b.cache_root, tmp_dir_path, del_err,
                    });
                };
                b.cache_root.handle.rename(tmp_dir_path, b.cache_root.handle, o_sub_path, io) catch |retry_err| {
                    return step.fail("unable to rename dir '{f}{s}' to '{f}{s}': {t}", .{
                        b.cache_root, tmp_dir_path, b.cache_root, o_sub_path, retry_err,
                    });
                };
            },
            else => return step.fail("unable to rename dir '{f}{s}' to '{f}{s}': {t}", .{
                b.cache_root, tmp_dir_path, b.cache_root, o_sub_path, err,
            }),
        };
    }

    if (!has_side_effects) try step.writeManifestAndWatch(&man);

    try populateGeneratedPaths(
        arena,
        output_placeholders.items,
        run.captured_stdout,
        run.captured_stderr,
        b.cache_root,
        &digest,
    );
}

pub fn rerunInFuzzMode(
    run: *Run,
    fuzz: *std.Build.Fuzz,
    prog_node: std.Progress.Node,
) !void {
    const step = &run.step;
    const b = step.owner;
    const io = b.graph.io;
    const arena = b.allocator;
    var argv_list: std.ArrayList([]const u8) = .empty;
    for (run.argv.items) |arg| {
        switch (arg) {
            .bytes => |bytes| {
                try argv_list.append(arena, bytes);
            },
            .lazy_path => |file| {
                const file_path = file.lazy_path.getPath3(b, step);
                try argv_list.append(arena, b.fmt("{s}{s}", .{ file.prefix, run.convertPathArg(file_path) }));
            },
            .decorated_directory => |dd| {
                const file_path = dd.lazy_path.getPath3(b, step);
                try argv_list.append(arena, b.fmt("{s}{s}{s}", .{ dd.prefix, run.convertPathArg(file_path), dd.suffix }));
            },
            .file_content => |file_plp| {
                const file_path = file_plp.lazy_path.getPath3(b, step);

                var result: std.Io.Writer.Allocating = .init(arena);
                errdefer result.deinit();
                result.writer.writeAll(file_plp.prefix) catch return error.OutOfMemory;

                const file = try file_path.root_dir.handle.openFile(io, file_path.subPathOrDot(), .{});
                defer file.close(io);

                var buf: [1024]u8 = undefined;
                var file_reader = file.reader(io, &buf);
                _ = file_reader.interface.streamRemaining(&result.writer) catch |err| switch (err) {
                    error.ReadFailed => return file_reader.err.?,
                    error.WriteFailed => return error.OutOfMemory,
                };

                try argv_list.append(arena, result.written());
            },
            .artifact => |pa| {
                const artifact = pa.artifact;
                const file_path: []const u8 = p: {
                    if (artifact == run.producer.?) break :p b.fmt("{f}", .{run.rebuilt_executable.?});
                    break :p artifact.installed_path orelse artifact.generated_bin.?.path.?;
                };
                try argv_list.append(arena, b.fmt("{s}{s}", .{
                    pa.prefix,
                    run.convertPathArg(.{ .root_dir = .cwd(), .sub_path = file_path }),
                }));
            },
            .output_file, .output_directory => unreachable,
        }
    }

    if (run.step.result_failed_command) |cmd| {
        fuzz.gpa.free(cmd);
        run.step.result_failed_command = null;
    }

    const has_side_effects = false;
    var rand_int: u64 = undefined;
    io.random(@ptrCast(&rand_int));
    const tmp_dir_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);
    try runCommand(run, argv_list.items, has_side_effects, tmp_dir_path, .{
        .progress_node = prog_node,
        .watch = undefined, // not used by `runCommand`
        .web_server = null, // only needed for time reports
        .unit_test_timeout_ns = null, // don't time out fuzz tests for now
        .gpa = fuzz.gpa,
    }, .{
        .fuzz = fuzz,
    });
}

fn populateGeneratedPaths(
    arena: std.mem.Allocator,
    output_placeholders: []const IndexedOutput,
    captured_stdout: ?*CapturedStdIo,
    captured_stderr: ?*CapturedStdIo,
    cache_root: Build.Cache.Directory,
    digest: *const Build.Cache.HexDigest,
) !void {
    for (output_placeholders) |placeholder| {
        placeholder.output.generated_file.path = try cache_root.join(arena, &.{
            "o", digest, placeholder.output.basename,
        });
    }

    if (captured_stdout) |captured| {
        captured.output.generated_file.path = try cache_root.join(arena, &.{
            "o", digest, captured.output.basename,
        });
    }

    if (captured_stderr) |captured| {
        captured.output.generated_file.path = try cache_root.join(arena, &.{
            "o", digest, captured.output.basename,
        });
    }
}

fn formatTerm(term: ?process.Child.Term, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (term) |t| switch (t) {
        .exited => |code| try w.print("exited with code {d}", .{code}),
        .signal => |sig| try w.print("terminated with signal {t}", .{sig}),
        .stopped => |sig| try w.print("stopped with signal {t}", .{sig}),
        .unknown => |code| try w.print("terminated for unknown reason with code {d}", .{code}),
    } else {
        try w.writeAll("exited with any code");
    }
}
fn fmtTerm(term: ?process.Child.Term) std.fmt.Alt(?process.Child.Term, formatTerm) {
    return .{ .data = term };
}

fn termMatches(expected: ?process.Child.Term, actual: process.Child.Term) bool {
    return if (expected) |e| switch (e) {
        .exited => |expected_code| switch (actual) {
            .exited => |actual_code| expected_code == actual_code,
            else => false,
        },
        .signal => |expected_sig| switch (actual) {
            .signal => |actual_sig| expected_sig == actual_sig,
            else => false,
        },
        .stopped => |expected_sig| switch (actual) {
            .stopped => |actual_sig| expected_sig == actual_sig,
            else => false,
        },
        .unknown => |expected_code| switch (actual) {
            .unknown => |actual_code| expected_code == actual_code,
            else => false,
        },
    } else switch (actual) {
        .exited => true,
        else => false,
    };
}

const FuzzContext = struct {
    fuzz: *std.Build.Fuzz,
};

fn runCommand(
    run: *Run,
    argv: []const []const u8,
    has_side_effects: bool,
    output_dir_path: []const u8,
    options: Step.MakeOptions,
    fuzz_context: ?FuzzContext,
) !void {
    const step = &run.step;
    const b = step.owner;
    const arena = b.allocator;
    const gpa = options.gpa;
    const io = b.graph.io;

    const cwd: process.Child.Cwd = if (run.cwd) |lazy_cwd| .{ .path = lazy_cwd.getPath2(b, step) } else .inherit;

    try step.handleChildProcUnsupported();
    try Step.handleVerbose2(step.owner, cwd, run.environ_map, argv);

    const allow_skip = switch (run.stdio) {
        .check, .zig_test => run.skip_foreign_checks,
        else => false,
    };

    var interp_argv = std.array_list.Managed([]const u8).init(b.allocator);
    defer interp_argv.deinit();

    var environ_map: EnvMap = env: {
        const orig = run.environ_map orelse &b.graph.environ_map;
        break :env try orig.clone(gpa);
    };
    defer environ_map.deinit();

    const opt_generic_result = spawnChildAndCollect(run, argv, &environ_map, has_side_effects, options, fuzz_context) catch |err| term: {
        // InvalidExe: cpu arch mismatch
        // FileNotFound: can happen with a wrong dynamic linker path
        if (err == error.InvalidExe or err == error.FileNotFound) interpret: {
            // TODO: learn the target from the binary directly rather than from
            // relying on it being a Compile step. This will make this logic
            // work even for the edge case that the binary was produced by a
            // third party.
            const exe = switch (run.argv.items[0]) {
                .artifact => |exe| exe.artifact,
                else => break :interpret,
            };
            switch (exe.kind) {
                .exe, .@"test" => {},
                else => break :interpret,
            }

            const root_target = exe.rootModuleTarget();
            const need_cross_libc = exe.is_linking_libc and
                (root_target.isGnuLibC() or (root_target.isMuslLibC() and exe.linkage == .dynamic));
            const other_target = exe.root_module.resolved_target.?.result;
            switch (std.zig.system.getExternalExecutor(io, &b.graph.host.result, &other_target, .{
                .qemu_fixes_dl = need_cross_libc and b.libc_runtimes_dir != null,
                .link_libc = exe.is_linking_libc,
            })) {
                .native, .rosetta => {
                    if (allow_skip) return error.MakeSkipped;
                    break :interpret;
                },
                .wine => |bin_name| {
                    if (b.enable_wine) {
                        try interp_argv.append(bin_name);
                        try interp_argv.appendSlice(argv);

                        // Wine's excessive stderr logging is only situationally helpful. Disable it by default, but
                        // allow the user to override it (e.g. with `WINEDEBUG=err+all`) if desired.
                        if (environ_map.get("WINEDEBUG") == null) {
                            try environ_map.put("WINEDEBUG", "-all");
                        }
                    } else {
                        return failForeign(run, "-fwine", argv[0], exe);
                    }
                },
                .qemu => |bin_name| {
                    if (b.enable_qemu) {
                        try interp_argv.append(bin_name);

                        if (need_cross_libc) {
                            if (b.libc_runtimes_dir) |dir| {
                                try interp_argv.append("-L");
                                try interp_argv.append(b.pathJoin(&.{
                                    dir,
                                    try if (root_target.isGnuLibC()) std.zig.target.glibcRuntimeTriple(
                                        b.allocator,
                                        root_target.cpu.arch,
                                        root_target.os.tag,
                                        root_target.abi,
                                    ) else if (root_target.isMuslLibC()) std.zig.target.muslRuntimeTriple(
                                        b.allocator,
                                        root_target.cpu.arch,
                                        root_target.abi,
                                    ) else unreachable,
                                }));
                            } else return failForeign(run, "--libc-runtimes", argv[0], exe);
                        }

                        try interp_argv.appendSlice(argv);
                    } else return failForeign(run, "-fqemu", argv[0], exe);
                },
                .darling => |bin_name| {
                    if (b.enable_darling) {
                        try interp_argv.append(bin_name);
                        try interp_argv.appendSlice(argv);
                    } else {
                        return failForeign(run, "-fdarling", argv[0], exe);
                    }
                },
                .wasmtime => |bin_name| {
                    if (b.enable_wasmtime) {
                        try interp_argv.append(bin_name);
                        try interp_argv.append("--dir=.");
                        // Wasmtime doeesn't inherit environment variables from the parent process
                        // by default. '-S inherit-env' was added in Wasmtime version 20.
                        try interp_argv.append("-Sinherit-env");
                        try interp_argv.append(argv[0]);
                        try interp_argv.appendSlice(argv[1..]);
                    } else {
                        return failForeign(run, "-fwasmtime", argv[0], exe);
                    }
                },
                .bad_dl => |foreign_dl| {
                    if (allow_skip) return error.MakeSkipped;

                    const host_dl = b.graph.host.result.dynamic_linker.get() orelse "(none)";

                    return step.fail(
                        \\the host system is unable to execute binaries from the target
                        \\  because the host dynamic linker is '{s}',
                        \\  while the target dynamic linker is '{s}'.
                        \\  consider setting the dynamic linker or enabling skip_foreign_checks in the Run step
                    , .{ host_dl, foreign_dl });
                },
                .bad_os_or_cpu => {
                    if (allow_skip) return error.MakeSkipped;

                    const host_name = try b.graph.host.result.zigTriple(b.allocator);
                    const foreign_name = try root_target.zigTriple(b.allocator);

                    return step.fail("the host system ({s}) is unable to execute binaries from the target ({s})", .{
                        host_name, foreign_name,
                    });
                },
            }

            if (root_target.os.tag == .windows) {
                // On Windows we don't have rpaths so we have to add .dll search paths to PATH
                run.addPathForDynLibs(exe);
            }

            gpa.free(step.result_failed_command.?);
            step.result_failed_command = null;
            try Step.handleVerbose2(step.owner, cwd, run.environ_map, interp_argv.items);

            break :term spawnChildAndCollect(run, interp_argv.items, &environ_map, has_side_effects, options, fuzz_context) catch |e| {
                if (!run.failing_to_execute_foreign_is_an_error) return error.MakeSkipped;
                if (e == error.MakeFailed) return error.MakeFailed; // error already reported
                return step.fail("unable to spawn interpreter {s}: {t}", .{ interp_argv.items[0], e });
            };
        }
        if (err == error.MakeFailed) return error.MakeFailed; // error already reported

        return step.fail("failed to spawn and capture stdio from {s}: {t}", .{ argv[0], err });
    };

    const generic_result = opt_generic_result orelse {
        assert(run.stdio == .zig_test);
        // Specific errors have already been reported, and test results are populated. All we need
        // to do is report step failure if any test failed.
        if (!step.test_results.isSuccess()) return error.MakeFailed;
        return;
    };

    assert(fuzz_context == null);
    assert(run.stdio != .zig_test);

    // Capture stdout and stderr to GeneratedFile objects.
    const Stream = struct {
        captured: ?*CapturedStdIo,
        bytes: ?[]const u8,
    };
    for ([_]Stream{
        .{
            .captured = run.captured_stdout,
            .bytes = generic_result.stdout,
        },
        .{
            .captured = run.captured_stderr,
            .bytes = generic_result.stderr,
        },
    }) |stream| {
        if (stream.captured) |captured| {
            const output_components = .{ output_dir_path, captured.output.basename };
            const output_path = try b.cache_root.join(arena, &output_components);
            captured.output.generated_file.path = output_path;

            const sub_path = b.pathJoin(&output_components);
            const sub_path_dirname = Dir.path.dirname(sub_path).?;
            b.cache_root.handle.createDirPath(io, sub_path_dirname) catch |err| {
                return step.fail("unable to make path '{f}{s}': {s}", .{
                    b.cache_root, sub_path_dirname, @errorName(err),
                });
            };
            const data = switch (captured.trim_whitespace) {
                .none => stream.bytes.?,
                .all => mem.trim(u8, stream.bytes.?, &std.ascii.whitespace),
                .leading => mem.trimStart(u8, stream.bytes.?, &std.ascii.whitespace),
                .trailing => mem.trimEnd(u8, stream.bytes.?, &std.ascii.whitespace),
            };
            b.cache_root.handle.writeFile(io, .{ .sub_path = sub_path, .data = data }) catch |err| {
                return step.fail("unable to write file '{f}{s}': {s}", .{
                    b.cache_root, sub_path, @errorName(err),
                });
            };
        }
    }

    switch (run.stdio) {
        .zig_test => unreachable,
        .check => |checks| for (checks.items) |check| switch (check) {
            .expect_stderr_exact => |expected_bytes| {
                if (!mem.eql(u8, expected_bytes, generic_result.stderr.?)) {
                    return step.fail(
                        \\========= expected this stderr: =========
                        \\{s}
                        \\========= but found: ====================
                        \\{s}
                    , .{
                        expected_bytes,
                        generic_result.stderr.?,
                    });
                }
            },
            .expect_stderr_match => |match| {
                if (mem.find(u8, generic_result.stderr.?, match) == null) {
                    return step.fail(
                        \\========= expected to find in stderr: =========
                        \\{s}
                        \\========= but stderr does not contain it: =====
                        \\{s}
                    , .{
                        match,
                        generic_result.stderr.?,
                    });
                }
            },
            .expect_stdout_exact => |expected_bytes| {
                if (!mem.eql(u8, expected_bytes, generic_result.stdout.?)) {
                    return step.fail(
                        \\========= expected this stdout: =========
                        \\{s}
                        \\========= but found: ====================
                        \\{s}
                    , .{
                        expected_bytes,
                        generic_result.stdout.?,
                    });
                }
            },
            .expect_stdout_match => |match| {
                if (mem.find(u8, generic_result.stdout.?, match) == null) {
                    return step.fail(
                        \\========= expected to find in stdout: =========
                        \\{s}
                        \\========= but stdout does not contain it: =====
                        \\{s}
                    , .{
                        match,
                        generic_result.stdout.?,
                    });
                }
            },
            .expect_term => |expected_term| {
                if (!termMatches(expected_term, generic_result.term)) {
                    return step.fail("process {f} (expected {f})", .{
                        fmtTerm(generic_result.term),
                        fmtTerm(expected_term),
                    });
                }
            },
        },
        else => {
            // On failure, report captured stderr like normal standard error output.
            const bad_exit = switch (generic_result.term) {
                .exited => |code| code != 0,
                .signal, .stopped, .unknown => true,
            };
            if (bad_exit) {
                if (generic_result.stderr) |bytes| {
                    run.step.result_stderr = bytes;
                }
            }

            try step.handleChildProcessTerm(generic_result.term);
        },
    }
}

const EvalGenericResult = struct {
    term: process.Child.Term,
    stdout: ?[]const u8,
    stderr: ?[]const u8,
};

fn spawnChildAndCollect(
    run: *Run,
    argv: []const []const u8,
    environ_map: *EnvMap,
    has_side_effects: bool,
    options: Step.MakeOptions,
    fuzz_context: ?FuzzContext,
) !?EvalGenericResult {
    const b = run.step.owner;
    const graph = b.graph;
    const io = graph.io;

    if (fuzz_context != null) {
        assert(!has_side_effects);
        assert(run.stdio == .zig_test);
    }

    const child_cwd: process.Child.Cwd = if (run.cwd) |lazy_cwd| .{ .path = lazy_cwd.getPath2(b, &run.step) } else .inherit;

    // If an error occurs, it's caused by this command:
    assert(run.step.result_failed_command == null);
    run.step.result_failed_command = try Step.allocPrintCmd(options.gpa, child_cwd, .{
        .child = environ_map,
        .parent = &graph.environ_map,
    }, argv);

    var spawn_options: process.SpawnOptions = .{
        .argv = argv,
        .cwd = child_cwd,
        .environ_map = environ_map,
        .request_resource_usage_statistics = true,
        .stdin = if (run.stdin != .none) s: {
            assert(run.stdio != .inherit);
            break :s .pipe;
        } else switch (run.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .ignore,
            .inherit => .inherit,
            .check => .ignore,
            .zig_test => .pipe,
        },
        .stdout = if (run.captured_stdout != null) .pipe else switch (run.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .ignore,
            .inherit => .inherit,
            .check => |checks| if (checksContainStdout(checks.items)) .pipe else .ignore,
            .zig_test => .pipe,
        },
        .stderr = if (run.captured_stderr != null) .pipe else switch (run.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .pipe,
            .inherit => .inherit,
            .check => .pipe,
            .zig_test => .pipe,
        },
    };

    if (run.stdio == .zig_test) {
        const started: Io.Clock.Timestamp = .now(io, .awake);
        const result = evalZigTest(run, spawn_options, options, fuzz_context) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| e,
        };
        run.step.result_duration_ns = @intCast(started.untilNow(io).raw.nanoseconds);
        try result;
        return null;
    } else {
        const inherit = spawn_options.stdout == .inherit or spawn_options.stderr == .inherit;
        if (!run.disable_zig_progress and !inherit) {
            spawn_options.progress_node = options.progress_node;
        }
        const terminal_mode: Io.Terminal.Mode = if (inherit) m: {
            const stderr = try io.lockStderr(&.{}, graph.stderr_mode);
            break :m stderr.terminal_mode;
        } else .no_color;
        defer if (inherit) io.unlockStderr();
        try setColorEnvironmentVariables(run, environ_map, terminal_mode);

        const started: Io.Clock.Timestamp = .now(io, .awake);
        const result = evalGeneric(run, spawn_options) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| e,
        };
        run.step.result_duration_ns = @intCast(started.untilNow(io).raw.nanoseconds);
        return try result;
    }
}

fn setColorEnvironmentVariables(run: *Run, environ_map: *EnvMap, terminal_mode: Io.Terminal.Mode) !void {
    color: switch (run.color) {
        .manual => {},
        .enable => {
            try environ_map.put("CLICOLOR_FORCE", "1");
            _ = environ_map.swapRemove("NO_COLOR");
        },
        .disable => {
            try environ_map.put("NO_COLOR", "1");
            _ = environ_map.swapRemove("CLICOLOR_FORCE");
        },
        .inherit => switch (terminal_mode) {
            .no_color, .windows_api => continue :color .disable,
            .escape_codes => continue :color .enable,
        },
        .auto => {
            const capture_stderr = run.captured_stderr != null or switch (run.stdio) {
                .check => |checks| checksContainStderr(checks.items),
                .infer_from_args, .inherit, .zig_test => false,
            };
            if (capture_stderr) {
                continue :color .disable;
            } else {
                continue :color .inherit;
            }
        },
    }
}

const StdioPollEnum = enum { stdout, stderr };

fn evalZigTest(
    run: *Run,
    spawn_options: process.SpawnOptions,
    options: Step.MakeOptions,
    fuzz_context: ?FuzzContext,
) !void {
    if (fuzz_context != null) {
        try evalFuzzTest(run, spawn_options, options, fuzz_context.?);
        return;
    }

    const step_owner = run.step.owner;
    const gpa = step_owner.allocator;
    const arena = step_owner.allocator;
    const io = step_owner.graph.io;

    // We will update this every time a child runs.
    run.step.result_peak_rss = 0;

    var test_results: Step.TestResults = .{
        .test_count = 0,
        .skip_count = 0,
        .fail_count = 0,
        .crash_count = 0,
        .timeout_count = 0,
        .leak_count = 0,
        .log_err_count = 0,
    };
    var test_metadata: ?TestMetadata = null;

    while (true) {
        var child = try process.spawn(io, spawn_options);
        var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
        var multi_reader: Io.File.MultiReader = undefined;
        multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        var child_killed = false;
        defer if (!child_killed) {
            child.kill(io);
            multi_reader.deinit();
            run.step.result_peak_rss = @max(
                run.step.result_peak_rss,
                child.resource_usage_statistics.getMaxRss() orelse 0,
            );
        };

        switch (try waitZigTest(
            run,
            &child,
            options,
            &multi_reader,
            &test_metadata,
            &test_results,
        )) {
            .write_failed => |err| {
                // The runner unexpectedly closed a stdio pipe, which means a crash. Make sure we've captured
                // all available stderr to make our error output as useful as possible.
                const stderr_fr = multi_reader.fileReader(1);
                while (stderr_fr.interface.fillMore()) |_| {} else |e| switch (e) {
                    error.ReadFailed => return stderr_fr.err.?,
                    error.EndOfStream => {},
                }
                run.step.result_stderr = try arena.dupe(u8, stderr_fr.interface.buffered());

                // Clean up everything and wait for the child to exit.
                child.stdin.?.close(io);
                child.stdin = null;
                multi_reader.deinit();
                child_killed = true;
                const term = try child.wait(io);
                run.step.result_peak_rss = @max(
                    run.step.result_peak_rss,
                    child.resource_usage_statistics.getMaxRss() orelse 0,
                );

                // The individual unit test results are irrelevant: the test runner itself broke!
                // Fail immediately without populating `s.test_results`.
                return run.step.fail("unable to write stdin ({t}); test process unexpectedly {f}", .{ err, fmtTerm(term) });
            },
            .no_poll => |no_poll| {
                // This might be a success (we requested exit and the child dutifully closed stdout) or
                // a crash of some kind. Either way, the child will terminate by itself -- wait for it.
                const stderr_reader = multi_reader.reader(1);
                const stderr_owned = try arena.dupe(u8, stderr_reader.buffered());

                // Clean up everything and wait for the child to exit.
                child.stdin.?.close(io);
                child.stdin = null;
                multi_reader.deinit();
                child_killed = true;
                const term = try child.wait(io);
                run.step.result_peak_rss = @max(
                    run.step.result_peak_rss,
                    child.resource_usage_statistics.getMaxRss() orelse 0,
                );

                if (no_poll.active_test_index) |test_index| {
                    // A test was running, so this is definitely a crash. Report it against that
                    // test, and continue to the next test.
                    test_metadata.?.ns_per_test[test_index] = no_poll.ns_elapsed;
                    test_results.crash_count += 1;
                    try run.step.addError("'{s}' {f}{s}{s}", .{
                        test_metadata.?.testName(test_index),
                        fmtTerm(term),
                        if (stderr_owned.len != 0) " with stderr:\n" else "",
                        std.mem.trim(u8, stderr_owned, "\n"),
                    });
                    continue;
                }

                // Report an error if the child terminated uncleanly or if we were still trying to run more tests.
                run.step.result_stderr = stderr_owned;
                const tests_done = test_metadata != null and test_metadata.?.next_index == std.math.maxInt(u32);
                if (!tests_done or !termMatches(.{ .exited = 0 }, term)) {
                    // The individual unit test results are irrelevant: the test runner itself broke!
                    // Fail immediately without populating `s.test_results`.
                    return run.step.fail("test process unexpectedly {f}", .{fmtTerm(term)});
                }

                // We're done with all of the tests! Commit the test results and return.
                run.step.test_results = test_results;
                if (test_metadata) |tm| {
                    run.cached_test_metadata = tm.toCachedTestMetadata();
                    if (options.web_server) |ws| {
                        if (run.step.owner.graph.time_report) {
                            ws.updateTimeReportRunTest(
                                run,
                                &run.cached_test_metadata.?,
                                tm.ns_per_test,
                            );
                        }
                    }
                }
                return;
            },
            .timeout => |timeout| {
                const stderr_reader = multi_reader.reader(1);
                const stderr = stderr_reader.buffered();
                stderr_reader.tossBuffered();
                if (timeout.active_test_index) |test_index| {
                    // A test was running. Report the timeout against that test, and continue on to
                    // the next test.
                    test_metadata.?.ns_per_test[test_index] = timeout.ns_elapsed;
                    test_results.timeout_count += 1;
                    try run.step.addError("'{s}' timed out after {f}{s}{s}", .{
                        test_metadata.?.testName(test_index),
                        Io.Duration{ .nanoseconds = timeout.ns_elapsed },
                        if (stderr.len != 0) " with stderr:\n" else "",
                        std.mem.trim(u8, stderr, "\n"),
                    });
                    continue;
                }
                // Just log an error and let the child be killed.
                run.step.result_stderr = try arena.dupe(u8, stderr);
                // The individual unit test results in `results` are irrelevant: the test runner
                // is broken! Fail immediately without populating `s.test_results`.
                return run.step.fail("test runner failed to respond for {f}", .{Io.Duration{ .nanoseconds = timeout.ns_elapsed }});
            },
        }
        comptime unreachable;
    }
}

/// Reads stdout of a Zig test process until a termination condition is reached:
/// * A write fails, indicating the child unexpectedly closed stdin
/// * A test (or a response from the test runner) times out
/// * The wait fails, indicating the child closed stdout and stderr
fn waitZigTest(
    run: *Run,
    child: *process.Child,
    options: Step.MakeOptions,
    multi_reader: *Io.File.MultiReader,
    opt_metadata: *?TestMetadata,
    results: *Step.TestResults,
) !union(enum) {
    write_failed: anyerror,
    no_poll: struct {
        active_test_index: ?u32,
        ns_elapsed: u64,
    },
    timeout: struct {
        active_test_index: ?u32,
        ns_elapsed: u64,
    },
} {
    const gpa = run.step.owner.allocator;
    const arena = run.step.owner.allocator;
    const io = run.step.owner.graph.io;

    var sub_prog_node: ?std.Progress.Node = null;
    defer if (sub_prog_node) |n| n.end();

    if (opt_metadata.*) |*md| {
        // Previous unit test process died or was killed; we're continuing where it left off
        requestNextTest(io, child.stdin.?, md, &sub_prog_node) catch |err| return .{ .write_failed = err };
    } else {
        // Running unit tests normally
        run.fuzz_tests.clearRetainingCapacity();
        sendMessage(io, child.stdin.?, .query_test_metadata) catch |err| return .{ .write_failed = err };
    }

    var active_test_index: ?u32 = null;

    var last_update: Io.Clock.Timestamp = .now(io, .awake);

    // This timeout is used when we're waiting on the test runner itself rather than a user-specified
    // test. For instance, if the test runner leaves this much time between us requesting a test to
    // start and it acknowledging the test starting, we terminate the child and raise an error. This
    // *should* never happen, but could in theory be caused by some very unlucky IB in a test.
    const response_timeout: Io.Clock.Duration = t: {
        const ns = @max(options.unit_test_timeout_ns orelse 0, 60 * std.time.ns_per_s);
        break :t .{ .clock = .awake, .raw = .fromNanoseconds(ns) };
    };
    const test_timeout: ?Io.Clock.Duration = if (options.unit_test_timeout_ns) |ns| .{
        .clock = .awake,
        .raw = .fromNanoseconds(ns),
    } else null;

    const stdout = multi_reader.reader(0);
    const stderr = multi_reader.reader(1);
    const Header = std.zig.Server.Message.Header;

    while (true) {
        const timeout: Io.Timeout = t: {
            const opt_duration = if (active_test_index == null) response_timeout else test_timeout;
            const duration = opt_duration orelse break :t .none;
            break :t .{ .deadline = last_update.addDuration(duration) };
        };

        // This block is exited when `stdout` contains enough bytes for a `Header`.
        header_ready: {
            if (stdout.buffered().len >= @sizeOf(Header)) {
                // We already have one, no need to poll!
                break :header_ready;
            }

            multi_reader.fill(64, timeout) catch |err| switch (err) {
                error.Timeout => return .{ .timeout = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                error.EndOfStream => return .{ .no_poll = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                else => |e| return e,
            };

            continue;
        }
        // There is definitely a header available now -- read it.
        const header = stdout.takeStruct(Header, .little) catch unreachable;

        while (stdout.buffered().len < header.bytes_len) {
            multi_reader.fill(64, timeout) catch |err| switch (err) {
                error.Timeout => return .{ .timeout = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                error.EndOfStream => return .{ .no_poll = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                else => |e| return e,
            };
        }

        const body = stdout.take(header.bytes_len) catch unreachable;
        var body_r: std.Io.Reader = .fixed(body);
        switch (header.tag) {
            .zig_version => {
                if (!std.mem.eql(u8, builtin.zig_version_string, body)) return run.step.fail(
                    "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                    .{ builtin.zig_version_string, body },
                );
            },
            .test_metadata => {
                // `metadata` would only be populated if we'd already seen a `test_metadata`, but we
                // only request it once (and importantly, we don't re-request it if we kill and
                // restart the test runner).
                assert(opt_metadata.* == null);

                const tm_hdr = body_r.takeStruct(std.zig.Server.Message.TestMetadata, .little) catch unreachable;
                results.test_count = tm_hdr.tests_len;

                const names = try arena.alloc(u32, results.test_count);
                for (names) |*dest| dest.* = body_r.takeInt(u32, .little) catch unreachable;

                const expected_panic_msgs = try arena.alloc(u32, results.test_count);
                for (expected_panic_msgs) |*dest| dest.* = body_r.takeInt(u32, .little) catch unreachable;

                const string_bytes = body_r.take(tm_hdr.string_bytes_len) catch unreachable;

                options.progress_node.setEstimatedTotalItems(names.len);
                opt_metadata.* = .{
                    .string_bytes = try arena.dupe(u8, string_bytes),
                    .ns_per_test = try arena.alloc(u64, results.test_count),
                    .names = names,
                    .expected_panic_msgs = expected_panic_msgs,
                    .next_index = 0,
                    .prog_node = options.progress_node,
                };
                @memset(opt_metadata.*.?.ns_per_test, std.math.maxInt(u64));

                active_test_index = null;
                last_update = .now(io, .awake);

                requestNextTest(io, child.stdin.?, &opt_metadata.*.?, &sub_prog_node) catch |err| return .{ .write_failed = err };
            },
            .test_started => {
                active_test_index = opt_metadata.*.?.next_index - 1;
                last_update = .now(io, .awake);
            },
            .test_results => {
                const md = &opt_metadata.*.?;

                const tr_hdr = body_r.takeStruct(std.zig.Server.Message.TestResults, .little) catch unreachable;
                assert(tr_hdr.index == active_test_index);

                switch (tr_hdr.flags.status) {
                    .pass => {},
                    .skip => results.skip_count +|= 1,
                    .fail => results.fail_count +|= 1,
                }
                const leak_count = tr_hdr.flags.leak_count;
                const log_err_count = tr_hdr.flags.log_err_count;
                results.leak_count +|= leak_count;
                results.log_err_count +|= log_err_count;

                if (tr_hdr.flags.fuzz) try run.fuzz_tests.append(gpa, md.testName(tr_hdr.index));

                if (tr_hdr.flags.status == .fail) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    if (stderr_bytes.len == 0) {
                        try run.step.addError("'{s}' failed without output", .{name});
                    } else {
                        try run.step.addError("'{s}' failed:\n{s}", .{ name, stderr_bytes });
                    }
                } else if (leak_count > 0) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    try run.step.addError("'{s}' leaked {d} allocations:\n{s}", .{ name, leak_count, stderr_bytes });
                } else if (log_err_count > 0) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    try run.step.addError("'{s}' logged {d} errors:\n{s}", .{ name, log_err_count, stderr_bytes });
                }

                active_test_index = null;

                const now: Io.Clock.Timestamp = .now(io, .awake);
                md.ns_per_test[tr_hdr.index] = @intCast(last_update.durationTo(now).raw.nanoseconds);
                last_update = now;

                requestNextTest(io, child.stdin.?, md, &sub_prog_node) catch |err| return .{ .write_failed = err };
            },
            else => {}, // ignore other messages
        }
    }
}

const FuzzTestRunner = struct {
    run: *Run,
    ctx: FuzzContext,
    coverage_id: ?u64,

    instances: []Instance,
    /// The indexes of this are layed out such that it is effectively an array
    /// of `[instances.len][3]Io.Operation.Storage` of stdin, stdout, stderr.
    batch: Io.Batch,
    /// LIFO. Stream of message bodies trailed by PendingBroadcastFooter.
    pending_broadcasts: std.ArrayList(u8),
    broadcast: std.ArrayList(u8),
    broadcast_undelivered: u32,

    const Instance = struct {
        child: process.Child,
        message: std.ArrayListAligned(u8, .@"4"),
        broadcast_written: usize,
        stderr: std.ArrayList(u8),
        stdin_vec: [1][]u8,
        stdout_vec: [1][]u8,
        stderr_vec: [1][]u8,
        progress_node: std.Progress.Node,

        fn messageHeader(instance: *Instance) InHeader {
            assert(instance.message.items.len >= @sizeOf(InHeader));
            const header_ptr: *InHeader = @ptrCast(instance.message.items);
            var header = header_ptr.*;
            if (std.builtin.Endian.native != .little) {
                std.mem.byteSwapAllFields(InHeader, &header);
            }
            return header;
        }
    };

    const PendingBroadcastFooter = struct {
        from_id: u32,
        body_len: u32,
    };

    const InHeader = std.zig.Server.Message.Header;
    const OutHeader = std.zig.Client.Message.Header;

    const stdin_i = 0;
    const stdout_i = 1;
    const stderr_i = 2;

    fn init(
        run: *Run,
        ctx: FuzzContext,
        progress_node: std.Progress.Node,
        spawn_options: process.SpawnOptions,
    ) !FuzzTestRunner {
        const step_owner = run.step.owner;
        const gpa = step_owner.allocator;
        const io = step_owner.graph.io;

        const n_instances = switch (ctx.fuzz.mode) {
            .forever => step_owner.graph.max_jobs orelse @min(
                std.Thread.getCpuCount() catch 1,
                (std.math.maxInt(u32) - 2) / 3,
            ),
            .limit => 1,
        };
        const instances = try gpa.alloc(Instance, n_instances);
        errdefer gpa.free(instances);
        const batch_storage = try gpa.alloc(Io.Operation.Storage, instances.len * 3);
        errdefer gpa.free(batch_storage);

        @memset(instances, .{
            .child = undefined,
            .message = .empty,
            .broadcast_written = undefined,
            .stderr = .empty,
            .stdin_vec = undefined,
            .stdout_vec = undefined,
            .stderr_vec = undefined,
            .progress_node = undefined,
        });
        for (0.., instances) |id, *instance| {
            errdefer for (instances[0..id]) |*spawned| {
                spawned.child.kill(io);
                spawned.progress_node.end();
            };
            instance.child = try process.spawn(io, spawn_options);
            instance.progress_node = progress_node.start("starting fuzzer", 0);
        }

        return .{
            .run = run,
            .ctx = ctx,
            .coverage_id = null,

            .instances = instances,
            .batch = .init(batch_storage),
            .pending_broadcasts = .empty,
            .broadcast = .empty,
            .broadcast_undelivered = 0,
        };
    }

    fn deinit(f: *FuzzTestRunner) void {
        const step_owner = f.run.step.owner;
        const gpa = step_owner.allocator;
        const io = step_owner.graph.io;

        f.batch.cancel(io);
        gpa.free(f.batch.storage);
        var total_rss: usize = 0;
        for (f.instances) |*instance| {
            instance.child.kill(io);
            instance.message.deinit(gpa);
            instance.stderr.deinit(gpa);
            instance.progress_node.end();
            total_rss += instance.child.resource_usage_statistics.getMaxRss() orelse 0;
        }
        f.run.step.result_peak_rss = @max(f.run.step.result_peak_rss, total_rss);
        gpa.free(f.instances);
    }

    fn startInstances(f: *FuzzTestRunner) !void {
        const step_owner = f.run.step.owner;
        const io = step_owner.graph.io;

        for (0.., f.instances) |id, *instance| {
            const id32: u32 = @intCast(id);
            (switch (f.ctx.fuzz.mode) {
                .forever => sendRunFuzzTestMessage(
                    io,
                    instance.child.stdin.?,
                    f.run.fuzz_tests.items,
                    .forever,
                    id32,
                ),
                .limit => |limit| sendRunFuzzTestMessage(
                    io,
                    instance.child.stdin.?,
                    f.run.fuzz_tests.items,
                    .iterations,
                    limit.amount,
                ),
            }) catch |write_err| {
                // The runner unexpectedly closed stdin, which means it crashed during initialization.
                // Clean up everything and wait for the child to exit.
                instance.child.stdin.?.close(io);
                instance.child.stdin = null;
                const term = try instance.child.wait(io);
                return f.run.step.fail(
                    "unable to write stdin ({t}); test process unexpectedly {f}",
                    .{ write_err, fmtTerm(term) },
                );
            };

            try f.addStdoutRead(id32, @sizeOf(InHeader));
            try f.addStderrRead(id32);
        }
    }

    fn listen(f: *FuzzTestRunner) !void {
        const step_owner = f.run.step.owner;
        const io = step_owner.graph.io;

        while (true) {
            try f.batch.awaitConcurrent(io, .none);
            while (f.batch.next()) |completion| {
                const id = completion.index / 3;
                const result = completion.result;
                switch (completion.index % 3) {
                    0 => try f.completeStdinWrite(id, result.file_write_streaming catch |e| switch (e) {
                        error.BrokenPipe => return f.instanceEos(id),
                        else => |write_e| return write_e,
                    }),
                    1 => try f.completeStdoutRead(id, result.file_read_streaming catch |e| switch (e) {
                        error.EndOfStream => return f.instanceEos(id),
                        else => |read_e| return read_e,
                    }),
                    2 => try f.completeStderrRead(id, result.file_read_streaming catch |e| switch (e) {
                        error.EndOfStream => return f.instanceEos(id),
                        else => |read_e| return read_e,
                    }),
                    else => unreachable,
                }
            }
        }
    }

    fn completeStdoutRead(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const step_owner = f.run.step.owner;
        const gpa = step_owner.allocator;
        const io = step_owner.graph.io;
        const instance = &f.instances[id];

        instance.message.items.len += n;
        const total_read = instance.message.items.len;
        if (total_read < @sizeOf(InHeader)) {
            try f.addStdoutRead(id, @sizeOf(InHeader));
            return;
        }

        const header = instance.messageHeader();
        const body = instance.message.items[@sizeOf(InHeader)..];
        if (body.len != header.bytes_len) {
            try f.addStdoutRead(id, @sizeOf(InHeader) + header.bytes_len);
            return;
        }

        switch (header.tag) {
            .zig_version => {
                if (!std.mem.eql(u8, builtin.zig_version_string, body)) return f.run.step.fail(
                    "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                    .{ builtin.zig_version_string, body },
                );
            },
            .coverage_id => {
                var body_r: Io.Reader = .fixed(body);
                f.coverage_id = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_runs = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_unique = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_coverage = body_r.takeInt(u64, .little) catch unreachable;

                const fuzz = f.ctx.fuzz;
                fuzz.queue_mutex.lockUncancelable(io);
                defer fuzz.queue_mutex.unlock(io);
                try fuzz.msg_queue.append(fuzz.gpa, .{ .coverage = .{
                    .id = f.coverage_id.?,
                    .cumulative = .{
                        .runs = cumulative_runs,
                        .unique = cumulative_unique,
                        .coverage = cumulative_coverage,
                    },
                    .run = f.run,
                } });
                fuzz.queue_cond.signal(io);
            },
            .fuzz_start_addr => {
                var body_r: Io.Reader = .fixed(body);
                const fuzz = f.ctx.fuzz;
                const addr = body_r.takeInt(u64, .little) catch unreachable;

                fuzz.queue_mutex.lockUncancelable(io);
                defer fuzz.queue_mutex.unlock(io);
                try fuzz.msg_queue.append(fuzz.gpa, .{ .entry_point = .{
                    .addr = addr,
                    .coverage_id = f.coverage_id.?,
                } });
                fuzz.queue_cond.signal(io);
            },
            .fuzz_test_change => {
                const test_i = std.mem.readInt(u32, body[0..4], .little);
                instance.progress_node.setName(f.run.fuzz_tests.items[test_i]);
            },
            .broadcast_fuzz_input => {
                if (f.instances.len == 1) {
                    // No other processes to broadcast to.
                } else if (f.broadcast_undelivered == 0) {
                    try f.instanceBroadcast(id, body);
                } else {
                    const footer: PendingBroadcastFooter = .{
                        .from_id = id,
                        .body_len = @intCast(body.len),
                    };
                    // There is another broadcast in progress so add this one to the queue.
                    const size = @sizeOf(PendingBroadcastFooter) + body.len;
                    try f.pending_broadcasts.ensureUnusedCapacity(gpa, size);
                    f.pending_broadcasts.appendSliceAssumeCapacity(body);
                    f.pending_broadcasts.appendSliceAssumeCapacity(@ptrCast(&footer));
                }
            },
            else => {}, // ignore other messages
        }

        instance.message.clearRetainingCapacity();
        try f.addStdoutRead(id, @sizeOf(InHeader));
    }

    fn completeStderrRead(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const instance = &f.instances[id];
        instance.stderr.items.len += n;
        try f.addStderrRead(id);
    }

    fn completeStdinWrite(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const instance = &f.instances[id];

        instance.broadcast_written += n;
        if (instance.broadcast_written == f.broadcast.items.len) {
            f.broadcast_undelivered -= 1;
            if (f.broadcast_undelivered == 0) {
                try f.broadcastComplete();
            }
        } else {
            f.addStdinWrite(id);
        }
    }

    fn addStdoutRead(f: *FuzzTestRunner, id: u32, end: usize) !void {
        const step_owner = f.run.step.owner;
        const gpa = step_owner.allocator;
        const instance = &f.instances[id];

        try instance.message.ensureTotalCapacity(gpa, end);
        const start = instance.message.items.len;
        instance.stdout_vec = .{instance.message.allocatedSlice()[start..end]};
        f.batch.addAt(id * 3 + stdout_i, .{ .file_read_streaming = .{
            .file = instance.child.stdout.?,
            .data = &instance.stdout_vec,
        } });
    }

    fn addStderrRead(f: *FuzzTestRunner, id: u32) !void {
        const step_owner = f.run.step.owner;
        const gpa = step_owner.allocator;
        const instance = &f.instances[id];

        try instance.stderr.ensureUnusedCapacity(gpa, 1);
        instance.stderr_vec = .{instance.stderr.unusedCapacitySlice()};
        f.batch.addAt(id * 3 + stderr_i, .{ .file_read_streaming = .{
            .file = instance.child.stderr.?,
            .data = &instance.stderr_vec,
        } });
    }

    fn addStdinWrite(f: *FuzzTestRunner, id: u32) void {
        const instance = &f.instances[id];

        assert(f.broadcast.items.len != instance.broadcast_written);
        instance.stdin_vec = .{f.broadcast.items[instance.broadcast_written..]};
        f.batch.addAt(id * 3 + stdin_i, .{ .file_write_streaming = .{
            .file = instance.child.stdin.?,
            .data = &instance.stdin_vec,
        } });
    }

    fn instanceEos(f: *FuzzTestRunner, id: u32) !void {
        const step_owner = f.run.step.owner;
        const io = step_owner.graph.io;
        const instance = &f.instances[id];

        instance.child.stdin.?.close(io);
        instance.child.stdin = null;
        const term = try instance.child.wait(io);
        if (!termMatches(.{ .exited = 0 }, term)) {
            f.run.step.result_stderr = try f.mergedStderr();
            try f.saveCrash(id, term);
            return f.run.step.fail("test process unexpectedly {f}", .{fmtTerm(term)});
        }
    }

    fn saveCrash(f: *FuzzTestRunner, id: u32, term: process.Child.Term) !void {
        const step = &f.run.step;
        const b = step.owner;
        const io = b.graph.io;

        if (f.coverage_id == null) return;

        // Search for the input file corresponding to the instance
        const InputHeader = Build.abi.fuzz.MmapInputHeader;
        var in_r_buf: [@sizeOf(InputHeader)]u8 = undefined;
        var in_r: Io.File.Reader = undefined;
        var in_f: Io.File = undefined;
        var in_name_buf: [12]u8 = undefined;
        var in_name: []const u8 = undefined;
        var i: u32 = 0;
        const header: InputHeader = while (true) {
            const name_prefix = "f" ++ Io.Dir.path.sep_str ++ "in";
            in_name = std.fmt.bufPrint(&in_name_buf, name_prefix ++ "{x}", .{i}) catch unreachable;
            in_f = b.cache_root.handle.openFile(io, in_name, .{
                .lock = .exclusive,
                .lock_nonblocking = true,
            }) catch |e| switch (e) {
                error.FileNotFound => return,
                error.WouldBlock => continue, // Can not be from
                // the crashed instance since it is still locked.
                else => return step.fail("failed to open file '{f}{s}': {t}", .{
                    b.cache_root, in_name, e,
                }),
            };

            in_r = in_f.readerStreaming(io, &in_r_buf);
            const header = in_r.interface.takeStruct(InputHeader, .little) catch |e| {
                in_f.close(io);
                switch (e) {
                    error.ReadFailed => return step.fail("failed to read file '{f}{s}': {t}", .{
                        b.cache_root, in_name, in_r.err.?,
                    }),
                    error.EndOfStream => continue,
                }
            };

            if (header.pc_digest == f.coverage_id.? and
                header.instance_id == id and
                header.test_i < f.run.fuzz_tests.items.len)
            {
                break header;
            }

            in_f.close(io);
            if (i == std.math.maxInt(u32)) return;
            i += 1;
        };
        defer in_f.close(io);

        // Save it to a seperate file
        const crash_name = "f" ++ Io.Dir.path.sep_str ++ "crash";
        const out = b.cache_root.handle.createFile(io, crash_name, .{
            .lock = .exclusive, // Multiple run steps could have found a crash at the same time
        }) catch |e| return step.fail("failed to create file '{f}{s}': {t}", .{
            b.cache_root, crash_name, e,
        });
        defer out.close(io);

        var out_w_buf: [512]u8 = undefined;
        var out_w = out.writerStreaming(io, &out_w_buf);
        _ = out_w.interface.sendFileAll(&in_r, .limited(header.len)) catch |e| switch (e) {
            error.ReadFailed => return step.fail("failed to read file '{f}{s}': {t}", .{
                b.cache_root, in_name, in_r.err.?,
            }),
            error.WriteFailed => return step.fail("failed to write file '{f}{s}': {t}", .{
                b.cache_root, crash_name, out_w.err.?,
            }),
        };

        return f.run.step.fail("test '{s}' {f}; input saved to '{f}{s}'", .{
            f.run.fuzz_tests.items[header.test_i],
            fmtTerm(term),
            b.cache_root,
            crash_name,
        });
    }

    fn instanceBroadcast(f: *FuzzTestRunner, from_id: u32, bytes: []const u8) !void {
        assert(f.instances.len > 1);
        assert(f.broadcast_undelivered == 0); // no other broadcast is progress
        assert(f.broadcast.items.len == 0);
        assert(from_id < f.instances.len);

        const step_owner = f.run.step.owner;
        const gpa = step_owner.allocator;

        var out_header: OutHeader = .{
            .tag = .new_fuzz_input,
            .bytes_len = @intCast(bytes.len),
        };
        if (std.builtin.Endian.native != .little) {
            std.mem.byteSwapAllFields(OutHeader, &out_header);
        }
        try f.broadcast.ensureTotalCapacity(gpa, @sizeOf(OutHeader) + bytes.len);
        f.broadcast.appendSliceAssumeCapacity(@ptrCast(&out_header));
        f.broadcast.appendSliceAssumeCapacity(bytes);

        f.broadcast_undelivered = @intCast(f.instances.len - 1);
        for (0.., f.instances) |to_id, *instance| {
            if (to_id == from_id) continue;
            instance.broadcast_written = 0;
            f.addStdinWrite(@intCast(to_id));
        }
    }

    fn broadcastComplete(f: *FuzzTestRunner) !void {
        assert(f.instances.len > 1);
        assert(f.broadcast_undelivered == 0);
        f.broadcast.clearRetainingCapacity();

        const pending = &f.pending_broadcasts;
        if (pending.items.len != 0) {
            // Another broadcast is pending; copy it over to `broadcast`

            const footer_len = @sizeOf(PendingBroadcastFooter);
            const footer_bytes = pending.items[pending.items.len - footer_len ..];
            const footer: *align(1) PendingBroadcastFooter = @ptrCast(footer_bytes);
            pending.items.len -= footer_len;

            const body = pending.items[pending.items.len - footer.body_len ..];
            try f.instanceBroadcast(footer.from_id, body);
            pending.items.len -= body.len;
        }
    }

    fn mergedStderr(f: *FuzzTestRunner) std.mem.Allocator.Error![]const u8 {
        const step_owner = f.run.step.owner;
        const arena = step_owner.allocator;

        // Collect any remaining stderr
        while (f.batch.next()) |completion| {
            if (completion.index % 3 != 2) continue;
            const len = completion.result.file_read_streaming catch continue;
            f.instances[completion.index / 3].stderr.items.len += len;
        }

        var stderr_len: usize = 0;
        for (f.instances) |*instance| stderr_len += instance.stderr.items.len;
        const stderr = try arena.alloc(u8, stderr_len);

        stderr_len = 0;
        for (f.instances) |*instance| {
            @memcpy(stderr[stderr_len..][0..instance.stderr.items.len], instance.stderr.items);
            stderr_len += instance.stderr.items.len;
        }
        return stderr;
    }
};

fn evalFuzzTest(
    run: *Run,
    spawn_options: process.SpawnOptions,
    options: Step.MakeOptions,
    fuzz_context: FuzzContext,
) !void {
    var f: FuzzTestRunner = try .init(run, fuzz_context, options.progress_node, spawn_options);
    defer f.deinit();
    try f.startInstances();
    try f.listen();
}

const TestMetadata = struct {
    names: []const u32,
    ns_per_test: []u64,
    expected_panic_msgs: []const u32,
    string_bytes: []const u8,
    next_index: u32,
    prog_node: std.Progress.Node,

    fn toCachedTestMetadata(tm: TestMetadata) CachedTestMetadata {
        return .{
            .names = tm.names,
            .string_bytes = tm.string_bytes,
        };
    }

    fn testName(tm: TestMetadata, index: u32) []const u8 {
        return tm.toCachedTestMetadata().testName(index);
    }
};

pub const CachedTestMetadata = struct {
    names: []const u32,
    string_bytes: []const u8,

    pub fn testName(tm: CachedTestMetadata, index: u32) []const u8 {
        return std.mem.sliceTo(tm.string_bytes[tm.names[index]..], 0);
    }
};

fn requestNextTest(io: Io, in: Io.File, metadata: *TestMetadata, sub_prog_node: *?std.Progress.Node) !void {
    while (metadata.next_index < metadata.names.len) {
        const i = metadata.next_index;
        metadata.next_index += 1;

        if (metadata.expected_panic_msgs[i] != 0) continue;

        const name = metadata.testName(i);
        if (sub_prog_node.*) |n| n.end();
        sub_prog_node.* = metadata.prog_node.start(name, 0);

        try sendRunTestMessage(io, in, .run_test, i);
        return;
    } else {
        metadata.next_index = std.math.maxInt(u32); // indicate that all tests are done
        try sendMessage(io, in, .exit);
    }
}

fn sendMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 0,
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

fn sendRunTestMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag, index: u32) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 4,
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u32, index, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

fn sendRunFuzzTestMessage(
    io: Io,
    file: Io.File,
    test_names: []const []const u8,
    kind: std.Build.abi.fuzz.LimitKind,
    amount_or_instance: u64,
) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = .start_fuzzing,
        .bytes_len = 1 + 8 + 4 + count: {
            var c: u32 = @intCast(test_names.len * 4);
            for (test_names) |name| {
                c += @intCast(name.len);
            }
            break :count c;
        },
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeByte(@intFromEnum(kind)) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u64, amount_or_instance, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u32, @intCast(test_names.len), .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    for (test_names) |test_name| {
        w.interface.writeInt(u32, @intCast(test_name.len), .little) catch |err| switch (err) {
            error.WriteFailed => return w.err.?,
        };
        w.interface.writeAll(test_name) catch |err| switch (err) {
            error.WriteFailed => return w.err.?,
        };
    }
}

fn evalGeneric(run: *Run, spawn_options: process.SpawnOptions) !EvalGenericResult {
    const b = run.step.owner;
    const io = b.graph.io;
    const arena = b.allocator;
    const gpa = b.allocator;

    var child = try process.spawn(io, spawn_options);
    defer child.kill(io);

    switch (run.stdin) {
        .bytes => |bytes| {
            child.stdin.?.writeStreamingAll(io, bytes) catch |err| {
                return run.step.fail("unable to write stdin: {t}", .{err});
            };
            child.stdin.?.close(io);
            child.stdin = null;
        },
        .lazy_path => |lazy_path| {
            const path = lazy_path.getPath3(b, &run.step);
            const file = path.root_dir.handle.openFile(io, path.subPathOrDot(), .{}) catch |err| {
                return run.step.fail("unable to open stdin file: {t}", .{err});
            };
            defer file.close(io);
            // TODO https://github.com/ziglang/zig/issues/23955
            var read_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(io, &read_buffer);
            var write_buffer: [1024]u8 = undefined;
            var stdin_writer = child.stdin.?.writerStreaming(io, &write_buffer);
            _ = stdin_writer.interface.sendFileAll(&file_reader, .unlimited) catch |err| switch (err) {
                error.ReadFailed => return run.step.fail("failed to read from {f}: {t}", .{
                    path, file_reader.err.?,
                }),
                error.WriteFailed => return run.step.fail("failed to write to stdin: {t}", .{
                    stdin_writer.err.?,
                }),
            };
            stdin_writer.interface.flush() catch |err| switch (err) {
                error.WriteFailed => return run.step.fail("failed to write to stdin: {t}", .{
                    stdin_writer.err.?,
                }),
            };
            child.stdin.?.close(io);
            child.stdin = null;
        },
        .none => {},
    }

    var stdout_bytes: ?[]const u8 = null;
    var stderr_bytes: ?[]const u8 = null;

    if (child.stdout) |stdout| {
        if (child.stderr) |stderr| {
            var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
            var multi_reader: Io.File.MultiReader = undefined;
            multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ stdout, stderr });
            defer multi_reader.deinit();

            const stdout_reader = multi_reader.reader(0);
            const stderr_reader = multi_reader.reader(1);

            while (multi_reader.fill(64, .none)) |_| {
                if (run.stdio_limit.toInt()) |limit| {
                    if (stdout_reader.buffered().len > limit)
                        return error.StdoutStreamTooLong;
                    if (stderr_reader.buffered().len > limit)
                        return error.StderrStreamTooLong;
                }
            } else |err| switch (err) {
                error.Timeout => unreachable,
                error.EndOfStream => {},
                else => |e| return e,
            }

            try multi_reader.checkAnyError();

            stdout_bytes = try multi_reader.toOwnedSlice(0);
            stderr_bytes = try multi_reader.toOwnedSlice(1);
        } else {
            var stdout_reader = stdout.readerStreaming(io, &.{});
            stdout_bytes = stdout_reader.interface.allocRemaining(arena, run.stdio_limit) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.ReadFailed => return stdout_reader.err.?,
                error.StreamTooLong => return error.StdoutStreamTooLong,
            };
        }
    } else if (child.stderr) |stderr| {
        var stderr_reader = stderr.readerStreaming(io, &.{});
        stderr_bytes = stderr_reader.interface.allocRemaining(arena, run.stdio_limit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return stderr_reader.err.?,
            error.StreamTooLong => return error.StderrStreamTooLong,
        };
    }

    if (stderr_bytes) |bytes| if (bytes.len > 0) {
        // Treat stderr as an error message.
        const stderr_is_diagnostic = run.captured_stderr == null and switch (run.stdio) {
            .check => |checks| !checksContainStderr(checks.items),
            else => true,
        };
        if (stderr_is_diagnostic) {
            run.step.result_stderr = bytes;
        }
    };

    run.step.result_peak_rss = child.resource_usage_statistics.getMaxRss() orelse 0;

    return .{
        .term = try child.wait(io),
        .stdout = stdout_bytes,
        .stderr = stderr_bytes,
    };
}

fn addPathForDynLibs(run: *Run, artifact: *Step.Compile) void {
    const b = run.step.owner;
    const compiles = artifact.getCompileDependencies(true);
    for (compiles) |compile| {
        if (compile.root_module.resolved_target.?.result.os.tag == .windows and
            compile.isDynamicLibrary())
        {
            addPathDir(run, Dir.path.dirname(compile.getEmittedBin().getPath2(b, &run.step)).?);
        }
    }
}

fn failForeign(
    run: *Run,
    suggested_flag: []const u8,
    argv0: []const u8,
    exe: *Step.Compile,
) error{ MakeFailed, MakeSkipped, OutOfMemory } {
    switch (run.stdio) {
        .check, .zig_test => {
            if (run.skip_foreign_checks)
                return error.MakeSkipped;

            const b = run.step.owner;
            const host_name = try b.graph.host.result.zigTriple(b.allocator);
            const foreign_name = try exe.rootModuleTarget().zigTriple(b.allocator);

            return run.step.fail(
                \\unable to spawn foreign binary '{s}' ({s}) on host system ({s})
                \\  consider using {s} or enabling skip_foreign_checks in the Run step
            , .{ argv0, foreign_name, host_name, suggested_flag });
        },
        else => {
            return run.step.fail("unable to spawn foreign binary '{s}'", .{argv0});
        },
    }
}

fn hashStdIo(hh: *std.Build.Cache.HashHelper, stdio: StdIo) void {
    switch (stdio) {
        .infer_from_args, .inherit, .zig_test => {},
        .check => |checks| for (checks.items) |check| {
            hh.add(@as(std.meta.Tag(StdIo.Check), check));
            switch (check) {
                .expect_stderr_exact,
                .expect_stderr_match,
                .expect_stdout_exact,
                .expect_stdout_match,
                => |s| hh.addBytes(s),

                .expect_term => |term| {
                    hh.add(@as(std.meta.Tag(process.Child.Term), term));
                    switch (term) {
                        inline .exited, .signal, .stopped => |x| hh.add(x),
                        .unknown => |x| hh.add(x),
                    }
                },
            }
        },
    }
}
