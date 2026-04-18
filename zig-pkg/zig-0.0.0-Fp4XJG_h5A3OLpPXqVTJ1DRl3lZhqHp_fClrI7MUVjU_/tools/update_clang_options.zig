//! To get started, run this tool with no args and read the help message.
//!
//! Clang has a file "options.td" which describes all of its command line parameter options.
//! When using `zig cc`, Zig acts as a proxy between the user and Clang. It does not need
//! to understand all the parameters, but it does need to understand some of them, such as
//! the target. This means that Zig must understand when a C command line parameter expects
//! to "consume" the next parameter on the command line.
//!
//! For example, `-z -target` would mean to pass `-target` to the linker, whereas `-E -target`
//! would mean that the next parameter specifies the target.

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const json = std.json;
const fatal = std.process.fatal;
const ClangCliParam = std.zig.ClangCliParam;

const KnownOpt = struct {
    name: []const u8,

    /// Corresponds to stage.zig ClangArgIterator.Kind
    ident: []const u8,
};

const known_options = [_]KnownOpt{
    .{
        .name = "target",
        .ident = "target",
    },
    .{
        .name = "o",
        .ident = "o",
    },
    .{
        .name = "c",
        .ident = "c",
    },
    .{
        .name = "r",
        .ident = "r",
    },
    .{
        .name = "l",
        .ident = "l",
    },
    .{
        .name = "pipe",
        .ident = "ignore",
    },
    .{
        .name = "help",
        .ident = "driver_punt",
    },
    .{
        .name = "fPIC",
        .ident = "pic",
    },
    .{
        .name = "fpic",
        .ident = "pic",
    },
    .{
        .name = "fno-PIC",
        .ident = "no_pic",
    },
    .{
        .name = "fno-pic",
        .ident = "no_pic",
    },
    .{
        .name = "fPIE",
        .ident = "pie",
    },
    .{
        .name = "fpie",
        .ident = "pie",
    },
    .{
        .name = "pie",
        .ident = "pie",
    },
    .{
        .name = "fno-PIE",
        .ident = "no_pie",
    },
    .{
        .name = "fno-pie",
        .ident = "no_pie",
    },
    .{
        .name = "no-pie",
        .ident = "no_pie",
    },
    .{
        .name = "nopie",
        .ident = "no_pie",
    },
    .{
        .name = "flto",
        .ident = "lto",
    },
    .{
        .name = "fno-lto",
        .ident = "no_lto",
    },
    .{
        .name = "funwind-tables",
        .ident = "unwind_tables",
    },
    .{
        .name = "fno-unwind-tables",
        .ident = "no_unwind_tables",
    },
    .{
        .name = "fasynchronous-unwind-tables",
        .ident = "asynchronous_unwind_tables",
    },
    .{
        .name = "fno-asynchronous-unwind-tables",
        .ident = "no_asynchronous_unwind_tables",
    },
    .{
        .name = "nolibc",
        .ident = "nostdlib",
    },
    .{
        .name = "nostdlib",
        .ident = "nostdlib",
    },
    .{
        .name = "no-standard-libraries",
        .ident = "nostdlib",
    },
    .{
        .name = "nostdlib++",
        .ident = "nostdlib_cpp",
    },
    .{
        .name = "nostdinc++",
        .ident = "nostdlib_cpp",
    },
    .{
        .name = "nostdlibinc",
        .ident = "nostdlibinc",
    },
    .{
        .name = "nostdinc",
        .ident = "nostdlibinc",
    },
    .{
        .name = "no-standard-includes",
        .ident = "nostdlibinc",
    },
    .{
        .name = "shared",
        .ident = "shared",
    },
    .{
        .name = "rdynamic",
        .ident = "rdynamic",
    },
    .{
        .name = "Wl,",
        .ident = "wl",
    },
    .{
        .name = "Wp,",
        .ident = "wp",
    },
    .{
        .name = "Xlinker",
        .ident = "for_linker",
    },
    .{
        .name = "for-linker",
        .ident = "for_linker",
    },
    .{
        .name = "for-linker=",
        .ident = "for_linker",
    },
    .{
        .name = "z",
        .ident = "linker_input_z",
    },
    .{
        .name = "E",
        .ident = "preprocess_only",
    },
    .{
        .name = "preprocess",
        .ident = "preprocess_only",
    },
    .{
        .name = "S",
        .ident = "asm_only",
    },
    .{
        .name = "assemble",
        .ident = "asm_only",
    },
    .{
        .name = "O0",
        .ident = "optimize",
    },
    .{
        .name = "O1",
        .ident = "optimize",
    },
    .{
        .name = "O2",
        .ident = "optimize",
    },
    // O3 is only detected from the joined "-O" option
    .{
        .name = "O4",
        .ident = "optimize",
    },
    .{
        .name = "Og",
        .ident = "optimize",
    },
    .{
        .name = "Os",
        .ident = "optimize",
    },
    // Oz is only detected from the joined "-O" option
    .{
        .name = "O",
        .ident = "optimize",
    },
    .{
        .name = "Ofast",
        .ident = "optimize",
    },
    .{
        .name = "optimize",
        .ident = "optimize",
    },
    .{
        .name = "g1",
        .ident = "debug",
    },
    .{
        .name = "gline-tables-only",
        .ident = "debug",
    },
    .{
        .name = "g",
        .ident = "debug",
    },
    .{
        .name = "debug",
        .ident = "debug",
    },
    .{
        .name = "gdwarf32",
        .ident = "gdwarf32",
    },
    .{
        .name = "gdwarf64",
        .ident = "gdwarf64",
    },
    .{
        .name = "gdwarf",
        .ident = "debug",
    },
    .{
        .name = "gdwarf-2",
        .ident = "debug",
    },
    .{
        .name = "gdwarf-3",
        .ident = "debug",
    },
    .{
        .name = "gdwarf-4",
        .ident = "debug",
    },
    .{
        .name = "gdwarf-5",
        .ident = "debug",
    },
    .{
        .name = "fsanitize",
        .ident = "sanitize",
    },
    .{
        .name = "fno-sanitize",
        .ident = "no_sanitize",
    },
    .{
        .name = "fsanitize-trap",
        .ident = "sanitize_trap",
    },
    .{
        .name = "fno-sanitize-trap",
        .ident = "no_sanitize_trap",
    },
    .{
        .name = "T",
        .ident = "linker_script",
    },
    .{
        .name = "###",
        .ident = "dry_run",
    },
    .{
        .name = "v",
        .ident = "verbose",
    },
    .{
        .name = "verbose",
        .ident = "verbose",
    },
    .{
        .name = "L",
        .ident = "lib_dir",
    },
    .{
        .name = "library-directory",
        .ident = "lib_dir",
    },
    .{
        .name = "mcpu",
        .ident = "mcpu",
    },
    .{
        .name = "march",
        .ident = "mcpu",
    },
    .{
        .name = "mtune",
        .ident = "mcpu",
    },
    .{
        .name = "mred-zone",
        .ident = "red_zone",
    },
    .{
        .name = "mno-red-zone",
        .ident = "no_red_zone",
    },
    .{
        .name = "fomit-frame-pointer",
        .ident = "omit_frame_pointer",
    },
    .{
        .name = "fno-omit-frame-pointer",
        .ident = "no_omit_frame_pointer",
    },
    .{
        .name = "ffunction-sections",
        .ident = "function_sections",
    },
    .{
        .name = "fno-function-sections",
        .ident = "no_function_sections",
    },
    .{
        .name = "fdata-sections",
        .ident = "data_sections",
    },
    .{
        .name = "fno-data-sections",
        .ident = "no_data_sections",
    },
    .{
        .name = "fbuiltin",
        .ident = "builtin",
    },
    .{
        .name = "fno-builtin",
        .ident = "no_builtin",
    },
    .{
        .name = "fcolor-diagnostics",
        .ident = "color_diagnostics",
    },
    .{
        .name = "fno-color-diagnostics",
        .ident = "no_color_diagnostics",
    },
    .{
        .name = "fcaret-diagnostics",
        .ident = "color_diagnostics",
    },
    .{
        .name = "fno-caret-diagnostics",
        .ident = "no_color_diagnostics",
    },
    .{
        .name = "fstack-check",
        .ident = "stack_check",
    },
    .{
        .name = "fno-stack-check",
        .ident = "no_stack_check",
    },
    .{
        .name = "stack-protector",
        .ident = "stack_protector",
    },
    .{
        .name = "fstack-protector",
        .ident = "stack_protector",
    },
    .{
        .name = "fno-stack-protector",
        .ident = "no_stack_protector",
    },
    .{
        .name = "fstack-protector-strong",
        .ident = "stack_protector",
    },
    .{
        .name = "fstack-protector-all",
        .ident = "stack_protector",
    },
    .{
        .name = "MD",
        .ident = "dep_file",
    },
    .{
        .name = "write-dependencies",
        .ident = "dep_file",
    },
    .{
        .name = "MV",
        .ident = "dep_file",
    },
    .{
        .name = "MF",
        .ident = "dep_file",
    },
    .{
        .name = "MT",
        .ident = "dep_file",
    },
    .{
        .name = "MG",
        .ident = "dep_file",
    },
    .{
        .name = "print-missing-file-dependencies",
        .ident = "dep_file",
    },
    .{
        .name = "MJ",
        .ident = "dep_file",
    },
    .{
        .name = "MM",
        .ident = "dep_file_to_stdout",
    },
    .{
        .name = "M",
        .ident = "dep_file_to_stdout",
    },
    .{
        .name = "user-dependencies",
        .ident = "dep_file_to_stdout",
    },
    .{
        .name = "MMD",
        .ident = "dep_file",
    },
    .{
        .name = "write-user-dependencies",
        .ident = "dep_file",
    },
    .{
        .name = "MP",
        .ident = "dep_file",
    },
    .{
        .name = "MQ",
        .ident = "dep_file",
    },
    .{
        .name = "F",
        .ident = "framework_dir",
    },
    .{
        .name = "framework",
        .ident = "framework",
    },
    .{
        .name = "s",
        .ident = "strip",
    },
    .{
        .name = "dynamiclib",
        .ident = "shared",
    },
    .{
        .name = "mexec-model",
        .ident = "exec_model",
    },
    .{
        .name = "emit-llvm",
        .ident = "emit_llvm",
    },
    .{
        .name = "sysroot",
        .ident = "sysroot",
    },
    .{
        .name = "entry",
        .ident = "entry",
    },
    .{
        .name = "e",
        .ident = "entry",
    },
    .{
        .name = "u",
        .ident = "force_undefined_symbol",
    },
    .{
        .name = "weak-l",
        .ident = "weak_library",
    },
    .{
        .name = "weak_library",
        .ident = "weak_library",
    },
    .{
        .name = "weak_framework",
        .ident = "weak_framework",
    },
    .{
        .name = "headerpad_max_install_names",
        .ident = "headerpad_max_install_names",
    },
    .{
        .name = "compress-debug-sections",
        .ident = "compress_debug_sections",
    },
    .{
        .name = "compress-debug-sections=",
        .ident = "compress_debug_sections",
    },
    .{
        .name = "install_name",
        .ident = "install_name",
    },
    .{
        .name = "undefined",
        .ident = "undefined",
    },
    .{
        .name = "x",
        .ident = "x",
    },
    .{
        .name = "ObjC",
        .ident = "force_load_objc",
    },
    .{
        .name = "municode",
        .ident = "mingw_unicode_entry_point",
    },
    .{
        .name = "fsanitize-coverage-trace-pc-guard",
        .ident = "san_cov_trace_pc_guard",
    },
    .{
        .name = "fsanitize-coverage",
        .ident = "san_cov",
    },
    .{
        .name = "fno-sanitize-coverage",
        .ident = "no_san_cov",
    },
    .{
        .name = "rtlib",
        .ident = "rtlib",
    },
    .{
        .name = "rtlib=",
        .ident = "rtlib",
    },
    .{
        .name = "static",
        .ident = "static",
    },
    .{
        .name = "dynamic",
        .ident = "dynamic",
    },
    .{
        .name = "version",
        .ident = "version",
    },
};

const blacklisted_options = [_][]const u8{};

fn knownOption(name: []const u8) ?[]const u8 {
    const chopped_name = if (std.mem.indexOfScalar(u8, name, '=')) |idx| name[0..idx] else name;
    for (known_options) |item| {
        if (std.mem.eql(u8, chopped_name, item.name)) {
            return item.ident;
        }
    }
    return null;
}

const cpu_targets = struct {
    pub const aarch64 = std.Target.aarch64;
    pub const amdgcn = std.Target.amdgcn;
    pub const arc = std.Target.arc;
    pub const arm = std.Target.arm;
    pub const avr = std.Target.avr;
    pub const bpf = std.Target.bpf;
    pub const csky = std.Target.csky;
    pub const hexagon = std.Target.hexagon;
    pub const loongarch = std.Target.loongarch;
    pub const m68k = std.Target.m68k;
    pub const mips = std.Target.mips;
    pub const msp430 = std.Target.msp430;
    pub const nvptx = std.Target.nvptx;
    pub const powerpc = std.Target.powerpc;
    pub const riscv = std.Target.riscv;
    pub const s390x = std.Target.s390x;
    pub const sparc = std.Target.sparc;
    pub const spirv = std.Target.spirv;
    pub const ve = std.Target.ve;
    pub const wasm = std.Target.wasm;
    pub const x86 = std.Target.x86;
    pub const xtensa = std.Target.xtensa;
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [4000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len <= 1) printUsageAndExit(args[0]);

    if (std.mem.eql(u8, args[1], "--help")) {
        printUsage(stdout, args[0]) catch std.process.exit(2);
        stdout.flush() catch std.process.exit(2);
        std.process.exit(0);
    }

    if (args.len < 3) printUsageAndExit(args[0]);

    const llvm_tblgen_exe = args[1];
    if (std.mem.startsWith(u8, llvm_tblgen_exe, "-")) printUsageAndExit(args[0]);

    const llvm_src_root = args[2];
    if (std.mem.startsWith(u8, llvm_src_root, "-")) printUsageAndExit(args[0]);

    var llvm_to_zig_cpu_features = std.StringHashMap([]const u8).init(arena);

    inline for (@typeInfo(cpu_targets).@"struct".decls) |decl| {
        const Feature = @field(cpu_targets, decl.name).Feature;
        const all_features = @field(cpu_targets, decl.name).all_features;

        for (all_features, 0..) |feat, i| {
            const llvm_name = feat.llvm_name orelse continue;
            const zig_feat = @as(Feature, @enumFromInt(i));
            const zig_name = @tagName(zig_feat);
            try llvm_to_zig_cpu_features.put(llvm_name, zig_name);
        }
    }

    const child_args = [_][]const u8{
        llvm_tblgen_exe,
        "--dump-json",
        try std.fmt.allocPrint(arena, "{s}/clang/include/clang/Driver/Options.td", .{llvm_src_root}),
        try std.fmt.allocPrint(arena, "-I={s}/llvm/include", .{llvm_src_root}),
        try std.fmt.allocPrint(arena, "-I={s}/clang/include/clang/Driver", .{llvm_src_root}),
    };

    const child_result = try std.process.run(arena, io, .{
        .argv = &child_args,
    });

    std.debug.print("{s}\n", .{child_result.stderr});

    const json_text = switch (child_result.term) {
        .exited => |code| if (code == 0) child_result.stdout else {
            fatal("llvm-tblgen exited with code {d}\n", .{code});
        },
        .signal => |sig| {
            fatal("llvm-tblgen terminated with signal {t}\n", .{sig});
        },
        .stopped => |sig| {
            fatal("llvm-tblgen stopped with signal {d}\n", .{sig});
        },
        .unknown => {
            fatal("llvm-tblgen crashed\n", .{});
        },
    };

    const parsed = try json.parseFromSlice(json.Value, arena, json_text, .{});
    defer parsed.deinit();
    const root_map = &parsed.value.object;

    var all_objects = std.array_list.Managed(*json.ObjectMap).init(arena);
    {
        var it = root_map.iterator();
        it_map: while (it.next()) |kv| {
            if (kv.key_ptr.len == 0) continue;
            if (kv.key_ptr.*[0] == '!') continue;
            if (kv.value_ptr.* != .object) continue;
            if (!kv.value_ptr.object.contains("NumArgs")) continue;
            if (!kv.value_ptr.object.contains("Name")) continue;
            for (blacklisted_options) |blacklisted_key| {
                if (std.mem.eql(u8, blacklisted_key, kv.key_ptr.*)) continue :it_map;
            }
            if (kv.value_ptr.object.get("Name").?.string.len == 0) continue;
            try all_objects.append(&kv.value_ptr.object);
        }
    }
    // Some options have multiple matches. As an example, "-Wl,foo" matches both
    // "W" and "Wl,". So we sort this list in order of descending priority.
    std.mem.sort(*json.ObjectMap, all_objects.items, {}, objectLessThan);

    try stdout.writeAll(
        \\// This file is generated by tools/update_clang_options.zig.
        \\// zig fmt: off
        \\
    );

    var serializer: std.zon.Serializer = .{ .writer = stdout };
    var top = try serializer.beginTuple(.{});
    serializer.indent_level = 0;

    for (all_objects.items) |obj| {
        const name = obj.get("Name").?.string;
        var pd1 = false;
        var pd2 = false;
        var pslash = false;
        for (obj.get("Prefixes").?.array.items) |prefix_json| {
            const prefix = prefix_json.string;
            if (std.mem.eql(u8, prefix, "-")) {
                pd1 = true;
            } else if (std.mem.eql(u8, prefix, "--")) {
                pd2 = true;
            } else if (std.mem.eql(u8, prefix, "/")) {
                pslash = true;
            } else {
                fatal("{s} has unrecognized prefix '{s}'", .{ name, prefix });
            }
        }
        const syntax = objSyntax(obj) orelse continue;

        var element: ClangCliParam = .{
            .name = name,
            .syntax = syntax,
            .pd1 = pd1,
            .pd2 = pd2,
            .psl = pslash,
        };

        if (std.mem.eql(u8, name, "MT") and syntax == .flag) {
            // `-MT foo` is ambiguous because there is also an -MT flag
            // The canonical way to specify the flag is with `/MT` and so we make this
            // the only way.
            element.psl = true;
            element.pd1 = false;
            element.pd2 = false;
        } else if (knownOption(name)) |ident| {
            // Workaround the fact that in 'Options.td'  -Ofast is listed as 'joined'
            if (std.mem.eql(u8, name, "Ofast")) element.syntax = .flag;
            element.ze = std.meta.stringToEnum(ClangCliParam.ZigEquivalent, ident) orelse fatal("unknown known option: {s}", .{ident});
        } else if (pd1 and !pd2 and !pslash and syntax == .flag) {
            if ((std.mem.startsWith(u8, name, "mno-") and
                llvm_to_zig_cpu_features.contains(name["mno-".len..])) or
                (std.mem.startsWith(u8, name, "m") and
                    llvm_to_zig_cpu_features.contains(name["m".len..])))
            {
                element.ze = .m;
            }
        }
        try top.field(element, .{ .emit_default_optional_fields = false });
    }

    try top.end();

    try stdout.flush();
}

fn objSyntax(obj: *json.ObjectMap) ?ClangCliParam.Syntax {
    const num_args = @as(u8, @intCast(obj.get("NumArgs").?.integer));
    for (obj.get("!superclasses").?.array.items) |superclass_json| {
        const superclass = superclass_json.string;
        if (std.mem.eql(u8, superclass, "Joined")) {
            return .joined;
        } else if (std.mem.eql(u8, superclass, "CLJoined")) {
            return .joined;
        } else if (std.mem.eql(u8, superclass, "CLIgnoredJoined")) {
            return .joined;
        } else if (std.mem.eql(u8, superclass, "CLCompileJoined")) {
            return .joined;
        } else if (std.mem.eql(u8, superclass, "CLDXCJoined")) {
            return .joined;
        } else if (std.mem.eql(u8, superclass, "JoinedOrSeparate")) {
            return .joined_or_separate;
        } else if (std.mem.eql(u8, superclass, "CLJoinedOrSeparate")) {
            return .joined_or_separate;
        } else if (std.mem.eql(u8, superclass, "CLCompileJoinedOrSeparate")) {
            return .joined_or_separate;
        } else if (std.mem.eql(u8, superclass, "DXCJoinedOrSeparate")) {
            return .joined_or_separate;
        } else if (std.mem.eql(u8, superclass, "CLDXCJoinedOrSeparate")) {
            return .joined_or_separate;
        } else if (std.mem.eql(u8, superclass, "Flag")) {
            return .flag;
        } else if (std.mem.eql(u8, superclass, "CLFlag")) {
            return .flag;
        } else if (std.mem.eql(u8, superclass, "CLIgnoredFlag")) {
            return .flag;
        } else if (std.mem.eql(u8, superclass, "Separate")) {
            return .separate;
        } else if (std.mem.eql(u8, superclass, "JoinedAndSeparate")) {
            return .joined_and_separate;
        } else if (std.mem.eql(u8, superclass, "CommaJoined")) {
            return .comma_joined;
        } else if (std.mem.eql(u8, superclass, "CLRemainingArgsJoined")) {
            return .remaining_args_joined;
        } else if (std.mem.eql(u8, superclass, "MultiArg")) {
            return .{ .multi_arg = num_args };
        }
    }
    const name = obj.get("Name").?.string;
    if (std.mem.eql(u8, name, "<input>")) {
        return .flag;
    } else if (std.mem.eql(u8, name, "<unknown>")) {
        return .flag;
    }
    const kind_def = obj.get("Kind").?.object.get("def").?.string;
    if (std.mem.eql(u8, kind_def, "KIND_FLAG")) {
        return .flag;
    }
    const key = obj.get("!name").?.string;
    std.debug.print("{s} (key {s}) has unrecognized superclasses:\n", .{ name, key });
    for (obj.get("!superclasses").?.array.items) |superclass_json| {
        std.debug.print(" {s}\n", .{superclass_json.string});
    }
    //std.process.exit(1);
    return null;
}

fn syntaxMatchesWithEql(syntax: ClangCliParam.Syntax) bool {
    return switch (syntax) {
        .flag,
        .separate,
        .multi_arg,
        => true,

        .joined,
        .joined_or_separate,
        .joined_and_separate,
        .comma_joined,
        .remaining_args_joined,
        => false,
    };
}

fn objectLessThan(context: void, a: *json.ObjectMap, b: *json.ObjectMap) bool {
    _ = context;
    // Priority is determined by exact matches first, followed by prefix matches in descending
    // length, with key as a final tiebreaker.
    const a_syntax = objSyntax(a) orelse return false;
    const b_syntax = objSyntax(b) orelse return true;

    const a_match_with_eql = syntaxMatchesWithEql(a_syntax);
    const b_match_with_eql = syntaxMatchesWithEql(b_syntax);

    if (a_match_with_eql and !b_match_with_eql) {
        return true;
    } else if (!a_match_with_eql and b_match_with_eql) {
        return false;
    }

    if (!a_match_with_eql and !b_match_with_eql) {
        const a_name = a.get("Name").?.string;
        const b_name = b.get("Name").?.string;
        if (a_name.len != b_name.len) {
            return a_name.len > b_name.len;
        }
    }

    const a_key = a.get("!name").?.string;
    const b_key = b.get("!name").?.string;
    return std.mem.lessThan(u8, a_key, b_key);
}

fn printUsageAndExit(arg0: []const u8) noreturn {
    const stderr = std.debug.lockStderr(&.{});
    const w = &stderr.file_writer.interface;
    printUsage(w, arg0) catch std.process.exit(2);
    std.process.exit(1);
}

fn printUsage(w: *std.Io.Writer, arg0: []const u8) std.Io.Writer.Error!void {
    try w.print(
        \\Usage: {s} /path/to/llvm-tblgen /path/to/git/llvm/llvm-project
        \\
        \\Prints to stdout Zig code which you can use to replace the file src/clang_options.zon.
        \\
    , .{arg0});
}
