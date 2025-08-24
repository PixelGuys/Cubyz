const std = @import("std");
const main = @import("main");

pub fn moveFolder(src: std.fs.Dir, dst: std.fs.Dir) !void {
    var walker = try src.walk(main.stackAllocator.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try entry.dir.copyFile(entry.basename, dst, entry.path, .{});
            },
            .directory => {
                try dst.makeDir(entry.path);
            },
            else => return error.UnexpectedEntryKind,
        }
    }
}

pub fn moveSaves() bool {
    {
        var oldDir = std.fs.cwd().openDir("saves", .{.iterate = true}) catch {
            return false;
        };
        defer oldDir.close();

        var newDir = main.files.cubyzDir().dir.makeOpenPath("saves", .{}) catch |err| {
            std.log.err("Encountered error while opening new saves directory: {s}", .{@errorName(err)});
            return false;
        };
        defer newDir.close();
        
        moveFolder(oldDir, newDir) catch |err| {
            std.log.err("Encountered error while moving saves: {s}", .{@errorName(err)});
            return false;
        };
    }
    std.fs.cwd().deleteTree("saves") catch |err| {
        std.log.err("Encountered error while deleting old saves folder: {s}", .{@errorName(err)});
    };
    return true;
}