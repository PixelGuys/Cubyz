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

pub fn deinit(allocator: NeverFailingAllocator) void {
	typeStorage.deinit(allocator);
	storage.deinit(allocator);
}

pub fn reset() void {
	typeStorage.clear();
	storage.clear();
}

pub fn fromZon(allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex, zon: ZonElement) void {
	const entityType = typeStorage.get(entityTypeIndex).?;
	if(storage.contains(entityIndex)) {
		storage.remove(entityIndex) catch unreachable;
	}
	storage.set(allocator, entityIndex, .{
		.pos = zon.get(Vec3d, "position", .{0, 0, 0}),
		.vel = zon.get(Vec3d, "velocity", .{0, 0, 0}),
		.rot = zon.get(Vec3f, "rotation", .{0, 0, 0}),
		.health = zon.get(f32, "health", entityType.maxHealth),
		.maxHealth = entityType.maxHealth,
		.energy = zon.get(f32, "energy", entityType.maxEnergy),
		.maxEnergy = entityType.maxEnergy,
	});
}

pub fn toZon(allocator: NeverFailingAllocator, entityIndex: EntityIndex) ZonElement {
	const data = storage.get(entityIndex).?;

	const zon = ZonElement.initObject(allocator);
	zon.put("position", data.pos);
	zon.put("velocity", data.vel);
	zon.put("rotation", data.rot);
	zon.put("health", data.health);
	zon.put("energy", data.energy);

	return zon;
}

pub fn add(allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex) void {
	const typeData = typeStorage.get(entityTypeIndex).?;
	const data: Data = .{
		.maxHealth = typeData.maxHealth,
		.health = typeData.maxHealth,

		.maxEnergy = typeData.maxEnergy,
		.energy = typeData.maxEnergy,
	};
	if(storage.get(entityIndex)) |ptr| {
		ptr.* = data;
		return;
	}
	storage.set(allocator, entityIndex, data);
}

pub fn set(allocator: NeverFailingAllocator, entityIndex: EntityIndex, data: Data) void {
	if(storage.get(entityIndex)) |ptr| {
		ptr.* = data;
		return;
	}
	storage.set(allocator, entityIndex, data);
}

pub fn get(entityIndex: EntityIndex) ?Data {
	const data = storage.get(entityIndex) orelse return null;
	return data.*;
}

pub fn has(entityIndex: EntityIndex) bool {
	return storage.contains(entityIndex);
}

pub fn remove(_: NeverFailingAllocator, entityIndex: EntityIndex, _: EntityTypeIndex) !void {
	try storage.remove(entityIndex);
}

pub fn initType(allocator: NeverFailingAllocator, entityTypeIndex: EntityTypeIndex, zon: ZonElement) void {
	const value: TypeData = .{
		.maxHealth = zon.get(?f32, "maxHealth", null) orelse blk: {
			std.log.err("Missing required parameter: maxHealth", .{});
			break :blk 8;
		},
		.maxEnergy = zon.get(?f32, "maxEnergy", null) orelse blk: {
			std.log.err("Missing required parameter: maxEnergy", .{});
			break :blk 8;
		},
	};
	typeStorage.set(allocator, entityTypeIndex, value);
}

pub fn hasType(entityTypeIndex: EntityTypeIndex) bool {
	return typeStorage.contains(entityTypeIndex);
}
