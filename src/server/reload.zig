const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

pub var worldName: []const u8 = &.{};

pub fn init(_worldName: []const u8) void {
	worldName = main.globalAllocator.dupe(u8, _worldName);
}
pub fn deinit() void {
	main.globalAllocator.free(worldName);
}
