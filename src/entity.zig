const std = @import("std");

const JsonElement = @import("json.zig").JsonElement;
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

pub const ClientEntity = struct {
	interpolatedValues: utils.GenericInterpolation(6) = undefined,

	width: f64,
	height: f64,
//	TODO:
//	public final EntityType type;
	
	pos: Vec3d = undefined,
	rot: Vec3f = undefined,

	id: u32,
	name: []const u8,

	pub fn init(self: *ClientEntity) void {
		self.interpolatedValues.init();
	}

	pub fn getRenderPosition(self: *ClientEntity) Vec3d {
		return Vec3d{.x = self.pos.x, .y = self.pos.y + self.height/2, .z = self.pos.z};
	}

	pub fn updatePosition(self: *ClientEntity, pos: [3]f64, vel: [3]f64, time: i16) void {
		self.interpolatedValues.updatePosition(pos, vel, time);
	}

	pub fn update(self: *ClientEntity, time: i16, lastTime: i16) void {
		self.interpolatedValues.update(time, lastTime);
		self.pos.x = self.interpolatedValues.outPos[0];
		self.pos.y = self.interpolatedValues.outPos[1];
		self.pos.z = self.interpolatedValues.outPos[2];
		self.rot.x = @floatCast(f32, self.interpolatedValues.outPos[3]);
		self.rot.y = @floatCast(f32, self.interpolatedValues.outPos[4]);
		self.rot.z = @floatCast(f32, self.interpolatedValues.outPos[5]);
	}
};

pub const ClientEntityManager = struct {
	var lastTime: i16 = 0;
	var timeDifference: utils.TimeDifference = utils.TimeDifference{};
	pub var entities: std.ArrayList(ClientEntity) = undefined;
	pub var mutex: std.Thread.Mutex = std.Thread.Mutex{};

	pub fn init() void {
		entities = std.ArrayList(ClientEntity).init(renderer.RenderStructure.allocator); // TODO: Use world allocator.
	}

	pub fn deinit() void {
		entities.deinit();
	}

	pub fn clear() void {
		entities.clearRetainingCapacity();
		timeDifference = utils.TimeDifference{};
	}

	pub fn update() void {
		mutex.lock();
		defer mutex.unlock();
		var time = @intCast(i16, std.time.milliTimestamp() & 65535);
		time -%= timeDifference.difference;
		for(entities.items) |*ent| {
			ent.update(time, lastTime);
		}
		lastTime = time;
	}

	pub fn addEntity(json: JsonElement) !void {
		mutex.lock();
		defer mutex.unlock();
		var ent = try entities.addOne();
		ent.* = ClientEntity{
			.id = json.get(u32, "id", std.math.maxInt(u32)),
			// TODO:
//			CubyzRegistries.ENTITY_REGISTRY.getByID(json.getString("type", null)),
			.width = json.get(f64, "width", 1),
			.height = json.get(f64, "height", 1),
			.name = json.get([]const u8, "name", 1),
		};
		ent.init();
	}

	pub fn removeEntity(id: u32) void {
		mutex.lock();
		defer mutex.unlock();
		for(entities.items) |*ent, i| {
			if(ent.id == id) {
				entities.swapRemove(i);
				break;
			}
		}
	}

	pub fn serverUpdate(time: i16, data: []const u8) !void {
		mutex.lock();
		defer mutex.unlock();
		timeDifference.addDataPoint(time);
		std.debug.assert(data.len%(4 + 24 + 12 + 24) == 0);
		var remaining = data;
		while(remaining.len != 0) {
			const id = std.mem.readIntBig(u32, remaining[0..4]);
			remaining = remaining[4..];
			const pos = [_]f64 {
				@bitCast(f64, std.mem.readIntBig(u64, remaining[0..8])),
				@bitCast(f64, std.mem.readIntBig(u64, remaining[8..16])),
				@bitCast(f64, std.mem.readIntBig(u64, remaining[16..24])),
				@floatCast(f64, @bitCast(f32, std.mem.readIntBig(u32, remaining[24..28]))),
				@floatCast(f64, @bitCast(f32, std.mem.readIntBig(u32, remaining[28..32]))),
				@floatCast(f64, @bitCast(f32, std.mem.readIntBig(u32, remaining[32..36]))),
			};
			remaining = remaining[36..];
			const vel = [_]f64 {
				@bitCast(f64, std.mem.readIntBig(u64, remaining[0..8])),
				@bitCast(f64, std.mem.readIntBig(u64, remaining[8..16])),
				@bitCast(f64, std.mem.readIntBig(u64, remaining[16..24])),
				0, 0, 0,
			};
			remaining = remaining[24..];
			for(entities.items) |*ent| {
				if(ent.id == id) {
					ent.updatePosition(pos, vel, time);
				}
			}
		}
	}
};