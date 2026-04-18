const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const fs = std.fs;
const mem = std.mem;

const TranslateC = @This();

pub const base_id: Step.Id = .translate_c;

step: Step,
source: std.Build.LazyPath,
include_dirs: std.array_list.Managed(std.Build.Module.IncludeDir),
system_libs: std.ArrayList(std.Build.Module.SystemLib),
c_macros: std.array_list.Managed([]const u8),
out_basename: []const u8,
target: std.Build.ResolvedTarget,
optimize: std.builtin.OptimizeMode,
output_file: std.Build.GeneratedFile,
link_libc: bool,

pub const Options = struct {
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_libc: bool = true,
};

pub fn create(owner: *std.Build, options: Options) *TranslateC {
    const translate_c = owner.allocator.create(TranslateC) catch @panic("OOM");
    const source = options.root_source_file.dupe(owner);
    translate_c.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "translate-c",
            .owner = owner,
            .makeFn = make,
        }),
        .source = source,
        .include_dirs = std.array_list.Managed(std.Build.Module.IncludeDir).init(owner.allocator),
        .c_macros = std.array_list.Managed([]const u8).init(owner.allocator),
        .out_basename = undefined,
        .target = options.target,
        .optimize = options.optimize,
        .output_file = .{ .step = &translate_c.step },
        .link_libc = options.link_libc,
        .system_libs = .empty,
    };
    source.addStepDependencies(&translate_c.step);
    return translate_c;
}

pub const AddExecutableOptions = struct {
    name: ?[]const u8 = null,
    version: ?std.SemanticVersion = null,
    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
    linkage: ?std.builtin.LinkMode = null,
};

pub fn getOutput(translate_c: *TranslateC) std.Build.LazyPath {
    return .{ .generated = .{ .file = &translate_c.output_file } };
}

/// Creates a module from the translated source and adds it to the package's
/// module set making it available to other packages which depend on this one.
/// `createModule` can be used instead to create a private module.
pub fn addModule(translate_c: *TranslateC, name: []const u8) *std.Build.Module {
    return setUpModule(translate_c, translate_c.step.owner.addModule(name, .{
        .root_source_file = translate_c.getOutput(),
        .target = translate_c.target,
        .optimize = translate_c.optimize,
        .link_libc = translate_c.link_libc,
    }));
}

/// Creates a private module from the translated source to be used by the
/// current package, but not exposed to other packages depending on this one.
/// `addModule` can be used instead to create a public module.
pub fn createModule(translate_c: *TranslateC) *std.Build.Module {
    return setUpModule(translate_c, translate_c.step.owner.createModule(.{
        .root_source_file = translate_c.getOutput(),
        .target = translate_c.target,
        .optimize = translate_c.optimize,
        .link_libc = translate_c.link_libc,
    }));
}

fn setUpModule(translate_c: *TranslateC, module: *std.Build.Module) *std.Build.Module {
    const b = translate_c.step.owner;
    const arena = b.graph.arena;

    if (translate_c.link_libc) module.link_libc = true;

    for (translate_c.system_libs.items) |system_lib| {
        module.link_objects.append(arena, .{ .system_lib = system_lib }) catch @panic("OOM");
    }

    return module;
}

pub fn addAfterIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const b = translate_c.step.owner;
    translate_c.include_dirs.append(.{ .path_after = lazy_path.dupe(b) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addSystemIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const b = translate_c.step.owner;
    translate_c.include_dirs.append(.{ .path_system = lazy_path.dupe(b) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const b = translate_c.step.owner;
    translate_c.include_dirs.append(.{ .path = lazy_path.dupe(b) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addConfigHeader(translate_c: *TranslateC, config_header: *Step.ConfigHeader) void {
    translate_c.include_dirs.append(.{ .config_header_step = config_header }) catch
        @panic("OOM");
    translate_c.step.dependOn(&config_header.step);
}

pub fn addSystemFrameworkPath(translate_c: *TranslateC, directory_path: LazyPath) void {
    const b = translate_c.step.owner;
    translate_c.include_dirs.append(.{ .framework_path_system = directory_path.dupe(b) }) catch
        @panic("OOM");
    directory_path.addStepDependencies(&translate_c.step);
}

pub fn addFrameworkPath(translate_c: *TranslateC, directory_path: LazyPath) void {
    const b = translate_c.step.owner;
    translate_c.include_dirs.append(.{ .framework_path = directory_path.dupe(b) }) catch
        @panic("OOM");
    directory_path.addStepDependencies(&translate_c.step);
}

pub fn addCheckFile(translate_c: *TranslateC, expected_matches: []const []const u8) *Step.CheckFile {
    return Step.CheckFile.create(
        translate_c.step.owner,
        translate_c.getOutput(),
        .{ .expected_matches = expected_matches },
    );
}

/// If the value is omitted, it is set to 1.
/// `name` and `value` need not live longer than the function call.
pub fn defineCMacro(translate_c: *TranslateC, name: []const u8, value: ?[]const u8) void {
    const macro = translate_c.step.owner.fmt("{s}={s}", .{ name, value orelse "1" });
    translate_c.c_macros.append(macro) catch @panic("OOM");
}

/// name_and_value looks like [name]=[value]. If the value is omitted, it is set to 1.
pub fn defineCMacroRaw(translate_c: *TranslateC, name_and_value: []const u8) void {
    translate_c.c_macros.append(translate_c.step.owner.dupe(name_and_value)) catch @panic("OOM");
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    const prog_node = options.progress_node;
    const b = step.owner;
    const translate_c: *TranslateC = @fieldParentPtr("step", step);
    const arena = b.graph.arena;

    var argv_list = std.array_list.Managed([]const u8).init(b.allocator);
    try argv_list.append(b.graph.zig_exe);
    try argv_list.append("translate-c");
    if (translate_c.link_libc) {
        try argv_list.append("-lc");
    }

    try argv_list.append("--cache-dir");
    try argv_list.append(b.cache_root.path orelse ".");

    try argv_list.append("--global-cache-dir");
    try argv_list.append(b.graph.global_cache_root.path orelse ".");

    if (!translate_c.target.query.isNative()) {
        try argv_list.append("-target");
        try argv_list.append(try translate_c.target.query.zigTriple(b.allocator));
    }

    switch (translate_c.optimize) {
        .Debug => {}, // Skip since it's the default.
        else => try argv_list.append(b.fmt("-O{s}", .{@tagName(translate_c.optimize)})),
    }

    for (translate_c.include_dirs.items) |include_dir| {
        try include_dir.appendZigProcessFlags(b, &argv_list, step);
    }

    for (translate_c.c_macros.items) |c_macro| {
        try argv_list.append("-D");
        try argv_list.append(c_macro);
    }

    var prev_search_strategy: std.Build.Module.SystemLib.SearchStrategy = .paths_first;
    var prev_preferred_link_mode: std.builtin.LinkMode = .dynamic;

    for (translate_c.system_libs.items) |*system_lib| {
        var seen_system_libs: std.StringHashMapUnmanaged([]const []const u8) = .empty;
        const system_lib_gop = try seen_system_libs.getOrPut(arena, system_lib.name);
        if (system_lib_gop.found_existing) {
            try argv_list.appendSlice(system_lib_gop.value_ptr.*);
            continue;
        } else {
            system_lib_gop.value_ptr.* = &.{};
        }

        if (system_lib.search_strategy != prev_search_strategy or
            system_lib.preferred_link_mode != prev_preferred_link_mode)
        {
            switch (system_lib.search_strategy) {
                .no_fallback => switch (system_lib.preferred_link_mode) {
                    .dynamic => try argv_list.append("-search_dylibs_only"),
                    .static => try argv_list.append("-search_static_only"),
                },
                .paths_first => switch (system_lib.preferred_link_mode) {
                    .dynamic => try argv_list.append("-search_paths_first"),
                    .static => try argv_list.append("-search_paths_first_static"),
                },
                .mode_first => switch (system_lib.preferred_link_mode) {
                    .dynamic => try argv_list.append("-search_dylibs_first"),
                    .static => try argv_list.append("-search_static_first"),
                },
            }
            prev_search_strategy = system_lib.search_strategy;
            prev_preferred_link_mode = system_lib.preferred_link_mode;
        }

        const prefix: []const u8 = prefix: {
            if (system_lib.needed) break :prefix "-needed-l";
            if (system_lib.weak) break :prefix "-weak-l";
            break :prefix "-l";
        };
        switch (system_lib.use_pkg_config) {
            .no => try argv_list.append(b.fmt("{s}{s}", .{ prefix, system_lib.name })),
            .yes, .force => {
                if (Step.Compile.runPkgConfig(&translate_c.step, system_lib.name)) |result| {
                    try argv_list.appendSlice(result.cflags);
                    try argv_list.appendSlice(result.libs);
                    try seen_system_libs.put(arena, system_lib.name, result.cflags);
                } else |err| switch (err) {
                    error.PkgConfigInvalidOutput,
                    error.PkgConfigCrashed,
                    error.PkgConfigFailed,
                    error.PkgConfigNotInstalled,
                    error.PackageNotFound,
                    => switch (system_lib.use_pkg_config) {
                        .yes => {
                            // pkg-config failed, so fall back to linking the library
                            // by name directly.
                            try argv_list.append(b.fmt("{s}{s}", .{
                                prefix,
                                system_lib.name,
                            }));
                        },
                        .force => {
                            std.debug.panic("pkg-config failed for library {s}", .{system_lib.name});
                        },
                        .no => unreachable,
                    },

                    else => |e| return e,
                }
            },
        }
    }

    const c_source_path = translate_c.source.getPath2(b, step);
    try argv_list.append(c_source_path);

    try argv_list.append("--listen=-");
    const output_dir = try step.evalZigProcess(argv_list.items, prog_node, false, options.web_server, options.gpa);

    const basename = std.fs.path.stem(std.fs.path.basename(c_source_path));
    translate_c.out_basename = b.fmt("{s}.zig", .{basename});
    translate_c.output_file.path = output_dir.?.joinString(b.allocator, translate_c.out_basename) catch @panic("OOM");
}

pub fn linkSystemLibrary(
    translate_c: *TranslateC,
    name: []const u8,
    options: std.Build.Module.LinkSystemLibraryOptions,
) void {
    const b = translate_c.step.owner;
    translate_c.system_libs.append(b.allocator, .{
        .name = b.dupe(name),
        .needed = options.needed,
        .weak = options.weak,
        .use_pkg_config = options.use_pkg_config,
        .preferred_link_mode = options.preferred_link_mode,
        .search_strategy = options.search_strategy,
    }) catch @panic("OOM");
}
