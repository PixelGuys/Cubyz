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
var freedList: main.List(main.entity.Entity) = undefined;

pub fn init() void {
	sync.threadContext.assertCorrectContext(.server);
	entities = .init();
	freedList = .empty;
}
pub fn deinit() void {
	sync.threadContext.assertCorrectContext(.server);
	for (entities.items()) |*ent| {
		if (ent.used) {
			ent.deinit(.server);
		}
	}
	entities.deinit();
	freedList.deinit(main.globalAllocator);
}

pub fn addEntity() main.entity.Entity {
	sync.threadContext.assertCorrectContext(.server);

	// get a free Id
	var entityId: main.entity.Entity = undefined;
	var ent: *server.Entity = undefined;
	if (freedList.items.len > 0) {
		entityId = freedList.swapRemove(0);
		ent = &entities.items()[@intFromEnum(entityId)];
	} else {
		entityId = @enumFromInt(entities.len);
		ent = entities.addOne();
	}

	// initialization of the Entity
	ent.* = server.Entity{};
	ent.id = entityId;
	ent.used = true;
	return entityId;
}

pub fn getEntity(entityId: main.entity.Entity) *server.Entity {
	sync.threadContext.assertCorrectContext(.server);

	std.debug.assert(@intFromEnum(entityId) < entities.len);
	std.debug.assert(entities.items()[@intFromEnum(entityId)].used);

	return &entities.items()[@intFromEnum(entityId)];
}

pub fn removeEntity(entityId: main.entity.Entity) void {
	sync.threadContext.assertCorrectContext(.server);

	if (@intFromEnum(entityId) >= entities.len) return;
	if (!entities.items()[@intFromEnum(entityId)].used) return;

	const ent = &entities.items()[@intFromEnum(entityId)];

	// remove entity
	{
		std.debug.assert(ent.id == entityId);
		ent.deinit(.server);
		ent.used = false;

		freedList.addOne(main.globalAllocator).* = entityId;
	}
}

pub fn getEntitiesNearbyInfo(allocator: main.heap.NeverFailingAllocator) main.ZonElement {
	sync.threadContext.assertCorrectContext(.server);

	const zonArray = main.ZonElement.initArray(allocator);
	for (entities.items()) |*entity| {
		if (!entity.used) continue;
		const entityZon = entity.save(allocator, .playerNearby);
		zonArray.array.append(entityZon);
	}
	return zonArray;
}
pub fn getEntityNearbyInfo(entityId: main.entity.Entity, allocator: main.heap.NeverFailingAllocator) ?main.ZonElement {
	sync.threadContext.assertCorrectContext(.server);

	const entity = getEntity(entityId);
	return entity.save(allocator, .playerNearby);
}

pub fn getEntityNetworkData(allocator: main.heap.NeverFailingAllocator) main.ListManaged(main.entity.EntityNetworkData) {
	sync.threadContext.assertCorrectContext(.server);

	var entityData: main.ListManaged(main.entity.EntityNetworkData) = .init(allocator);

	for (entities.items()) |*ent| {
		if (!ent.used) continue;
		const id = ent.id;
		entityData.append(.{
			.id = id,
			.pos = ent.pos,
			.vel = ent.vel,
			.rot = ent.rot,
		});
	}
	return entityData;
}
