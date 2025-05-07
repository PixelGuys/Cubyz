const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Energy = @This();

entityId: u32 = undefined,

maxEnergy: f32,
energy: f32,

pub fn loadFromZon(_: []const u8, _: []const u8, zon: ZonElement) Energy {
	const maxEnergy = zon.get(f32, "maxEnergy", 8);
	return .{
		.maxEnergy = maxEnergy,
		.energy = maxEnergy,
	};
}

pub fn copy(self: *Energy) Energy {
	return .{
		.maxEnergy = self.maxEnergy,
		.energy = self.energy,
	};
}

pub fn addEnergy(self: *Energy, energy: f32) void {
	_ = self;
	_ = energy;
	// Some networking stuff
}