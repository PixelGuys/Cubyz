const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Name = @This();

entityId: u32 = undefined,

name: []u8 = &.{},

pub fn loadFromZon(_: []const u8, _: []const u8, _: ZonElement) Name {
	return .{};
}

pub fn copy(_: *Name) Name {
	return .{};
}

pub fn setName(self: *Name, name: []const u8) void {
	self.name = main.ecs.ecsAllocator.dupe(u8, name);
}