const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const assert = std.debug.assert;

const build_options = @import("build_options");

const Compilation = @import("Compilation.zig");
const Package = @import("Package.zig");

/// Returns the sub_path that worked, or `null` if none did.
/// The path of the returned Directory is relative to `base`.
/// The handle of the returned Directory is open.
fn testZigInstallPrefix(io: Io, base_dir: Io.Dir) ?Cache.Directory {
    const test_index_file = "std" ++ Dir.path.sep_str ++ "std.zig";

    zig_dir: {
        // Try lib/zig/std/std.zig
        const lib_zig = "lib" ++ Dir.path.sep_str ++ "zig";
        var test_zig_dir = base_dir.openDir(io, lib_zig, .{}) catch break :zig_dir;
        const file = test_zig_dir.openFile(io, test_index_file, .{}) catch {
            test_zig_dir.close(io);
            break :zig_dir;
        };
        file.close(io);
        return .{ .handle = test_zig_dir, .path = lib_zig };
    }

    // Try lib/std/std.zig
    var test_zig_dir = base_dir.openDir(io, "lib", .{}) catch return null;
    const file = test_zig_dir.openFile(io, test_index_file, .{}) catch {
        test_zig_dir.close(io);
        return null;
    };
    file.close(io);
    return .{ .handle = test_zig_dir, .path = "lib" };
}

/// Both the directory handle and the path are newly allocated resources which the caller now owns.
pub fn findZigLibDir(gpa: Allocator, io: Io) !Cache.Directory {
    const cwd_path = try getResolvedCwd(io, gpa);
    defer gpa.free(cwd_path);
    const self_exe_path = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(self_exe_path);

    return findZigLibDirFromSelfExe(gpa, io, cwd_path, self_exe_path);
}

/// Like `std.process.currentPathAlloc`, but also resolves the path with `Dir.path.resolve`. This
/// means the path has no repeated separators, no "." or ".." components, and no trailing separator.
/// On WASI, "" is returned instead of ".".
pub fn getResolvedCwd(io: Io, gpa: Allocator) std.process.CurrentPathAllocError![]u8 {
    if (builtin.target.os.tag == .wasi) {
        if (std.debug.runtime_safety) {
            const cwd = try std.process.currentPathAlloc(io, gpa);
            defer gpa.free(cwd);
            assert(mem.eql(u8, cwd, "."));
        }
        return "";
    }
    const cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd);
    const resolved = try Dir.path.resolve(gpa, &.{cwd});
    assert(Dir.path.isAbsolute(resolved));
    return resolved;
}

/// Both the directory handle and the path are newly allocated resources which the caller now owns.
pub fn findZigLibDirFromSelfExe(
    allocator: Allocator,
    io: Io,
    /// The return value of `getResolvedCwd`.
    /// Passed as an argument to avoid pointlessly repeating the call.
    cwd_path: []const u8,
    self_exe_path: []const u8,
) error{ OutOfMemory, FileNotFound }!Cache.Directory {
    const cwd = Io.Dir.cwd();
    var cur_path: []const u8 = self_exe_path;
    while (Dir.path.dirname(cur_path)) |dirname| : (cur_path = dirname) {
        var base_dir = cwd.openDir(io, dirname, .{}) catch continue;
        defer base_dir.close(io);

        const sub_directory = testZigInstallPrefix(io, base_dir) orelse continue;
        const p = try Dir.path.join(allocator, &.{ dirname, sub_directory.path.? });
        defer allocator.free(p);

        const resolved = try resolvePath(allocator, cwd_path, &.{p});
        return .{
            .handle = sub_directory.handle,
            .path = if (resolved.len == 0) null else resolved,
        };
    }
    return error.FileNotFound;
}

pub fn resolveGlobalCacheDir(arena: Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    if (std.zig.EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map)) |value| return value;

    const app_name = "zig";

    switch (builtin.os.tag) {
        .wasi => @compileError("on WASI the global cache dir must be resolved with preopens"),
        .windows => {
            const local_app_data_dir = std.zig.EnvVar.LOCALAPPDATA.get(environ_map) orelse
                return error.AppDataDirUnavailable;
            return Dir.path.join(arena, &.{ local_app_data_dir, app_name });
        },
        else => {
            if (std.zig.EnvVar.XDG_CACHE_HOME.get(environ_map)) |cache_root| {
                if (cache_root.len > 0) {
                    return Dir.path.join(arena, &.{ cache_root, app_name });
                }
            }
            if (std.zig.EnvVar.HOME.get(environ_map)) |home| {
                if (home.len > 0) {
                    return Dir.path.join(arena, &.{ home, ".cache", app_name });
                }
            }
            return error.AppDataDirUnavailable;
        },
    }
}

/// Similar to `Dir.path.resolve`, but converts to a cwd-relative path, or, if that would
/// start with a relative up-dir (".."), an absolute path based on the cwd. Also, the cwd
/// returns the empty string ("") instead of ".".
pub fn resolvePath(
    gpa: Allocator,
    /// The return value of `getResolvedCwd`.
    /// Passed as an argument to avoid pointlessly repeating the call.
    cwd_resolved: []const u8,
    paths: []const []const u8,
) Allocator.Error![]u8 {
    if (builtin.target.os.tag == .wasi) {
        assert(mem.eql(u8, cwd_resolved, ""));
        const res = try Dir.path.resolve(gpa, paths);
        if (mem.eql(u8, res, ".")) {
            gpa.free(res);
            return "";
        }
        return res;
    }

    // Heuristic for a fast path: if no component is absolute and ".." never appears, we just need to resolve `paths`.
    for (paths) |p| {
        if (Dir.path.isAbsolute(p)) break; // absolute path
        if (mem.indexOf(u8, p, "..") != null) break; // may contain up-dir
    } else {
        // no absolute path, no "..".
        const res = try Dir.path.resolve(gpa, paths);
        if (mem.eql(u8, res, ".")) {
            gpa.free(res);
            return "";
        }
        assert(!Dir.path.isAbsolute(res));
        assert(!isUpDir(res));
        return res;
    }

    // The fast path failed; resolve the whole thing.
    // Optimization: `paths` often has just one element.
    const path_resolved = switch (paths.len) {
        0 => unreachable,
        1 => try Dir.path.resolve(gpa, &.{ cwd_resolved, paths[0] }),
        else => r: {
            const all_paths = try gpa.alloc([]const u8, paths.len + 1);
            defer gpa.free(all_paths);
            all_paths[0] = cwd_resolved;
            @memcpy(all_paths[1..], paths);
            break :r try Dir.path.resolve(gpa, all_paths);
        },
    };
    errdefer gpa.free(path_resolved);

    assert(Dir.path.isAbsolute(path_resolved));
    assert(Dir.path.isAbsolute(cwd_resolved));

    if (!std.mem.startsWith(u8, path_resolved, cwd_resolved)) return path_resolved; // not in cwd
    if (path_resolved.len == cwd_resolved.len) {
        // equal to cwd
        gpa.free(path_resolved);
        return "";
    }
    if (path_resolved[cwd_resolved.len] != Dir.path.sep) return path_resolved; // not in cwd (last component differs)

    // in cwd; extract sub path
    const sub_path = try gpa.dupe(u8, path_resolved[cwd_resolved.len + 1 ..]);
    gpa.free(path_resolved);
    return sub_path;
}

pub fn isUpDir(p: []const u8) bool {
    return mem.startsWith(u8, p, "..") and (p.len == 2 or p[2] == Dir.path.sep);
}

pub const default_local_zig_cache_basename = ".zig-cache";

/// Searches upwards from `cwd` for a directory containing a `build.zig` file.
/// If such a directory is found, returns the path to it joined to the `.zig_cache` name.
/// Otherwise, returns `null`, indicating no suitable local cache location.
pub fn resolveSuitableLocalCacheDir(arena: Allocator, io: Io, cwd: []const u8) Allocator.Error!?[]u8 {
    var cur_dir = cwd;
    while (true) {
        const joined = try Dir.path.join(arena, &.{ cur_dir, Package.build_zig_basename });
        if (Io.Dir.cwd().access(io, joined, .{})) |_| {
            return try Dir.path.join(arena, &.{ cur_dir, default_local_zig_cache_basename });
        } else |err| switch (err) {
            error.FileNotFound => {
                cur_dir = Dir.path.dirname(cur_dir) orelse return null;
                continue;
            },
            else => return null,
        }
    }
}
