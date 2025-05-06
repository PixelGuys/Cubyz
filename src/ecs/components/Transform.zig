const std = @import("std");

const main = @import("main");

const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const ZonElement = main.ZonElement;

const Transform = @This();

pos: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

pub fn loadFromZon(_: []const u8, _: []const u8, _: ZonElement) Transform {
	return .{};
}

pub fn copy(self: *Transform) Transform {
	return .{
		.pos = self.pos,
		.rot = self.rot,
	};
}

pub fn serialize(self: *Transform, writer: *main.utils.BinaryWriter) !void {
	try writer.writeEnum(main.ecs.Components, .transform);
	try writer.writeVec(Vec3d, self.pos);
	try writer.writeVec(Vec3f, self.rot);
}

pub fn deserialize(reader: *main.utils.BinaryReader) !Transform {
	return .{
		.pos = try reader.readVec(Vec3d),
		.rot = try reader.readVec(Vec3f),
	};
}