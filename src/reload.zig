const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");
const ZonElement = main.ZonElement;
const Window = @import("graphics/Window.zig");

pub const version = @import("utils/version.zig");

pub var lastWorldName: []const u8 = &.{};

pub fn init() void {}
pub fn deinit() void {
	main.globalAllocator.free(lastWorldName);
}
pub fn storeWorldName(worldName: []const u8) void {
	if (std.mem.eql(u8, lastWorldName, worldName)) return;
	main.globalAllocator.free(lastWorldName);
	lastWorldName = main.globalAllocator.dupe(u8, worldName);
}
