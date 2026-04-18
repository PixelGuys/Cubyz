const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const EnvVar = std.zig.EnvVar;
const fatal = std.process.fatal;

const build_options = @import("build_options");
const Compilation = @import("Compilation.zig");

pub fn cmdEnv(
    arena: Allocator,
    io: Io,
    out: *std.Io.Writer,
    args: []const []const u8,
    preopens: std.process.Preopens,
    host: *const std.Target,
    environ_map: *std.process.Environ.Map,
) !void {
    const override_lib_dir: ?[]const u8 = EnvVar.ZIG_LIB_DIR.get(environ_map);
    const override_global_cache_dir: ?[]const u8 = EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map);

    const self_exe_path = switch (builtin.target.os.tag) {
        .wasi => args[0],
        else => std.process.executablePathAlloc(io, arena) catch |err| {
            fatal("unable to find zig self exe path: {t}", .{err});
        },
    };

    var dirs: Compilation.Directories = .init(
        arena,
        io,
        override_lib_dir,
        override_global_cache_dir,
        .global,
        preopens,
        if (builtin.target.os.tag != .wasi) self_exe_path,
        environ_map,
    );
    defer dirs.deinit(io);

    const zig_lib_dir = dirs.zig_lib.path orelse "";
    const zig_std_dir = try dirs.zig_lib.join(arena, &.{"std"});
    const global_cache_dir = dirs.global_cache.path orelse "";
    const triple = try host.zigTriple(arena);

    var serializer: std.zon.Serializer = .{ .writer = out };
    var root = try serializer.beginStruct(.{});

    try root.field("zig_exe", self_exe_path, .{});
    try root.field("lib_dir", zig_lib_dir, .{});
    try root.field("std_dir", zig_std_dir, .{});
    try root.field("global_cache_dir", global_cache_dir, .{});
    try root.field("version", build_options.version, .{});
    try root.field("target", triple, .{});
    var env = try root.beginStructField("env", .{});
    inline for (@typeInfo(EnvVar).@"enum".fields) |field| {
        try env.field(field.name, @field(EnvVar, field.name).get(environ_map), .{});
    }
    try env.end();
    try root.end();

    try out.writeByte('\n');
}
