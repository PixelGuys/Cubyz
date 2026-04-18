const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;

const usage = "usage: incr-check <zig binary path> <input file> [--zig-lib-dir lib] [--debug-log foo] [--preserve-tmp] [--zig-cc-binary /path/to/zig]";

pub const std_options: std.Options = .{
    .logFn = logImpl,
};
var log_cur_update: ?struct { *const Case.Target, *const Case.Update } = null;
fn logImpl(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const target, const update = log_cur_update orelse {
        return std.log.defaultLog(level, scope, format, args);
    };
    std.log.defaultLog(
        level,
        scope,
        "[{s}-{t} '{s}'] " ++ format,
        .{ target.query, target.backend, update.name } ++ args,
    );
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const fatal = std.process.fatal;
    const arena = init.arena.allocator();
    const io = init.io;
    const environ_map = init.environ_map;
    const cwd_path = try std.process.currentPathAlloc(io, arena);

    var opt_zig_exe: ?[]const u8 = null;
    var opt_input_file_name: ?[]const u8 = null;
    var opt_lib_dir: ?[]const u8 = null;
    var opt_cc_zig: ?[]const u8 = null;
    var preserve_tmp = false;
    var enable_qemu: bool = false;
    var enable_wine: bool = false;
    var enable_wasmtime: bool = false;
    var enable_darling: bool = false;

    var debug_log_args: std.ArrayList([]const u8) = .empty;

    var arg_it = try init.minimal.args.iterateAllocator(arena);
    _ = arg_it.skip();
    while (arg_it.next()) |arg| {
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--zig-lib-dir")) {
                opt_lib_dir = arg_it.next() orelse fatal("expected arg after --zig-lib-dir\n{s}", .{usage});
            } else if (std.mem.eql(u8, arg, "--debug-log")) {
                try debug_log_args.append(
                    arena,
                    arg_it.next() orelse fatal("expected arg after --debug-log\n{s}", .{usage}),
                );
            } else if (std.mem.eql(u8, arg, "--preserve-tmp")) {
                preserve_tmp = true;
            } else if (std.mem.eql(u8, arg, "-fqemu")) {
                enable_qemu = true;
            } else if (std.mem.eql(u8, arg, "-fwine")) {
                enable_wine = true;
            } else if (std.mem.eql(u8, arg, "-fwasmtime")) {
                enable_wasmtime = true;
            } else if (std.mem.eql(u8, arg, "-fdarling")) {
                enable_darling = true;
            } else if (std.mem.eql(u8, arg, "--zig-cc-binary")) {
                opt_cc_zig = arg_it.next() orelse fatal("expected arg after --zig-cc-binary\n{s}", .{usage});
            } else {
                fatal("unknown option '{s}'\n{s}", .{ arg, usage });
            }
            continue;
        }
        if (opt_zig_exe == null) {
            opt_zig_exe = arg;
        } else if (opt_input_file_name == null) {
            opt_input_file_name = arg;
        } else {
            fatal("unknown argument '{s}'\n{s}", .{ arg, usage });
        }
    }
    const zig_exe = opt_zig_exe orelse fatal("missing path to zig\n{s}", .{usage});
    const input_file_name = opt_input_file_name orelse fatal("missing input file\n{s}", .{usage});

    const input_file_bytes = try Dir.cwd().readFileAlloc(io, input_file_name, arena, .limited(std.math.maxInt(u32)));
    const case = try Case.parse(arena, io, input_file_bytes);

    // Check now: if there are any targets using the `cbe` backend, we need the lib dir.
    if (opt_lib_dir == null) {
        for (case.targets) |target| {
            if (target.backend == .cbe) {
                fatal("'--zig-lib-dir' requried when using backend 'cbe'", .{});
            }
        }
    }

    const prog_node = std.Progress.start(io, .{});
    defer prog_node.end();

    const rand_int = rand64(io);
    const tmp_dir_path = "tmp_" ++ std.fmt.hex(rand_int);
    var tmp_dir = try Dir.cwd().createDirPathOpen(io, tmp_dir_path, .{});
    defer {
        tmp_dir.close(io);
        if (!preserve_tmp) {
            Dir.cwd().deleteTree(io, tmp_dir_path) catch |err| {
                std.log.warn("failed to delete tree '{s}': {t}", .{ tmp_dir_path, err });
            };
        }
    }

    // Convert paths to be relative to the cwd of the subprocess.
    const resolved_zig_exe = try Dir.path.relative(arena, cwd_path, environ_map, tmp_dir_path, zig_exe);
    const opt_resolved_lib_dir = if (opt_lib_dir) |lib_dir|
        try Dir.path.relative(arena, cwd_path, environ_map, tmp_dir_path, lib_dir)
    else
        null;

    const host = try std.zig.system.resolveTargetQuery(io, .{});

    const debug_log_verbose = debug_log_args.items.len != 0;

    for (case.targets) |target| {
        const target_prog_node = node: {
            var name_buf: [std.Progress.Node.max_name_len]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "{s}-{t}", .{ target.query, target.backend }) catch &name_buf;
            break :node prog_node.start(name, case.updates.len);
        };
        defer target_prog_node.end();

        if (debug_log_verbose) {
            std.log.scoped(.status).info("target: '{s}-{t}'", .{ target.query, target.backend });
        }
        var child_args: std.ArrayList([]const u8) = .empty;
        try child_args.appendSlice(arena, &.{
            resolved_zig_exe,
            "build-exe",
            "-fincremental",
            "-fno-ubsan-rt",
            "-target",
            target.query,
            "--cache-dir",
            ".local-cache",
            "--global-cache-dir",
            ".global-cache",
        });
        try child_args.append(arena, "--listen=-");

        if (opt_resolved_lib_dir) |resolved_lib_dir| {
            try child_args.appendSlice(arena, &.{ "--zig-lib-dir", resolved_lib_dir });
        }
        switch (target.backend) {
            .sema => try child_args.append(arena, "-fno-emit-bin"),
            .selfhosted => try child_args.appendSlice(arena, &.{ "-fno-llvm", "-fno-lld" }),
            .llvm => try child_args.appendSlice(arena, &.{ "-fllvm", "-flld" }),
            .cbe => try child_args.appendSlice(arena, &.{ "-ofmt=c", "-lc" }),
        }
        for (debug_log_args.items) |arg| {
            try child_args.appendSlice(arena, &.{ "--debug-log", arg });
        }
        for (case.modules) |mod| {
            try child_args.appendSlice(arena, &.{ "--dep", mod.name });
        }
        try child_args.append(arena, try std.fmt.allocPrint(arena, "-Mroot={s}", .{case.root_source_file}));
        for (case.modules) |mod| {
            try child_args.append(arena, try std.fmt.allocPrint(arena, "-M{s}={s}", .{ mod.name, mod.file }));
        }

        const zig_prog_node = target_prog_node.start("zig build-exe", 0);
        defer zig_prog_node.end();

        var cc_child_args: std.ArrayList([]const u8) = .empty;
        if (target.backend == .cbe) {
            const resolved_cc_zig_exe = if (opt_cc_zig) |cc_zig_exe|
                try Dir.path.relative(arena, cwd_path, environ_map, tmp_dir_path, cc_zig_exe)
            else
                resolved_zig_exe;

            try cc_child_args.appendSlice(arena, &.{
                resolved_cc_zig_exe,
                "cc",
                "-target",
                target.query,
                "-I",
                opt_resolved_lib_dir.?, // verified earlier
            });

            try cc_child_args.append(arena, "-o");
        }

        var child = try std.process.spawn(io, .{
            .argv = child_args.items,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
            .progress_node = zig_prog_node,
            .cwd = .{ .path = tmp_dir_path },
        });
        defer child.kill(io);

        var eval: Eval = .{
            .arena = arena,
            .io = io,
            .case = case,
            .host = host,
            .target = target,
            .tmp_dir = tmp_dir,
            .tmp_dir_path = tmp_dir_path,
            .child = &child,
            .allow_stderr = debug_log_verbose,
            .preserve_tmp_on_fatal = preserve_tmp,
            .cc_child_args = &cc_child_args,
            .enable_qemu = enable_qemu,
            .enable_wine = enable_wine,
            .enable_wasmtime = enable_wasmtime,
            .enable_darling = enable_darling,
        };

        var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
        var multi_reader: Io.File.MultiReader = undefined;
        multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer multi_reader.deinit();

        for (case.updates) |update| {
            var update_node = target_prog_node.start(update.name, 0);
            defer update_node.end();

            if (debug_log_verbose) {
                std.log.scoped(.status).info("update: '{s}'", .{update.name});
            }

            log_cur_update = .{ &target, &update };
            defer log_cur_update = null;

            eval.write(update);
            try eval.requestUpdate();
            try eval.check(&multi_reader, update, update_node);
        }

        try eval.end(&multi_reader);

        waitChild(&child, &eval);
    }
}

const Eval = struct {
    arena: Allocator,
    io: Io,
    host: std.Target,
    case: Case,
    target: Case.Target,
    tmp_dir: Dir,
    tmp_dir_path: []const u8,
    child: *std.process.Child,
    allow_stderr: bool,
    preserve_tmp_on_fatal: bool,
    /// When `target.backend == .cbe`, this contains the first few arguments to `zig cc` to build the generated binary.
    /// The arguments `out.c in.c` must be appended before spawning the subprocess.
    cc_child_args: *std.ArrayList([]const u8),

    enable_qemu: bool,
    enable_wine: bool,
    enable_wasmtime: bool,
    enable_darling: bool,

    /// Currently this function assumes the previous updates have already been written.
    fn write(eval: *Eval, update: Case.Update) void {
        const io = eval.io;
        for (update.changes) |full_contents| {
            eval.tmp_dir.writeFile(io, .{
                .sub_path = full_contents.name,
                .data = full_contents.bytes,
            }) catch |err| {
                eval.fatal("failed to update '{s}': {t}", .{ full_contents.name, err });
            };
        }
        for (update.deletes) |doomed_name| {
            eval.tmp_dir.deleteFile(io, doomed_name) catch |err| {
                eval.fatal("failed to delete '{s}': {t}", .{ doomed_name, err });
            };
        }
    }

    fn check(eval: *Eval, mr: *Io.File.MultiReader, update: Case.Update, prog_node: std.Progress.Node) !void {
        const arena = eval.arena;
        const stdout = mr.fileReader(0);
        const stderr = &mr.fileReader(1).interface;
        const Header = std.zig.Server.Message.Header;

        while (true) {
            const header = stdout.interface.takeStruct(Header, .little) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return stdout.err.?,
            };
            const body = stdout.interface.take(header.bytes_len) catch |err| switch (err) {
                // If this panic triggers it might be helpful to rework this
                // code to print the stderr from the abnormally terminated child.
                error.EndOfStream => @panic("unexpected mid-message end of stream"),
                error.ReadFailed => return stdout.err.?,
            };

            switch (header.tag) {
                .error_bundle => {
                    const result_error_bundle = try std.zig.Server.allocErrorBundle(arena, body);
                    if (stderr.bufferedLen() > 0) {
                        if (eval.allow_stderr) {
                            std.log.info("error_bundle stderr:\n{s}", .{stderr.buffered()});
                        } else {
                            eval.fatal("error_bundle unexpected stderr:\n{s}", .{stderr.buffered()});
                        }
                        stderr.tossBuffered();
                    }
                    if (result_error_bundle.errorMessageCount() != 0) {
                        try eval.checkErrorOutcome(update, result_error_bundle);
                    }
                    // This message indicates the end of the update.
                    return;
                },
                .emit_digest => {
                    var r: std.Io.Reader = .fixed(body);
                    _ = r.takeStruct(std.zig.Server.Message.EmitDigest, .little) catch unreachable;

                    if (stderr.bufferedLen() > 0) {
                        if (eval.allow_stderr) {
                            std.log.info("emit_digest stderr:\n{s}", .{stderr.buffered()});
                        } else {
                            eval.fatal("emit_digest unexpected stderr:\n{s}", .{stderr.buffered()});
                        }
                        stderr.tossBuffered();
                    }
                    if (eval.target.backend == .sema) {
                        try eval.checkSuccessOutcome(update, null, prog_node);
                        continue;
                    }

                    const digest = r.takeArray(Cache.bin_digest_len) catch unreachable;
                    const result_dir = ".local-cache" ++ Dir.path.sep_str ++ "o" ++ Dir.path.sep_str ++ Cache.binToHex(digest.*);

                    const bin_name = try std.zig.EmitArtifact.bin.cacheName(arena, .{
                        .root_name = "root", // corresponds to the module name "root"
                        .target = &eval.target.resolved,
                        .output_mode = .Exe,
                    });
                    const bin_path = try Dir.path.join(arena, &.{ result_dir, bin_name });

                    try eval.checkSuccessOutcome(update, bin_path, prog_node);
                },
                else => {
                    // Ignore other messages.
                },
            }
        }

        const buffered_stderr = stderr.buffered();
        if (buffered_stderr.len > 0) {
            if (eval.allow_stderr) {
                std.log.info("stderr:\n{s}", .{buffered_stderr});
            } else {
                eval.fatal("unexpected stderr:\n{s}", .{buffered_stderr});
            }
        }

        waitChild(eval.child, eval);
        eval.fatal("compiler failed to send terminating error_bundle", .{});
    }

    fn checkErrorOutcome(eval: *Eval, update: Case.Update, error_bundle: std.zig.ErrorBundle) !void {
        const io = eval.io;
        const expected = switch (update.outcome) {
            .unknown => return,
            .compile_errors => |ce| ce,
            .stdout, .exit_code => {
                try error_bundle.renderToStderr(io, .{}, .auto);
                eval.fatal("unexpected compile errors", .{});
            },
        };

        var expected_idx: usize = 0;

        for (error_bundle.getMessages()) |err_idx| {
            if (expected_idx == expected.errors.len) {
                try error_bundle.renderToStderr(io, .{}, .auto);
                eval.fatal("more errors than expected", .{});
            }
            try eval.checkOneError(error_bundle, expected.errors[expected_idx], false, err_idx);
            expected_idx += 1;

            for (error_bundle.getNotes(err_idx)) |note_idx| {
                if (expected_idx == expected.errors.len) {
                    try error_bundle.renderToStderr(io, .{}, .auto);
                    eval.fatal("more error notes than expected", .{});
                }
                try eval.checkOneError(error_bundle, expected.errors[expected_idx], true, note_idx);
                expected_idx += 1;
            }
        }

        if (!std.mem.eql(u8, error_bundle.getCompileLogOutput(), expected.compile_log_output)) {
            try error_bundle.renderToStderr(io, .{}, .auto);
            eval.fatal("unexpected compile log output", .{});
        }
    }

    fn checkOneError(
        eval: *Eval,
        eb: std.zig.ErrorBundle,
        expected: Case.ExpectedError,
        is_note: bool,
        err_idx: std.zig.ErrorBundle.MessageIndex,
    ) Allocator.Error!void {
        const io = eval.io;
        const err = eb.getErrorMessage(err_idx);
        if (err.count != 1) @panic("TODO error message with count>1");
        const msg = eb.nullTerminatedString(err.msg);
        const matches = matches: {
            if (expected.is_note != is_note) break :matches false;
            if (!std.mem.eql(u8, expected.msg, msg)) break :matches false;
            if (err.src_loc == .none) {
                break :matches expected.src == null;
            }
            const expected_src = expected.src orelse break :matches false;
            const src = eb.getSourceLocation(err.src_loc);
            const raw_filename = eb.nullTerminatedString(src.src_path);
            // We need to replace backslashes for consistency between platforms.
            const filename = name: {
                if (std.mem.indexOfScalar(u8, raw_filename, '\\') == null) break :name raw_filename;
                const copied = try eval.arena.dupe(u8, raw_filename);
                std.mem.replaceScalar(u8, copied, '\\', '/');
                break :name copied;
            };
            if (!std.mem.eql(u8, expected_src.filename, filename)) break :matches false;
            if (expected_src.line != src.line + 1) break :matches false;
            if (expected_src.column != src.column + 1) break :matches false;
            break :matches true;
        };
        if (!matches) {
            eb.renderToStderr(io, .{}, .auto) catch {};
            eval.fatal("compile error did not match expected error", .{});
        }
    }

    fn checkSuccessOutcome(eval: *Eval, update: Case.Update, opt_emitted_path: ?[]const u8, prog_node: std.Progress.Node) !void {
        switch (update.outcome) {
            .unknown => return,
            .compile_errors => eval.fatal("expected compile errors but compilation incorrectly succeeded", .{}),
            .stdout, .exit_code => {},
        }
        const emitted_path = opt_emitted_path orelse {
            std.debug.assert(eval.target.backend == .sema);
            return;
        };
        const io = eval.io;

        const binary_path = switch (eval.target.backend) {
            .sema => unreachable,
            .selfhosted, .llvm => emitted_path,
            .cbe => bin: {
                const rand_int = rand64(io);
                const out_bin_name = "./out_" ++ std.fmt.hex(rand_int);
                try eval.buildCOutput(emitted_path, out_bin_name, prog_node);
                break :bin out_bin_name;
            },
        };

        var argv_buf: [2][]const u8 = undefined;
        const argv: []const []const u8, const is_foreign: bool = sw: switch (std.zig.system.getExternalExecutor(
            io,
            &eval.host,
            &eval.target.resolved,
            .{ .link_libc = eval.target.backend == .cbe },
        )) {
            .bad_dl, .bad_os_or_cpu => {
                // This binary cannot be executed on this host.
                if (eval.allow_stderr) {
                    std.log.warn("skipping execution because host '{s}' cannot execute binaries for foreign target '{s}'", .{
                        try eval.host.zigTriple(eval.arena),
                        try eval.target.resolved.zigTriple(eval.arena),
                    });
                }
                return;
            },
            .native, .rosetta => argv: {
                argv_buf[0] = binary_path;
                break :argv .{ argv_buf[0..1], false };
            },
            .qemu => |executor_cmd| argv: {
                if (eval.enable_qemu) {
                    argv_buf[0] = executor_cmd;
                    argv_buf[1] = binary_path;
                    break :argv .{ argv_buf[0..2], true };
                } else {
                    continue :sw .bad_os_or_cpu;
                }
            },
            .wine => |executor_cmd| argv: {
                if (eval.enable_wine) {
                    argv_buf[0] = executor_cmd;
                    argv_buf[1] = binary_path;
                    break :argv .{ argv_buf[0..2], true };
                } else {
                    continue :sw .bad_os_or_cpu;
                }
            },
            .wasmtime => |executor_cmd| argv: {
                if (eval.enable_wasmtime) {
                    argv_buf[0] = executor_cmd;
                    argv_buf[1] = binary_path;
                    break :argv .{ argv_buf[0..2], true };
                } else {
                    continue :sw .bad_os_or_cpu;
                }
            },
            .darling => |executor_cmd| argv: {
                if (eval.enable_darling) {
                    argv_buf[0] = executor_cmd;
                    argv_buf[1] = binary_path;
                    break :argv .{ argv_buf[0..2], true };
                } else {
                    continue :sw .bad_os_or_cpu;
                }
            },
        };

        const run_prog_node = prog_node.start("run generated executable", 0);
        defer run_prog_node.end();

        const result = std.process.run(eval.arena, io, .{
            .argv = argv,
            .cwd = .{ .path = eval.tmp_dir_path },
        }) catch |err| {
            if (is_foreign) {
                // Chances are the foreign executor isn't available. Skip this evaluation.
                if (eval.allow_stderr) {
                    std.log.warn("skipping execution of '{s}' via executor for foreign target '{s}': {t}", .{
                        binary_path,
                        try eval.target.resolved.zigTriple(eval.arena),
                        err,
                    });
                }
                return;
            }
            eval.fatal("failed to run the generated executable '{s}': {t}", .{ binary_path, err });
        };

        // Some executors (looking at you, Wine) like throwing some stderr in, just for fun.
        // Therefore, we'll ignore stderr when using a foreign executor.
        if (!is_foreign and result.stderr.len != 0) {
            std.log.err("generated executable '{s}' had unexpected stderr:\n{s}", .{
                binary_path, result.stderr,
            });
        }

        switch (result.term) {
            .exited => |code| switch (update.outcome) {
                .unknown, .compile_errors => unreachable,
                .stdout => |expected_stdout| {
                    if (code != 0) {
                        eval.fatal("generated executable '{s}' failed with code {d}", .{ binary_path, code });
                    }
                    try std.testing.expectEqualStrings(expected_stdout, result.stdout);
                },
                .exit_code => |expected_code| try std.testing.expectEqual(expected_code, code),
            },
            .signal => |sig| {
                eval.fatal("generated executable '{s}' terminated with signal {t}", .{ binary_path, sig });
            },
            .stopped => |sig| {
                eval.fatal("generated executable '{s}' stopped with signal {t}", .{ binary_path, sig });
            },
            .unknown => {
                eval.fatal("generated executable '{s}' terminated unexpectedly", .{binary_path});
            },
        }

        if (!is_foreign and result.stderr.len != 0) std.process.exit(1);
    }

    fn requestUpdate(eval: *Eval) !void {
        const io = eval.io;
        const header: std.zig.Client.Message.Header = .{
            .tag = .update,
            .bytes_len = 0,
        };
        var w = eval.child.stdin.?.writer(io, &.{});
        w.interface.writeStruct(header, .little) catch |err| switch (err) {
            error.WriteFailed => return w.err.?,
        };
    }

    fn end(eval: *Eval, mr: *Io.File.MultiReader) !void {
        requestExit(eval.child, eval);

        const stdout = mr.fileReader(0);
        const Header = std.zig.Server.Message.Header;

        while (true) {
            const header = stdout.interface.takeStruct(Header, .little) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return stdout.err.?,
            };
            stdout.interface.discardAll(header.bytes_len) catch |err| switch (err) {
                error.ReadFailed => return stdout.err.?,
                error.EndOfStream => |e| return e,
            };
        }

        try mr.fillRemaining(.none);

        const stderr = mr.reader(1).buffered();
        if (stderr.len > 0) eval.fatal("unexpected stderr:\n{s}", .{stderr});
    }

    fn buildCOutput(eval: *Eval, c_path: []const u8, out_path: []const u8, prog_node: std.Progress.Node) !void {
        std.debug.assert(eval.cc_child_args.items.len > 0);

        const child_prog_node = prog_node.start("build cbe output", 0);
        defer child_prog_node.end();

        try eval.cc_child_args.appendSlice(eval.arena, &.{ out_path, c_path });
        defer eval.cc_child_args.items.len -= 2;

        const result = std.process.run(eval.arena, eval.io, .{
            .argv = eval.cc_child_args.items,
            .cwd = .{ .path = eval.tmp_dir_path },
            .progress_node = child_prog_node,
        }) catch |err| {
            eval.fatal("failed to spawn zig cc for '{s}': {t}", .{ c_path, err });
        };

        if (result.term == .exited and result.term.exited == 0) return;

        if (result.stderr.len != 0) {
            std.log.err("zig cc stderr:\n{s}", .{result.stderr});
        }
        switch (result.term) {
            .exited => |code| eval.fatal("zig cc for '{s}' failed with code {d}", .{ c_path, code }),
            .signal => |sig| eval.fatal("zig cc for '{s}' terminated unexpectedly with signal {t}", .{ c_path, sig }),
            .stopped => |sig| eval.fatal("zig cc for '{s}' stopped unexpectedly with signal {t}", .{ c_path, sig }),
            .unknown => eval.fatal("zig cc for '{s}' terminated unexpectedly", .{c_path}),
        }
    }

    fn fatal(eval: *Eval, comptime fmt: []const u8, args: anytype) noreturn {
        const io = eval.io;
        eval.tmp_dir.close(io);
        if (!eval.preserve_tmp_on_fatal) {
            // Kill the child since it holds an open handle to its CWD which is the tmp dir path
            eval.child.kill(io);
            Dir.cwd().deleteTree(io, eval.tmp_dir_path) catch |err| {
                std.log.warn("failed to delete tree '{s}': {t}", .{ eval.tmp_dir_path, err });
            };
        }
        std.process.fatal(fmt, args);
    }
};

const Case = struct {
    updates: []Update,
    root_source_file: []const u8,
    targets: []const Target,
    modules: []const Module,

    const Target = struct {
        query: []const u8,
        resolved: std.Target,
        backend: Backend,
        const Backend = enum {
            /// Run semantic analysis only. Runtime output will not be tested, but we still verify
            /// that compilation succeeds. Corresponds to `-fno-emit-bin`.
            sema,
            /// Use the self-hosted code generation backend for this target.
            /// Corresponds to `-fno-llvm -fno-lld`.
            selfhosted,
            /// Use the LLVM backend.
            /// Corresponds to `-fllvm -flld`.
            llvm,
            /// Use the C backend. The output is compiled with `zig cc`.
            /// Corresponds to `-ofmt=c`.
            cbe,
        };
    };

    const Module = struct {
        name: []const u8,
        file: []const u8,
    };

    const Update = struct {
        name: []const u8,
        outcome: Outcome,
        changes: []const FullContents = &.{},
        deletes: []const []const u8 = &.{},
    };

    const FullContents = struct {
        name: []const u8,
        bytes: []const u8,
    };

    const Outcome = union(enum) {
        unknown,
        compile_errors: struct {
            errors: []const ExpectedError,
            compile_log_output: []const u8,
        },
        stdout: []const u8,
        exit_code: u8,
    };

    const ExpectedError = struct {
        is_note: bool,
        msg: []const u8,
        src: ?struct {
            filename: []const u8,
            line: u32,
            column: u32,
        },
    };

    fn parse(arena: Allocator, io: Io, bytes: []const u8) !Case {
        const fatal = std.process.fatal;

        var targets: std.ArrayList(Target) = .empty;
        var modules: std.ArrayList(Module) = .empty;
        var updates: std.ArrayList(Update) = .empty;
        var changes: std.ArrayList(FullContents) = .empty;
        var deletes: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, bytes, '\n');
        var line_n: usize = 1;
        var root_source_file: ?[]const u8 = null;
        while (it.next()) |line| : (line_n += 1) {
            if (std.mem.startsWith(u8, line, "#")) {
                var line_it = std.mem.splitScalar(u8, line, '=');
                const key = line_it.first()[1..];
                const val = std.mem.trimEnd(u8, line_it.rest(), "\r"); // windows moment
                if (val.len == 0) {
                    fatal("line {d}: missing value", .{line_n});
                } else if (std.mem.eql(u8, key, "target")) {
                    const split_idx = std.mem.lastIndexOfScalar(u8, val, '-') orelse
                        fatal("line {d}: target does not include backend", .{line_n});

                    const query = val[0..split_idx];

                    const backend_str = val[split_idx + 1 ..];
                    const backend: Target.Backend = std.meta.stringToEnum(Target.Backend, backend_str) orelse
                        fatal("line {d}: invalid backend '{s}'", .{ line_n, backend_str });

                    const parsed_query = std.Build.parseTargetQuery(.{
                        .arch_os_abi = query,
                        .object_format = switch (backend) {
                            .sema, .selfhosted, .llvm => null,
                            .cbe => "c",
                        },
                    }) catch fatal("line {d}: invalid target query '{s}'", .{ line_n, query });

                    const resolved = try std.zig.system.resolveTargetQuery(io, parsed_query);

                    try targets.append(arena, .{
                        .query = query,
                        .resolved = resolved,
                        .backend = backend,
                    });
                } else if (std.mem.eql(u8, key, "module")) {
                    const split_idx = std.mem.indexOfScalar(u8, val, '=') orelse
                        fatal("line {d}: module does not include file", .{line_n});
                    const name = val[0..split_idx];
                    const file = val[split_idx + 1 ..];
                    try modules.append(arena, .{
                        .name = name,
                        .file = file,
                    });
                } else if (std.mem.eql(u8, key, "update")) {
                    if (updates.items.len > 0) {
                        const last_update = &updates.items[updates.items.len - 1];
                        last_update.changes = try changes.toOwnedSlice(arena);
                        last_update.deletes = try deletes.toOwnedSlice(arena);
                    }
                    try updates.append(arena, .{
                        .name = val,
                        .outcome = .unknown,
                    });
                } else if (std.mem.eql(u8, key, "file")) {
                    if (updates.items.len == 0) fatal("line {d}: file directive before update", .{line_n});

                    if (root_source_file == null)
                        root_source_file = val;

                    // Because Windows is so excellent, we need to convert CRLF to LF, so
                    // can't just slice into the input here. How delightful!
                    var src: std.ArrayList(u8) = .empty;

                    while (true) {
                        const next_line_raw = it.peek() orelse fatal("line {d}: unexpected EOF", .{line_n});
                        const next_line = std.mem.trimEnd(u8, next_line_raw, "\r");
                        if (std.mem.startsWith(u8, next_line, "#")) break;

                        _ = it.next();
                        line_n += 1;

                        try src.ensureUnusedCapacity(arena, next_line.len + 1);
                        src.appendSliceAssumeCapacity(next_line);
                        src.appendAssumeCapacity('\n');
                    }

                    try changes.append(arena, .{
                        .name = val,
                        .bytes = src.items,
                    });
                } else if (std.mem.eql(u8, key, "rm_file")) {
                    if (updates.items.len == 0) fatal("line {d}: rm_file directive before update", .{line_n});
                    try deletes.append(arena, val);
                } else if (std.mem.eql(u8, key, "expect_stdout")) {
                    if (updates.items.len == 0) fatal("line {d}: expect directive before update", .{line_n});
                    const last_update = &updates.items[updates.items.len - 1];
                    if (last_update.outcome != .unknown) fatal("line {d}: conflicting expect directive", .{line_n});
                    last_update.outcome = .{
                        .stdout = std.zig.string_literal.parseAlloc(arena, val) catch |err| {
                            fatal("line {d}: bad string literal: {t}", .{ line_n, err });
                        },
                    };
                } else if (std.mem.eql(u8, key, "expect_error")) {
                    if (updates.items.len == 0) fatal("line {d}: expect directive before update", .{line_n});
                    const last_update = &updates.items[updates.items.len - 1];
                    if (last_update.outcome != .unknown) fatal("line {d}: conflicting expect directive", .{line_n});

                    var errors: std.ArrayList(ExpectedError) = .empty;
                    try errors.append(arena, parseExpectedError(val, line_n));
                    while (true) {
                        const next_line = it.peek() orelse break;
                        if (!std.mem.startsWith(u8, next_line, "#")) break;
                        var new_line_it = std.mem.splitScalar(u8, next_line, '=');
                        const new_key = new_line_it.first()[1..];
                        const new_val = std.mem.trimEnd(u8, new_line_it.rest(), "\r");
                        if (new_val.len == 0) break;
                        if (!std.mem.eql(u8, new_key, "expect_error")) break;

                        _ = it.next();
                        line_n += 1;
                        try errors.append(arena, parseExpectedError(new_val, line_n));
                    }

                    var compile_log_output: std.ArrayList(u8) = .empty;
                    while (true) {
                        const next_line = it.peek() orelse break;
                        if (!std.mem.startsWith(u8, next_line, "#")) break;
                        var new_line_it = std.mem.splitScalar(u8, next_line, '=');
                        const new_key = new_line_it.first()[1..];
                        const new_val = std.mem.trimEnd(u8, new_line_it.rest(), "\r");
                        if (new_val.len == 0) break;
                        if (!std.mem.eql(u8, new_key, "expect_compile_log")) break;

                        _ = it.next();
                        line_n += 1;
                        try compile_log_output.ensureUnusedCapacity(arena, new_val.len + 1);
                        compile_log_output.appendSliceAssumeCapacity(new_val);
                        compile_log_output.appendAssumeCapacity('\n');
                    }

                    last_update.outcome = .{ .compile_errors = .{
                        .errors = errors.items,
                        .compile_log_output = compile_log_output.items,
                    } };
                } else if (std.mem.eql(u8, key, "expect_compile_log")) {
                    fatal("line {d}: 'expect_compile_log' must immediately follow 'expect_error'", .{line_n});
                } else {
                    fatal("line {d}: unrecognized key '{s}'", .{ line_n, key });
                }
            }
        }

        if (targets.items.len == 0) {
            fatal("missing target", .{});
        }

        if (changes.items.len > 0) {
            const last_update = &updates.items[updates.items.len - 1];
            last_update.changes = changes.items; // arena so no need for toOwnedSlice
            last_update.deletes = deletes.items;
        }

        return .{
            .updates = updates.items,
            .root_source_file = root_source_file orelse fatal("missing root source file", .{}),
            .targets = targets.items, // arena so no need for toOwnedSlice
            .modules = modules.items,
        };
    }
};

fn requestExit(child: *std.process.Child, eval: *Eval) void {
    if (child.stdin == null) return;
    const io = eval.io;

    const header: std.zig.Client.Message.Header = .{
        .tag = .exit,
        .bytes_len = 0,
    };
    var w = eval.child.stdin.?.writer(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => switch (w.err.?) {
            error.BrokenPipe => {},
            else => |e| eval.fatal("failed to send exit: {t}", .{e}),
        },
    };

    // Send EOF to stdin.
    child.stdin.?.close(io);
    child.stdin = null;
}

fn waitChild(child: *std.process.Child, eval: *Eval) void {
    const io = eval.io;
    requestExit(child, eval);
    const term = child.wait(io) catch |err| eval.fatal("child process failed: {t}", .{err});
    switch (term) {
        .exited => |code| if (code != 0) eval.fatal("compiler failed with code {d}", .{code}),
        .signal => |sig| eval.fatal("compiler terminated with signal {t}", .{sig}),
        .stopped => |sig| eval.fatal("compiler stopped unexpectedly with signal {t}", .{sig}),
        .unknown => eval.fatal("compiler terminated unexpectedly", .{}),
    }
}

fn parseExpectedError(str: []const u8, l: usize) Case.ExpectedError {
    // #expect_error=foo.zig:1:2: error: the error message
    // #expect_error=foo.zig:1:2: note: and a note

    const fatal = std.process.fatal;

    var it = std.mem.splitScalar(u8, str, ':');
    const filename = it.first();
    const line_str, const column_str = if (filename.len > 0) .{
        it.next() orelse fatal("line {d}: incomplete error specification", .{l}),
        it.next() orelse fatal("line {d}: incomplete error specification", .{l}),
    } else .{ undefined, undefined };
    const error_or_note_str = std.mem.trim(
        u8,
        it.next() orelse fatal("line {d}: incomplete error specification", .{l}),
        " ",
    );

    const is_note = if (std.mem.eql(u8, error_or_note_str, "error"))
        false
    else if (std.mem.eql(u8, error_or_note_str, "note"))
        true
    else
        fatal("line {d}: expeted 'error' or 'note', found '{s}'", .{ l, error_or_note_str });

    const message = std.mem.trim(u8, it.rest(), " ");
    if (message.len == 0) fatal("line {d}: empty error message", .{l});

    return .{
        .is_note = is_note,
        .msg = message,
        .src = if (filename.len == 0) null else .{
            .filename = filename,
            .line = std.fmt.parseInt(u32, line_str, 10) catch
                fatal("line {d}: invalid line number '{s}'", .{ l, line_str }),
            .column = std.fmt.parseInt(u32, column_str, 10) catch
                fatal("line {d}: invalid column number '{s}'", .{ l, column_str }),
        },
    };
}

fn rand64(io: Io) u64 {
    var x: u64 = undefined;
    io.random(@ptrCast(&x));
    return x;
}
