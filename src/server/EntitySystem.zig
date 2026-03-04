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

pub var entities: main.utils.VirtualList(server.Entity, 1 << 24) = undefined;
// TODO: have a sorted freed List for reuse.

pub fn init() void {
	entities = .init();
	const list = main.entityComponent;
	inline for (@typeInfo(list).@"struct".decls) |decl| {
		@field(list, decl.name).Server.init();
	}
}
pub fn getAll() []server.Entity {
	return entities.items();
}

pub fn deinit() void {
	for (entities.items()) |*value| {
		value.deinit(.ServerSide);
	}
	entities.deinit();

	const list = main.entityComponent;
	inline for (@typeInfo(list).@"struct".decls) |decl| {
		@field(list, decl.name).Server.deinit();
	}
}

pub fn add() u32 {
	// TODO: add a freed list.
	const id: u32 = @truncate(entities.items().len);
	var ent = entities.addOne();
	ent.* = server.Entity{};
	ent.inUse = true;
	ent.id = id;
	return id;
}
pub fn remove(entityID: u32) void {
	for (entities.items()) |*value| {
		if (value.id == entityID) {
			value.deinit(.ServerSide);
			value.inUse = false;

			const list = main.entityComponent;
			inline for (@typeInfo(list).@"struct".decls) |decl| {
				@field(list, decl.name).Server.unregister(entityID);
			}
			return;
		}
	}

	// TODO: add the entity to the freed list
	// if it is last one, remove until last one on entities isnt on freedList
	// .inUse = false
	// use swapremove
}
pub fn getEntity(entityID: u32) *server.Entity {
	return &entities.items()[entityID];
}
pub fn getEntitiesBasicInfo() main.ZonElement {
	const zonArray = main.ZonElement.initArray(main.stackAllocator);
	for (entities.items(), 0..) |entity, i| {
		if (!entity.inUse)
			continue;
		const entityZon = entity.save(main.stackAllocator);
		//const entityZon = main.ZonElement.initObject(main.stackAllocator);
		entityZon.put("id", i);
		//entityZon.put("name", entity.name);
		//if (entity.entityType) |entityType|
		//entityZon.put("type", entityType.id);
		zonArray.array.append(entityZon);
	}
	return zonArray;
}
pub fn getEntityBasicInfo(id: u32, array: *main.List(main.ZonElement)) void {
	const entity = entities.items()[id];
	const entityZon = entity.save(main.stackAllocator);
	//const entityZon = main.ZonElement.initObject(main.stackAllocator);
	entityZon.put("id", id);
	//entityZon.put("name", entity.name);

	// if (entity.entityType) |entityType|
	// entityZon.put("type", entityType.id);
	array.append(entityZon);
}
