//! This script updates the .c, .h, .s, and .S files that make up the start
//! files such as crt1.o. Not to be confused with
//! https://codeberg.org/ziglang/libc-abi-tools which updates the `abilists`
//! file.
//!
//! Example usage:
//! `zig run ../tools/update_glibc.zig -- ~/Downloads/glibc ..`

const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const mem = std.mem;
const log = std.log;
const fatal = std.process.fatal;

const exempt_files = [_][]const u8{
    // This file is maintained by a separate project and does not come from glibc.
    "abilists",

    // Generated files.
    "include/libc-modules.h",
    "include/config.h",

    // These are easier to maintain like this, without updating to the abi-note.c
    // that glibc did upstream.
    "csu/abi-tag.h",
    "csu/abi-note.S",

    // We have patched these files to require fewer includes.
    "stdlib/at_quick_exit.c",
    "stdlib/atexit.c",
    "sysdeps/pthread/pthread_atfork.c",
};

const exempt_extensions = [_][]const u8{
    // These are the start files we use when targeting glibc <= 2.33.
    "-2.33.S",
    "-2.33.c",
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const glibc_src_path = args[1];
    const zig_src_path = args[2];

    const dest_dir_path = try std.fmt.allocPrint(arena, "{s}/lib/libc/glibc", .{zig_src_path});

    var dest_dir = Dir.cwd().openDir(io, dest_dir_path, .{ .iterate = true }) catch |err| {
        fatal("unable to open destination directory '{s}': {t}", .{ dest_dir_path, err });
    };
    defer dest_dir.close(io);

    var glibc_src_dir = try Dir.cwd().openDir(io, glibc_src_path, .{});
    defer glibc_src_dir.close(io);

    // Copy updated files from upstream.
    {
        var walker = try dest_dir.walk(arena);
        defer walker.deinit();

        walk: while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (mem.startsWith(u8, entry.basename, ".")) continue;
            for (exempt_files) |p| {
                if (mem.eql(u8, entry.path, p)) continue :walk;
            }
            for (exempt_extensions) |ext| {
                if (mem.endsWith(u8, entry.path, ext)) continue :walk;
            }

            glibc_src_dir.copyFile(entry.path, dest_dir, entry.path, io, .{}) catch |err| {
                log.warn("unable to copy '{s}/{s}' to '{s}/{s}': {t}", .{
                    glibc_src_path, entry.path, dest_dir_path, entry.path, err,
                });
                if (err == error.FileNotFound) {
                    try dest_dir.deleteFile(io, entry.path);
                }
            };
        }
    }

    // Warn about duplicated files inside glibc/include/* that can be omitted
    // because they are already in generic-glibc/*.

    var include_dir = dest_dir.openDir(io, "include", .{ .iterate = true }) catch |err| {
        fatal("unable to open directory '{s}/include': {t}", .{ dest_dir_path, err });
    };
    defer include_dir.close(io);

    const generic_glibc_path = try std.fmt.allocPrint(
        arena,
        "{s}/lib/libc/include/generic-glibc",
        .{zig_src_path},
    );
    var generic_glibc_dir = try Dir.cwd().openDir(io, generic_glibc_path, .{});
    defer generic_glibc_dir.close(io);

    var walker = try include_dir.walk(arena);
    defer walker.deinit();

    walk: while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (mem.startsWith(u8, entry.basename, ".")) continue;
        for (exempt_files) |p| {
            if (mem.eql(u8, entry.path, p)) continue :walk;
        }

        const max_file_size = 10 * 1024 * 1024;

        const generic_glibc_contents = generic_glibc_dir.readFileAlloc(
            io,
            entry.path,
            arena,
            .limited(max_file_size),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| fatal("unable to load '{s}/include/{s}': {t}", .{ generic_glibc_path, entry.path, e }),
        };
        const glibc_include_contents = include_dir.readFileAlloc(
            io,
            entry.path,
            arena,
            .limited(max_file_size),
        ) catch |err| {
            fatal("unable to load '{s}/include/{s}': {t}", .{ dest_dir_path, entry.path, err });
        };

        const whitespace = " \r\n\t";
        const generic_glibc_trimmed = mem.trim(u8, generic_glibc_contents, whitespace);
        const glibc_include_trimmed = mem.trim(u8, glibc_include_contents, whitespace);
        if (mem.eql(u8, generic_glibc_trimmed, glibc_include_trimmed)) {
            log.warn("same contents: '{s}/include/{s}' and '{s}/include/{s}'", .{
                generic_glibc_path, entry.path, dest_dir_path, entry.path,
            });
        }
    }
}
