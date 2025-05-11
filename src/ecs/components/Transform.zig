const std = @import("std");

const main = @import("main");

const utils = main.utils;

const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const ZonElement = main.ZonElement;

const Transform = @This();

entityId: u32 = undefined,

pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

interpolation: utils.GenericInterpolation(3) = undefined,

pub fn loadFromZon(_: []const u8, _: []const u8, _: ZonElement) Transform {
	return .{};
}

pub fn copy(self: *Transform) Transform {
	return .{
		.pos = self.pos,
		.vel = self.vel,
		.rot = self.rot,
	};
}

pub fn createFromDefaults(self: *Transform) void {
	self.interpolation.init(@ptrCast(&self.pos), @ptrCast(&self.vel));
}