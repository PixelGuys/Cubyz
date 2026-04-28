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
var uniforms: struct {
	projectionMatrix: c_int,
	viewMatrix: c_int,
	light: c_int,
	contrast: c_int,
	ambientLight: c_int,
} = undefined;

pub var entities: main.utils.VirtualList(main.client.Entity, 1 << 20) = undefined;
pub var idMapping: std.AutoHashMap(u32, *main.client.Entity) = undefined;
pub var mutex: main.utils.Mutex = .{};

pub fn init() void {
	entities = .init();
	idMapping = .init(main.globalAllocator.allocator);
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

	var ent = entities.addOne();
	const id = zon.get(?u32, "id", null) orelse return error.entityIdMissing;
	try idMapping.put(id, ent);
	try ent.init(zon, main.globalAllocator);
}
pub fn getEntity(id: u32) ?*main.client.Entity {
	return idMapping.get(id);
}
pub fn removeEntity(id: u32) void {
	mutex.lock();
	defer mutex.unlock();

	_ = idMapping.remove(id);
	for (entities.items(), 0..) |*ent, i| {
		if (ent.id == id) {
			ent.deinit(main.globalAllocator);
			_ = entities.swapRemove(i);
			if (i != entities.len) {
				entities.items()[i].interpolatedValues.outPos = &entities.items()[i]._interpolationPos;
				entities.items()[i].interpolatedValues.outVel = &entities.items()[i]._interpolationVel;
			}
			break;
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
