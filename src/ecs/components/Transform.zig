const std = @import("std");

const main = @import("main");

const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const ZonElement = main.ZonElement;

const Transform = @This();

pos: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

pub fn loadFromZon(_: ZonElement) Transform {
	return .{};
}