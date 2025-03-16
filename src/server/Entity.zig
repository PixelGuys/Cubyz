const std = @import("std");

const main = @import("root");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

health: f32 = 8,
maxHealth: f32 = 8,
hunger: f32 = 8,
maxHunger: f32 = 8,
// TODO: Name

pub fn loadFrom(self: *@This(), zon: ZonElement) void {
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.hunger = zon.get(f32, "hunger", self.maxHunger);
}

pub fn save(self: *@This(), allocator: NeverFailingAllocator) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", self.pos);
	zon.put("velocity", self.vel);
	zon.put("rotation", self.rot);
	zon.put("health", self.health);
	zon.put("hunger", self.hunger);
	return zon;
}
