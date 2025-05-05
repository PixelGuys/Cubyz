const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Health = @This();

maxHealth: f32,
health: f32,

pub fn loadFromZon(zon: ZonElement) Health {
	const maxHealth = zon.get(f32, "maxHealth", 8);
	return .{
		.maxHealth = maxHealth,
		.health = maxHealth,
	};
}