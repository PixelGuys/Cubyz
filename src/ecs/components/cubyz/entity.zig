const std = @import("std");

const main = @import("main");
const SparseSet = main.utils.SparseSet;
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const ecs = main.ecs;
const EntityTypeIndex = ecs.EntityTypeIndex;
const EntityIndex = ecs.EntityIndex;

const Self = @This();

const typeStorage: SparseSet(TypeData, EntityTypeIndex) = undefined;
const storage: SparseSet(Data, EntityIndex) = undefined;

pub const TypeData = struct {
	maxHealth: f32 = 8,
	maxEnergy: f32 = 8,
};

pub const Data = struct {
	pos: Vec3d = .{0, 0, 0},
	vel: Vec3d = .{0, 0, 0},
	rot: Vec3f = .{0, 0, 0},

	health: f32 = 8,
	maxHealth: f32 = 8,

	energy: f32 = 8,
	maxEnergy: f32 = 8,
};

pub fn init() void {
	typeStorage = .{};
	storage = .{};
}

pub fn fromZon(self: *Self, zon: ZonElement) void {
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
}

pub fn toZon(allocator: NeverFailingAllocator) ZonElement {
	const list = ZonElement.initArray(allocator);

	for(storage.dense.items) |item| {
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

pub fn initData(allocator: NeverFailingAllocator, entityId: EntityIndex, entityTypeId: EntityTypeIndex) void {
	const typeData = typeStorage.get(entityTypeId).?;
	storage.set(allocator, entityId, .{
		.maxHealth = typeData.maxHealth,
		.health = typeData.maxHealth,

		.maxEnergy = typeData.maxEnergy,
		.energy = typeData.maxEnergy,
	});
}

pub fn deinitData(_: NeverFailingAllocator, entityIndex: EntityIndex, _: EntityTypeIndex) !void {
	try storage.remove(entityIndex);
}

pub fn get(entityId: EntityIndex) ?*Data {
	return storage.get(entityId);
}

pub fn initType(allocator: NeverFailingAllocator, entityTypeId: EntityTypeIndex, zon: ZonElement) void {
	const value: TypeData = .{
		.maxHealth = zon.get(?f32, "maxHealth", null) orelse blk: {
			std.log.err("Missing required parameter: maxHealth");
			break :blk 8;
		},
		.maxEnergy = zon.get(?f32, "maxEnergy", null) orelse blk: {
			std.log.err("Missing required parameter: maxEnergy");
			break :blk 8;
		},
	};
	typeStorage.set(allocator, entityTypeId, value);
}

pub fn deinit(allocator: NeverFailingAllocator) void {
	typeStorage.deinit(allocator);
	storage.deinit(allocator);
}
