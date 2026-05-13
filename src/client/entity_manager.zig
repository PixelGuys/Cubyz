const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

var lastTime: i16 = 0;
var timeDifference: utils.TimeDifference = utils.TimeDifference{};

pub var entities: main.utils.VirtualList(main.client.Entity, 1 << 20) = undefined;
pub var idMapping: main.List(?u32) = undefined;
pub var mutex: main.utils.Mutex = .{};

pub fn init() void {
	entities = .init();
	idMapping = .init(main.globalAllocator);
}

pub fn deinit() void {
	for (entities.items()) |ent| {
		ent.deinit(main.globalAllocator);
	}
	entities.deinit();
	idMapping.deinit();
}

pub fn clear() void {
	for (entities.items()) |ent| {
		ent.deinit(main.globalAllocator);
	}
	entities.clearRetainingCapacity();
	idMapping.clearRetainingCapacity();
	timeDifference = utils.TimeDifference{};
}

pub fn update() void {
	mutex.lock();
	defer mutex.unlock();

	var time: i16 = @truncate(main.timestamp().toMilliseconds() -% settings.entityLookback);
	time -%= timeDifference.difference.load(.monotonic);
	for (entities.items()) |*ent| {
		ent.update(time, lastTime);
	}
	lastTime = time;
}

pub fn addEntity(zon: ZonElement) !void {
	mutex.lock();
	defer mutex.unlock();

	const id = zon.get(?u32, "id", null) orelse return error.entityIdMissing;
	const index = entities.len;
	var ent = entities.addOne();

	if (idMapping.items.len <= id)
		idMapping.appendNTimes(null, id - idMapping.items.len + 1);
	idMapping.items[id] = index;

	try ent.init(zon, main.globalAllocator);
}
pub fn getEntity(id: u32) ?*main.client.Entity {
	mutex.assertLocked();
	if (id < idMapping.items.len)
		return &entities.items()[idMapping.items[id] orelse return null];
	return null;
}
pub fn removeEntity(id: u32) void {
	mutex.lock();
	defer mutex.unlock();

	if (idMapping.items.len <= id)
		return;
	const index: u32 = idMapping.items[id] orelse return;
	const ent = entities.items()[index];

	// remove id
	idMapping.items[id] = null;

	// remove entity
	{
		std.debug.assert(ent.id == id);
		ent.deinit(main.globalAllocator);
		_ = entities.swapRemove(index);

		if (index != entities.len) {
			idMapping.items[entities.items()[index].id] = index;
			entities.items()[index].interpolatedValues.outPos = &entities.items()[index]._interpolationPos;
			entities.items()[index].interpolatedValues.outVel = &entities.items()[index]._interpolationVel;
		}
	}
}

pub fn serverUpdate(time: i16, entityData: []main.entity.EntityNetworkData) void {
	mutex.lock();
	defer mutex.unlock();
	timeDifference.addDataPoint(time);

	for (entityData) |data| {
		const pos = [_]f64{
			data.pos[0],
			data.pos[1],
			data.pos[2],
			@floatCast(data.rot[0]),
			@floatCast(data.rot[1]),
			@floatCast(data.rot[2]),
		};
		const vel = [_]f64{
			data.vel[0],
			data.vel[1],
			data.vel[2],
			0,
			0,
			0,
		};
		if (getEntity(data.id)) |ent| {
			ent.updatePosition(&pos, &vel, time);
		}
	}
}
