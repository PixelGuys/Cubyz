const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Health = @This();

entityId: u32 = undefined,

maxHealth: f32,
health: f32,

pub fn loadFromZon(_: []const u8, _: []const u8, zon: ZonElement) Health {
	const maxHealth = zon.get(f32, "maxHealth", 8);
	return .{
		.maxHealth = maxHealth,
		.health = maxHealth,
	};
}

pub fn copy(self: *Health) Health {
	return .{
		.maxHealth = self.maxHealth,
		.health = self.health,
	};
}

pub fn addHealth(self: *Health, health: f32) void {
	_ = self;
	_ = health;
	// Some networking stuff
}