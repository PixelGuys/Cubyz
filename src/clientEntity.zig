const std = @import("std");

const chunk = @import("chunk.zig");
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

pub const EntityNetworkData = struct {
	id: u32,
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
};

pub const ClientEntity = struct {
	interpolatedValues: utils.GenericInterpolation(6) = undefined,
	_interpolationPos: [6]f64 = undefined,
	_interpolationVel: [6]f64 = undefined,

	width: f64,
	height: f64,

	pos: Vec3d = undefined,
	rot: Vec3f = undefined,

	id: u32,
	name: []const u8,

	pub fn init(self: *ClientEntity, zon: ZonElement, allocator: NeverFailingAllocator) void {
		self.* = ClientEntity{
			.id = zon.get(u32, "id", std.math.maxInt(u32)),
			.width = zon.get(f64, "width", 1),
			.pos = zon.get(Vec3d, "pos", .{0, 0, 0}),
			.rot = zon.get(Vec3f, "rot", .{0, 0, 0}),
			// .vel = zon.get(Vec3f,"vel",.{0,0,0}),
			.height = zon.get(f64, "height", 1),
			.name = allocator.dupe(u8, zon.get([]const u8, "name", "")),
		};

		self._interpolationPos = [_]f64{
			self.pos[0],
			self.pos[1],
			self.pos[2],
			@floatCast(self.rot[0]),
			@floatCast(self.rot[1]),
			@floatCast(self.rot[2]),
		};
		self._interpolationVel = @splat(0);
		self.interpolatedValues.init(&self._interpolationPos, &self._interpolationVel);

		// components
		if (zon.getChildOrNull("components")) |components| {
			const list = main.entityComponent;
			inline for (@typeInfo(list).@"struct".decls) |decl| {
				if (components.getChildOrNull(decl.name)) |comp| {
					@field(list, decl.name).Client.register(self.id, comp);
				}
			}
		}
	}

	pub fn deinit(self: ClientEntity, allocator: NeverFailingAllocator) void {
		if (self.id < 1000) {
			std.debug.print("yo", .{});
		}
		const list = main.entityComponent;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			@field(list, decl.name).Client.unregister(self.id);
		}
		allocator.free(self.name);
	}

	pub fn getRenderPosition(self: *const ClientEntity) Vec3d {
		return Vec3d{self.pos[0], self.pos[1], self.pos[2]};
	}

	pub fn updatePosition(self: *ClientEntity, pos: *const [6]f64, vel: *const [6]f64, time: i16) void {
		self.interpolatedValues.updatePosition(pos, vel, time);
	}

	pub fn update(self: *ClientEntity, time: i16, lastTime: i16) void {
		self.interpolatedValues.update(time, lastTime);
		self.pos[0] = self.interpolatedValues.outPos[0];
		self.pos[1] = self.interpolatedValues.outPos[1];
		self.pos[2] = self.interpolatedValues.outPos[2];
		self.rot[0] = @floatCast(self.interpolatedValues.outPos[3]);
		self.rot[1] = @floatCast(self.interpolatedValues.outPos[4]);
		self.rot[2] = @floatCast(self.interpolatedValues.outPos[5]);
	}
};

pub const ClientEntityManager = struct {
	var lastTime: i16 = 0;
	var timeDifference: utils.TimeDifference = utils.TimeDifference{};

	pub var entityArray: main.utils.VirtualList(ClientEntity, 1 << 24) = undefined;
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
	pub fn getEntity(entityID: u32) ClientEntity {
		main.utils.assertLocked(&mutex);
		return entityArray.items()[idToIndex.get(entityID) orelse unreachable];
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
		ClientEntity.init(entity, zon, main.globalAllocator);

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

	pub fn serverUpdate(time: i16, entityData: []EntityNetworkData) void {
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
};
