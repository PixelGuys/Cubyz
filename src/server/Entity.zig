const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

var numEntities: u32 = 0;

id: u32 = 0,
pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

health: f32 = 8,
maxHealth: f32 = 8,
energy: f32 = 8,
maxEnergy: f32 = 8,

name: []const u8 = "",

entityType: u16 = 0,

pub fn loadFrom(self: *@This(), zon: ZonElement) void {
	self.id = numEntities;
	numEntities += 1;
	
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
	self.name = main.globalAllocator.dupe(u8, zon.get([]const u8, "name", ""));
	self.entityType = zon.get(u16, "entityType", 0);
}

pub fn deinit(self: @This()) void {
	main.globalAllocator.free(self.name);
}

pub fn save(self: *@This(), allocator: NeverFailingAllocator) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", self.pos);
	zon.put("velocity", self.vel);
	zon.put("rotation", self.rot);
	zon.put("health", self.health);
	zon.put("energy", self.energy);
	zon.putOwnedString("name", self.name);
	zon.put("entityType", self.entityType);
	return zon;
}
