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

var typeStorage: SparseSet(TypeData, EntityTypeIndex) = undefined;
var storage: SparseSet(Data, EntityIndex) = undefined;

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

pub fn fromZon(self: *Data, zon: ZonElement) void {
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
}

pub fn toZon(allocator: NeverFailingAllocator, data: Data) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", data.pos);
	zon.put("velocity", data.vel);
	zon.put("rotation", data.rot);
	zon.put("health", data.health);
	zon.put("energy", data.energy);
	return zon;
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
