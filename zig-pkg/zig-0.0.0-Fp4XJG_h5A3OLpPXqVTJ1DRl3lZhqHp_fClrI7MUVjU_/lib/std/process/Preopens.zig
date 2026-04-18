const Preopens = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

map: Map,

pub const empty: Preopens = switch (native_os) {
    .wasi => .{ .map = .empty },
    else => .{ .map = {} },
};

pub const Map = switch (native_os) {
    // Indexed by file descriptor number.
    .wasi => std.StringArrayHashMapUnmanaged(void),
    else => void,
};

pub const Resource = union(enum) {
    file: Io.File,
    dir: Io.Dir,
};

pub fn get(p: *const Preopens, name: []const u8) ?Resource {
    switch (native_os) {
        .wasi => {
            const index = p.map.getIndex(name) orelse return null;
            if (index <= 2) return .{ .file = .{
                .handle = @intCast(index),
                .flags = .{ .nonblocking = false },
            } };
            return .{ .dir = .{ .handle = @intCast(index) } };
        },
        else => {
            if (std.mem.eql(u8, name, "stdin")) return .{ .file = .stdin() };
            if (std.mem.eql(u8, name, "stdout")) return .{ .file = .stdout() };
            if (std.mem.eql(u8, name, "stderr")) return .{ .file = .stderr() };
            return null;
        },
    }
}

pub const InitError = Allocator.Error || error{Unexpected};

pub fn init(arena: Allocator) InitError!Preopens {
    if (native_os != .wasi) return .{ .map = {} };
    const wasi = std.os.wasi;
    var map: Map = .empty;

    try map.ensureUnusedCapacity(arena, 3);

    map.putAssumeCapacityNoClobber("stdin", {}); // 0
    map.putAssumeCapacityNoClobber("stdout", {}); // 1
    map.putAssumeCapacityNoClobber("stderr", {}); // 2
    while (true) {
        const fd: wasi.fd_t = @intCast(map.entries.len);
        var prestat: wasi.prestat_t = undefined;
        switch (wasi.fd_prestat_get(fd, &prestat)) {
            .SUCCESS => {},
            .OPNOTSUPP, .BADF => return .{ .map = map },
            else => return error.Unexpected,
        }
        try map.ensureUnusedCapacity(arena, 1);
        // This length does not include a null byte. Let's keep it this way to
        // gently encourage WASI implementations to behave properly.
        const name_len = prestat.u.dir.pr_name_len;
        const name = try arena.alloc(u8, name_len);
        switch (wasi.fd_prestat_dir_name(fd, name.ptr, name.len)) {
            .SUCCESS => {},
            else => return error.Unexpected,
        }
        map.putAssumeCapacityNoClobber(name, {});
    }
}
