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

pub fn createFromDefaults(self: *Transform, entityId: u32) void {
	self.interpolation.init(@ptrCast(&self.pos), @ptrCast(&self.vel));
	self.entityId = entityId;
}

pub fn setPosition(self: *Transform, pos: Vec3d) void {
	_ = self;
	_ = pos;
	// Some networking stuff
}

pub fn setVelocity(self: *Transform, vel: Vec3d) void {
	_ = self;
	_ = vel;
	// Some networking stuff
}

pub fn setRotation(self: *Transform, rot: Vec3f) void {
	_ = self;
	_ = rot;
	// Some networking stuff
}