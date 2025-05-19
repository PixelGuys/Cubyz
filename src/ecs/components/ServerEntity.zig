const std = @import("std");

const main = @import("main");
const SparseSet = main.utils.SparseSet;
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const ecs = @import("../ecs.zig");
const EntityTypeId = ecs.EntityTypeId;
const EntityId = ecs.EntityId;

const Self = @This();

const typeStorage: SparseSet(EntityTypeData, EntityTypeId) = .{};
const storage: SparseSet(EntityData, EntityId) = .{};

pub const id = "cubyz:server_entity";

pub const EntityTypeData = struct {
	maxHealth: f32 = 8,
	maxEnergy: f32 = 8,
};

pub const EntityData = struct {
	typeId: EntityTypeId = undefined,

	pos: Vec3d = .{0, 0, 0},
	vel: Vec3d = .{0, 0, 0},
	rot: Vec3f = .{0, 0, 0},

	health: f32 = 8,
	maxHealth: f32 = 8,

	energy: f32 = 8,
	maxEnergy: f32 = 8,
};

pub fn fromZon(self: *Self, zon: ZonElement) void {
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
}

pub fn toZon(allocator: NeverFailingAllocator) ZonElement {
	const list = ZonElement.initArray(allocator);

	for (storage.dense.items) |item| {
		const zon = ZonElement.initObject(allocator);
		zon.put("position", item.pos);
		zon.put("velocity", item.vel);
		zon.put("rotation", item.rot);
		zon.put("health", item.health);
		zon.put("energy", item.energy);
		list.append(zon);
	}
	
	return list;
}

pub fn set(allocator: NeverFailingAllocator, entityId: EntityId, value: EntityData) void {
	storage.set(allocator, entityId, value);
}

pub fn remove(entityId: EntityId) !void {
	try storage.remove(entityId);
}

pub fn get(entityId: EntityId) ?*EntityData {
	return storage.get(entityId);
}

pub fn setType(allocator: NeverFailingAllocator, entityTypeId: EntityTypeId, value: EntityTypeData) void {
	typeStorage.set(allocator, entityTypeId, value);
}

pub fn getType(entityTypeId: EntityTypeId) ?*EntityTypeData {
	return typeStorage.get(entityTypeId);
}