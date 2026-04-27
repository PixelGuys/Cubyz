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

pub var entities: main.utils.SparseSet(main.client.Entity, main.entity.Entity) = undefined;
pub var mutex: main.utils.Mutex = .{};

pub fn init() void {
	entities = .{};
}

pub fn deinit() void {
	for (entities.dense.items) |*value| {
		value.deinit(main.globalAllocator);
	}
	entities.deinit(main.globalAllocator);
}

pub fn clear() void {
	deinit();
	init();
	timeDifference = utils.TimeDifference{};
}

pub fn update() void {
	mutex.lock();
	defer mutex.unlock();

	var time: i16 = @truncate(main.timestamp().toMilliseconds() -% settings.entityLookback);
	time -%= timeDifference.difference.load(.monotonic);
	for (entities.dense.items) |*ent| {
		ent.update(time, lastTime);
	}
	lastTime = time;
}

pub fn addEntity(zon: ZonElement) !void {
	mutex.lock();
	defer mutex.unlock();

	const id = zon.get(?u32, "id", null) orelse return error.entityIdMissing;
	var ent = entities.add(main.globalAllocator, @enumFromInt(id));
	try ent.init(zon, main.globalAllocator);
}
pub fn getEntity(id: u32) ?*main.client.Entity {
	return entities.get(@enumFromInt(id));
}
pub fn removeEntity(id: u32) void {
	mutex.lock();
	defer mutex.unlock();

	std.debug.assert(entities.sparseToDenseIndex.items.len > id);
	const oldIndex = @intFromEnum(entities.sparseToDenseIndex.items[id]);
	const ent = entities.fetchRemove(@enumFromInt(id)) catch unreachable;
	ent.deinit(main.globalAllocator);

	if(entities.dense.items.len > oldIndex){
		entities.dense.items[oldIndex].interpolatedValues.outPos = &entities.dense.items[oldIndex]._interpolationPos;
		entities.dense.items[oldIndex].interpolatedValues.outVel = &entities.dense.items[oldIndex]._interpolationVel;	
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
		if(getEntity(data.id))|ent|{
			ent.updatePosition(&pos, &vel, time);
		}
	}
}
