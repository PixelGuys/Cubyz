const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Health = @This();

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

pub fn serialize(self: *Health, writer: *main.utils.BinaryWriter) !void {
	try writer.writeEnum(main.ecs.Components, .health);
	try writer.writeFloat(f32, self.maxHealth);
	try writer.writeFloat(f32, self.health);
}

pub fn deserialize(reader: *main.utils.BinaryReader) !Health {
	return .{
		.maxHealth = try reader.readFloat(f32),
		.health = try reader.readFloat(f32),
	};
}