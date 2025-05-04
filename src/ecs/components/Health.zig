const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Health = @This();

const id = "health";
const bit = 0;

maxHealth: f32 = undefined,

health: f32 = undefined,

pub fn loadFromZon(self: *Health, zon: ZonElement) void {
	self.maxHealth = zon.get(f32, "maxHealth", 8);
	self.health = zon.get(f32, "health", self.maxHealth);
}