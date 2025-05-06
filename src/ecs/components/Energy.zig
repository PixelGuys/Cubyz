const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Energy = @This();

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

pub fn serialize(self: *Energy, writer: *main.utils.BinaryWriter) !void {
	try writer.writeEnum(main.ecs.Components, .energy);
	try writer.writeFloat(f32, self.maxEnergy);
	try writer.writeFloat(f32, self.energy);
}

pub fn deserialize(reader: *main.utils.BinaryReader) !Energy {
	return .{
		.maxEnergy = try reader.readFloat(f32),
		.energy = try reader.readFloat(f32),
	};
}