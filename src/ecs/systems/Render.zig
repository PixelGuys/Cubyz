const std = @import("std");

const main = @import("main");

const ecs = main.ecs;

const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const ZonElement = main.ZonElement;

const Render = @This();

pub const id = "render";

pub fn isValid(components: ecs.ComponentBitset) bool {
	return components.model and components.transform;
}

pub fn run(target: u32) void {
	_ = target;
}