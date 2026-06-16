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

var entities: main.utils.VirtualList(server.Entity, 1 << 24) = undefined;
var idMapping: main.List(?u32) = undefined;

var freedList: main.List(main.entity.Entity) = undefined;

pub fn init() void {
	entities = .init();
	idMapping = .empty;
	freedList = .empty;
}
pub fn deinit() void {
	for (entities.items()) |*ent| {
		ent.deinit(.server);
	}
	entities.deinit();
	idMapping.deinit(main.globalAllocator);
	freedList.deinit(main.globalAllocator);
}

pub fn getAll() []server.Entity {
	return entities.items();
}

var freeId: u32 = 0;
pub fn addEntity() main.entity.Entity {
	// get a free Id
	var entityId: main.entity.Entity = undefined;
	if (freedList.items.len > 0) {
		entityId = freedList.swapRemove(0);
	} else {
		entityId = @enumFromInt(freeId);
		freeId += 1;
	}

	// get a new memory address
	const index: u32 = entities.len;
	var ent = entities.addOne();

	// assign index to memory address
	if (idMapping.items.len <= @intFromEnum(entityId)) {
		idMapping.appendNTimes(main.globalAllocator, null, @intFromEnum(entityId) - idMapping.items.len + 1);
	}
	idMapping.items[@intFromEnum(entityId)] = index;

	// initialization of the Entity
	ent.* = server.Entity{};
	ent.id = entityId;
	return entityId;
}

pub fn getEntity(entityId: main.entity.Entity) ?*server.Entity {
	if (@intFromEnum(entityId) >= idMapping.items.len) return null;
	return &entities.items()[idMapping.items[@intFromEnum(entityId)] orelse return null];
}

pub fn removeEntity(entityId: main.entity.Entity) void {
	if (idMapping.items.len <= @intFromEnum(entityId)) return;
	const index: u32 = idMapping.items[@intFromEnum(entityId)] orelse return;
	const ent = &entities.items()[index];

	// remove id
	idMapping.items[@intFromEnum(entityId)] = null;

	// remove entity
	{
		std.debug.assert(ent.id == entityId);
		ent.deinit(.server);
		_ = entities.swapRemove(index);

		if (index != entities.len) {
			idMapping.items[@intFromEnum(entities.items()[index].id)] = index;
		}
		freedList.addOne(main.globalAllocator).* = entityId;
	}
}

pub fn getEntitiesNearbyInfo(allocator: main.heap.NeverFailingAllocator) main.ZonElement {
	const zonArray = main.ZonElement.initArray(allocator);
	for (entities.items()) |*entity| {
		const entityZon = entity.save(allocator, .playerNearby);
		zonArray.array.append(entityZon);
	}
	return zonArray;
}
pub fn getEntityNearbyInfo(entityId: main.entity.Entity, allocator: main.heap.NeverFailingAllocator) ?main.ZonElement {
	const entity = getEntity(entityId) orelse return null;
	return entity.save(allocator, .playerNearby);
}
