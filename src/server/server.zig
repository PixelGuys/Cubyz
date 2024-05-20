const std = @import("std");

const main = @import("root");
const network = main.network;
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;

pub const ServerWorld = @import("world.zig").ServerWorld;
pub const terrain = @import("terrain/terrain.zig");
pub const Entity = @import("Entity.zig");
pub const storage = @import("storage.zig");


pub const User = struct {
	conn: *Connection,
	player: Entity = .{},
	timeDifference: utils.TimeDifference = .{},
	interpolation: utils.GenericInterpolation(3) = undefined,
	lastTime: i16 = undefined,
	name: []const u8 = "",
	renderDistance: u16 = undefined,
	receivedFirstEntityData: bool = false,
	isLocal: bool = false,
	id: u32 = 0, // TODO: Use entity id.
	// TODO: ipPort: []const u8,

	pub fn init(manager: *ConnectionManager, ipPort: []const u8) !*User {
		const self = main.globalAllocator.create(User);
		errdefer main.globalAllocator.destroy(self);
		self.* = User {
			.conn = try Connection.init(manager, ipPort),
		};
		self.conn.user = self;
		self.interpolation.init(@ptrCast(&self.player.pos), @ptrCast(&self.player.vel));
		network.Protocols.handShake.serverSide(self.conn);
		return self;
	}

	pub fn deinit(self: *User) void {
		self.conn.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}

	pub fn initPlayer(self: *User, name: []const u8) void {
		self.name = main.globalAllocator.dupe(u8, name);
		world.?.findPlayer(self);
	}

	pub fn update(self: *User) void {
		main.utils.assertLocked(&mutex);
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% main.settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		self.interpolation.update(time, self.lastTime);
		self.lastTime = time;
	}

	pub fn receiveData(self: *User, data: []const u8) void {
		mutex.lock();
		defer mutex.unlock();
		const position: [3]f64 = .{
			@bitCast(std.mem.readInt(u64, data[0..8], .big)),
			@bitCast(std.mem.readInt(u64, data[8..16], .big)),
			@bitCast(std.mem.readInt(u64, data[16..24], .big)),
		};
		const velocity: [3]f64 = .{
			@bitCast(std.mem.readInt(u64, data[24..32], .big)),
			@bitCast(std.mem.readInt(u64, data[32..40], .big)),
			@bitCast(std.mem.readInt(u64, data[40..48], .big)),
		};
		const rotation: [3]f32 = .{
			@bitCast(std.mem.readInt(u32, data[48..52], .big)),
			@bitCast(std.mem.readInt(u32, data[52..56], .big)),
			@bitCast(std.mem.readInt(u32, data[56..60], .big)),
		};
		self.player.rot = rotation;
		const time = std.mem.readInt(i16, data[60..62], .big);
		self.timeDifference.addDataPoint(time);
		self.interpolation.updatePosition(&position, &velocity, time);
	}
};

pub const updatesPerSec: u32 = 20;
const updateNanoTime: u32 = 1000000000/20;

pub var world: ?*ServerWorld = null;
pub var users: main.List(*User) = undefined;
pub var userDeinitList: main.List(*User) = undefined;

pub var connectionManager: *ConnectionManager = undefined;

var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var lastTime: i128 = undefined;

pub var mutex: std.Thread.Mutex = .{};

pub var thread: ?std.Thread = null;

fn init(name: []const u8) void {
	std.debug.assert(world == null); // There can only be one world.
	users = main.List(*User).init(main.globalAllocator);
	userDeinitList = main.List(*User).init(main.globalAllocator);
	lastTime = std.time.nanoTimestamp();
	connectionManager = ConnectionManager.init(main.settings.defaultPort, false) catch |err| {
		std.log.err("Couldn't create socket: {s}", .{@errorName(err)});
		@panic("Could not open Server.");
	}; // TODO Configure the second argument in the server settings.
	// TODO: Load the assets.

	world = ServerWorld.init(name, null) catch |err| {
		std.log.err("Failed to create world: {s}", .{@errorName(err)});
		@panic("Can't create world.");
	};
	if(true) blk: { // singleplayer // TODO: Configure this in the server settings.
		const user = User.init(connectionManager, "127.0.0.1:47650") catch |err| {
			std.log.err("Cannot create singleplayer user {s}", .{@errorName(err)});
			break :blk;
		};
		user.isLocal = true;
	}
}

fn deinit() void {
	for(users.items) |user| {
		user.deinit();
	}
	users.clearAndFree();
	for(userDeinitList.items) |user| {
		user.deinit();
	}
	userDeinitList.clearAndFree();
	connectionManager.deinit();
	connectionManager = undefined;

	if(world) |_world| {
		_world.deinit();
	}
	world = null;
}

fn update() void {
	world.?.update();
	mutex.lock();
	for(users.items) |user| {
		user.update();
	}
	mutex.unlock();

	const data = main.stackAllocator.alloc(u8, (4 + 24 + 12 + 24)*users.items.len);
	defer main.stackAllocator.free(data);
	var remaining = data;
	for(users.items) |user| {
		const id = user.id; // TODO
		std.mem.writeInt(u32, remaining[0..4], id, .big);
		remaining = remaining[4..];
		std.mem.writeInt(u64, remaining[0..8], @bitCast(user.player.pos[0]), .big);
		std.mem.writeInt(u64, remaining[8..16], @bitCast(user.player.pos[1]), .big);
		std.mem.writeInt(u64, remaining[16..24], @bitCast(user.player.pos[2]), .big);
		std.mem.writeInt(u32, remaining[24..28], @bitCast(user.player.rot[0]), .big);
		std.mem.writeInt(u32, remaining[28..32], @bitCast(user.player.rot[1]), .big);
		std.mem.writeInt(u32, remaining[32..36], @bitCast(user.player.rot[2]), .big);
		remaining = remaining[36..];
		std.mem.writeInt(u64, remaining[0..8], @bitCast(user.player.vel[0]), .big);
		std.mem.writeInt(u64, remaining[8..16], @bitCast(user.player.vel[1]), .big);
		std.mem.writeInt(u64, remaining[16..24], @bitCast(user.player.vel[2]), .big);
		remaining = remaining[24..];
	}
	for(users.items) |user| {
		main.network.Protocols.entityPosition.send(user.conn, data, &.{});
	}
	while(userDeinitList.popOrNull()) |user| {
		user.deinit();
	}
}

pub fn start(name: []const u8) void {
	var sta = utils.StackAllocator.init(main.globalAllocator, 1 << 23);
	defer sta.deinit();
	main.stackAllocator = sta.allocator();
	std.debug.assert(!running.load(.monotonic)); // There can only be one server.
	init(name);
	defer deinit();
	running.store(true, .monotonic);
	while(running.load(.monotonic)) {
		const newTime = std.time.nanoTimestamp();
		if(newTime -% lastTime < updateNanoTime) {
			std.time.sleep(@intCast(lastTime +% updateNanoTime -% newTime));
			lastTime +%= updateNanoTime;
		} else {
			std.log.warn("The server is lagging behind by {d:.1} ms", .{@as(f32, @floatFromInt(newTime -% lastTime -% updateNanoTime))/1000000.0});
			lastTime = newTime;
		}
		update();

	}
}

pub fn stop() void {
	running.store(false, .monotonic);
}

pub fn disconnect(user: *User) void {
	// TODO: world.forceSave();
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, "{s} #ffff00left", .{user.name}) catch unreachable;
	defer main.stackAllocator.free(message);
	mutex.lock();
	defer mutex.unlock();

	for(users.items, 0..) |other, i| {
		if(other == user) {
			_ = users.swapRemove(i);
			break;
		}
	}
	sendMessage(message);
	// Let the other clients know about that this new one left.
	const jsonArray = main.JsonElement.initArray(main.stackAllocator);
	defer jsonArray.free(main.stackAllocator);
	jsonArray.JsonArray.append(.{.JsonInt = user.id});
	const data = jsonArray.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(data);
	for(users.items) |other| {
		main.network.Protocols.entity.send(other.conn, data);
	}
	userDeinitList.append(user);
}

var freeId: u32 = 0;
pub fn connect(user: *User) void {
	// TODO: addEntity(player);
	user.id = freeId;
	freeId += 1;
	// Let the other clients know about this new one.
	{
		const jsonArray = main.JsonElement.initArray(main.stackAllocator);
		defer jsonArray.free(main.stackAllocator);
		const entityJson = main.JsonElement.initObject(main.stackAllocator);
		entityJson.put("id", user.id);
		entityJson.put("name", user.name);
		jsonArray.JsonArray.append(entityJson);
		const data = jsonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		for(users.items) |other| {
			main.network.Protocols.entity.send(other.conn, data);
		}
	}
	{ // Let this client know about the others:
		const jsonArray = main.JsonElement.initArray(main.stackAllocator);
		defer jsonArray.free(main.stackAllocator);
		for(users.items) |other| {
			const entityJson = main.JsonElement.initObject(main.stackAllocator);
			entityJson.put("id", other.id);
			entityJson.put("name", other.name);
			jsonArray.JsonArray.append(entityJson);
		}
		const data = jsonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		main.network.Protocols.entity.send(user.conn, data);

	}
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, "{s} #ffff00joined", .{user.name}) catch unreachable;
	defer main.stackAllocator.free(message);
	mutex.lock();
	defer mutex.unlock();
	sendMessage(message);

	users.append(user);
}

pub fn sendMessage(msg: []const u8) void {
	main.utils.assertLocked(&mutex);
	std.log.info("Chat: {s}", .{msg}); // TODO use color \033[0;32m
	for(users.items) |user| {
		main.network.Protocols.chat.send(user.conn, msg);
	}
}