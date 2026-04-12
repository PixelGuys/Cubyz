const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const chunk = main.chunk;
const network = main.network;
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const InventoryId = main.items.Inventory.InventoryId;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;
const Blueprint = main.blueprint.Blueprint;
const Mask = main.blueprint.Mask;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const CircularBufferQueue = main.utils.CircularBufferQueue;
const sync = main.sync;
const server = main.server;

pub var entities: main.utils.SparseSet(server.Entity, main.entity.Entity) = undefined;
var freedList: main.ListUnmanaged(u32) = undefined;

pub fn init() void {
	entities = .{};
	freedList = .{};
}
pub fn deinit() void {
	for (entities.dense.items) |*value| {
		value.deinit(.server);
	}
	entities.deinit(main.globalAllocator);
	freedList.deinit(main.globalAllocator);
}
pub fn getAll() []server.Entity {
	return entities.dense.items;
}

var freeId = 0;
pub fn add() u32 {
	// TODO: add a freed list.
	var entityId: i32 = undefined;
	var ent: *server.Entity = undefined;
	if (freedList.items.len > 0) {
		entityId = freedList.items[0];
		freedList.swapRemove(entityId);
		ent = entities.add(main.globalAllocator, entityId);
	} else {
		entityId = freeId;
		freeId += 1;
		ent = entities.get(entityId) orelse entities.add(main.globalAllocator, entityId);
	}
	ent.* = server.Entity{};
	ent.id = entityId;
	return entityId;
}
pub fn remove(entityId: u32) void {
	if (entities.get(entityId)) |entity| {
		entity.deinit(.server);
		entities.remove(entityId);
		freedList.addOne(main.globalAllocator).* = entityId;
	}
}
pub fn getEntity(entityId: u32) ?*server.Entity {
	return entities.get(entityId);
}
pub fn getEntitiesBasicInfo(allocator: *main.heap.NeverFailingAllocator) main.ZonElement {
	const zonArray = main.ZonElement.initArray(allocator);
	for (entities.dense.items) |entity| {
		const entityZon = entity.save(allocator, .playerNearby);
		zonArray.array.append(entityZon);
	}
	return zonArray;
}
pub fn getEntityBasicInfo(entityId: u32, allocator: *main.heap.NeverFailingAllocator) ?main.ZonElement {
	const entity = entities.get(entityId);
	if (entity) |ent| {
		return ent.save(allocator, .playerNearby);
	} else {
		return null;
	}
}
