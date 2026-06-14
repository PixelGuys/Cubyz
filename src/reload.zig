const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const ZonElement = main.ZonElement;
const Window = @import("graphics/Window.zig");

pub const version = @import("utils/version.zig");

pub var worldName: []const u8 = &.{};

pub fn init() void {}
pub fn deinit() void {
	main.globalAllocator.free(worldName);
}
pub fn storeWorldName(_worldName: []const u8) void {
	if (std.mem.eql(u8, _worldName, worldName)) return;
	main.globalAllocator.free(worldName);
	worldName = main.globalAllocator.dupe(u8, _worldName);
}

// storing stuff for init after restart
pub var connectionManager: ?*main.network.ConnectionManager = null;
