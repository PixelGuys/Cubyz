const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const c = graphics.c;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

var lastTime: i16 = 0;
var timeDifference: utils.TimeDifference = utils.TimeDifference{};
pub var entityArray: main.utils.VirtualList(main.client.Entity, 1 << 24) = undefined;
pub var idToIndex: std.AutoHashMap(u32, u32) = undefined;
pub var mutex: std.Thread.Mutex = .{};
pub fn init() void {
	entityArray = .init();
	idToIndex = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	mutex.lock();
	defer mutex.unlock();
	for (entityArray.items()) |value| {
		value.deinit(main.globalAllocator);
	}
	entityArray.deinit();
	idToIndex.deinit();
}

pub fn clear() void {
	mutex.lock();
	defer mutex.unlock();
	for (entityArray.items()) |value| {
		value.deinit(main.globalAllocator);
	}
	entityArray.clearRetainingCapacity();
	idToIndex.clearRetainingCapacity();
	timeDifference = utils.TimeDifference{};
}
pub fn getEntity(entityID: u32) *main.client.Entity {
	main.utils.assertLocked(&mutex);
	return &entityArray.items()[idToIndex.get(entityID) orelse unreachable];
}

pub fn update() void {
	mutex.lock();
	defer mutex.unlock();
	var time: i16 = @truncate(main.timestamp().toMilliseconds() -% settings.entityLookback);
	time -%= timeDifference.difference.load(.monotonic);

	// std.debug.print("{}\n", .{entityArray.items()[0].pos});
	// std.debug.print("{}\n", .{idToIndex.get(0) orelse 42});

	for (entityArray.items()) |*ent| {
		ent.update(time, lastTime);
	}
	lastTime = time;
}

pub fn addEntity(zon: ZonElement) void {
	mutex.lock();
	defer mutex.unlock();

	const index = entityArray.len;
	var entity = entityArray.addOne();
	main.client.Entity.init(entity, zon, main.globalAllocator) catch |err| {
		std.log.err("Failed to init Entity: {}", .{err});
		unreachable;
	};

	if (idToIndex.get(entity.id)) |_| {
		removeEntity(entity.id);
		unreachable;
	}
	idToIndex.put(entity.id, index) catch unreachable;
}

pub fn removeEntity(id: u32) void {
	mutex.lock();
	defer mutex.unlock();

	const i = idToIndex.get(id) orelse return;
	var ent = entityArray.items()[i];
	std.debug.assert(ent.id == id);

	ent.deinit(main.globalAllocator);
	_ = idToIndex.remove(id);
	_ = entityArray.swapRemove(i);
	if (i != entityArray.len) {
		entityArray.items()[i].interpolatedValues.outPos = &entityArray.items()[i]._interpolationPos;
		entityArray.items()[i].interpolatedValues.outVel = &entityArray.items()[i]._interpolationVel;
		idToIndex.put(entityArray.items()[i].id, i) catch unreachable;
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
		for (entityArray.items()) |*ent| {
			if (ent.id == data.id) {
				ent.updatePosition(&pos, &vel, time);
				break;
			}
		}
	}
}
