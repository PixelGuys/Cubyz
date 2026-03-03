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

var entities: main.ListUnmanaged(server.Entity) = .{};
// TODO: have a sorted freed List for reuse.

pub fn init() void {}
pub fn getAll() []server.Entity {
	return entities.items;
}

pub fn deinit() void {
	for (entities.items) |*value| {
		value.deinit();
	}
	entities.deinit(main.globalAllocator);
}

pub fn add() u32 {
	// TODO: add a freed list.
	const id: u32 = @truncate(entities.items.len);
	var ent = entities.addOne(main.globalAllocator);
	ent.inUse = true;
	return id;
}
pub fn remove(entityID: u32) void {
	_ = entityID;
	//TODO: add the entity to the freed list
	// if it is last one, remove until last one on entities isnt on freedList
	//.inUse = false
}
pub fn getEntity(entityID: u32) *server.Entity {
	return &entities.items[entityID];
}
pub fn getEntitiesBasicInfo() main.ZonElement {
	const zonArray = main.ZonElement.initArray(main.stackAllocator);
	for (entities.items, 0..) |entity, i| {
		if (!entity.inUse)
			continue;
		const entityZon = main.ZonElement.initObject(main.stackAllocator);
		entityZon.put("id", i);
		entityZon.put("name", entity.name);
		if (entity.entityType) |entityType|
			entityZon.put("type", entityType.id);
		zonArray.array.append(entityZon);
	}
	return zonArray;
}
pub fn getEntityBasicInfo(id: u32, array: *main.List(main.ZonElement)) void {
	const entity = entities.items[id];
	const entityZon = main.ZonElement.initObject(main.stackAllocator);
	entityZon.put("id", id);
	entityZon.put("name", entity.name);
	if (entity.entityType) |entityType|
		entityZon.put("type", entityType.id);
	array.append(entityZon);
}
