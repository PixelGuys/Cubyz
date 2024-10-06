const std = @import("std");

const main = @import("root");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},
// TODO: Health and hunger
// TODO: Name

pub fn loadFrom(self: *@This(), zon: ZonElement) void {
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
}

pub fn save(self: *@This(), allocator: NeverFailingAllocator) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", self.pos);
	zon.put("velocity", self.vel);
	zon.put("rotation", self.rot);
	return zon;
}
