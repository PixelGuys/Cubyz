const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const chunk = main.chunk;
const network = main.network;
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3i = vec.Vec3i;

pub const ServerWorld = @import("world.zig").ServerWorld;
pub const terrain = @import("terrain/terrain.zig");
pub const Entity = @import("Entity.zig");
pub const storage = @import("storage.zig");

const command = @import("command/_command.zig");


pub const User = struct { // MARK: User
	const maxSimulationDistance = 8;
	const simulationSize = 2*maxSimulationDistance;
	const simulationMask = simulationSize - 1;
	conn: *Connection = undefined,
	player: Entity = .{},
	timeDifference: utils.TimeDifference = .{},
	interpolation: utils.GenericInterpolation(3) = undefined,
	lastTime: i16 = undefined,
	lastSaveTime: i64 = 0,
	name: []const u8 = "",
	renderDistance: u16 = undefined,
	clientUpdatePos: Vec3i = .{0, 0, 0},
	receivedFirstEntityData: bool = false,
	isLocal: bool = false,
	id: u32 = 0, // TODO: Use entity id.
	// TODO: ipPort: []const u8,
	loadedChunks: [simulationSize][simulationSize][simulationSize]*@import("world.zig").EntityChunk = undefined,
	lastRenderDistance: u16 = 0,
	lastPos: Vec3i = @splat(0),
	gamemode: std.atomic.Value(main.game.Gamemode) = .init(.creative),

	inventoryClientToServerIdMap: std.AutoHashMap(u32, u32) = undefined,

	connected: Atomic(bool) = .init(true),

	refCount: Atomic(u32) = .init(1),

	mutex: std.Thread.Mutex = .{},

	pub fn initAndIncreaseRefCount(manager: *ConnectionManager, ipPort: []const u8) !*User {
		const self = main.globalAllocator.create(User);
		errdefer main.globalAllocator.destroy(self);
		self.* = .{};
		self.inventoryClientToServerIdMap = .init(main.globalAllocator.allocator);
		self.interpolation.init(@ptrCast(&self.player.pos), @ptrCast(&self.player.vel));
		self.conn = try Connection.init(manager, ipPort, self);
		self.increaseRefCount();
		network.Protocols.handShake.serverSide(self.conn);
		return self;
	}

	pub fn reinitialize(self: *User) void {
		removePlayer(self);
		self.timeDifference = .{};
		main.globalAllocator.free(self.name);
		self.name = "";
	}

	pub fn deinit(self: *User) void {
		std.debug.assert(self.refCount.load(.monotonic) == 0);
		main.items.Inventory.Sync.ServerSide.disconnectUser(self);
		std.debug.assert(self.inventoryClientToServerIdMap.count() == 0); // leak
		self.inventoryClientToServerIdMap.deinit();
		self.unloadOldChunk(.{0, 0, 0}, 0);
		self.conn.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}

	pub fn increaseRefCount(self: *User) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *User) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			self.deinit();
		}
	}

	pub fn initPlayer(self: *User, name: []const u8) void {
		self.name = main.globalAllocator.dupe(u8, name);
		world.?.findPlayer(self);
	}

	fn simArrIndex(x: i32) usize {
		return @intCast(x >> chunk.chunkShift & simulationMask);
	}

	fn unloadOldChunk(self: *User, newPos: Vec3i, newRenderDistance: u16) void {
		const lastBoxStart = (self.lastPos -% @as(Vec3i, @splat(self.lastRenderDistance*chunk.chunkSize))) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const lastBoxEnd = (self.lastPos +% @as(Vec3i, @splat(self.lastRenderDistance*chunk.chunkSize))) +% @as(Vec3i, @splat(chunk.chunkSize - 1)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newBoxStart = (newPos -% @as(Vec3i, @splat(newRenderDistance*chunk.chunkSize))) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newBoxEnd = (newPos +% @as(Vec3i, @splat(newRenderDistance*chunk.chunkSize))) +% @as(Vec3i, @splat(chunk.chunkSize - 1)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		// Clear all chunks not inside the new box:
		var x: i32 = lastBoxStart[0];
		while(x != lastBoxEnd[0]) : (x +%= chunk.chunkSize) {
			const inXDistance = x -% newBoxStart[0] >= 0 and x -% newBoxEnd[0] < 0;
			var y: i32 = lastBoxStart[1];
			while(y != lastBoxEnd[1]) : (y +%= chunk.chunkSize) {
				const inYDistance = y -% newBoxStart[1] >= 0 and y -% newBoxEnd[1] < 0;
				var z: i32 = lastBoxStart[2];
				while(z != lastBoxEnd[2]) : (z +%= chunk.chunkSize) {
					const inZDistance = z -% newBoxStart[2] >= 0 and z -% newBoxEnd[2] < 0;
					if(!inXDistance or !inYDistance or !inZDistance) {
						self.loadedChunks[simArrIndex(x)][simArrIndex(y)][simArrIndex(z)].decreaseRefCount();
						self.loadedChunks[simArrIndex(x)][simArrIndex(y)][simArrIndex(z)] = undefined;
					}
				}
			}
		}
	}

	fn loadNewChunk(self: *User, newPos: Vec3i, newRenderDistance: u16) void {
		const lastBoxStart = (self.lastPos -% @as(Vec3i, @splat(self.lastRenderDistance*chunk.chunkSize))) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const lastBoxEnd = (self.lastPos +% @as(Vec3i, @splat(self.lastRenderDistance*chunk.chunkSize))) +% @as(Vec3i, @splat(chunk.chunkSize - 1)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newBoxStart = (newPos -% @as(Vec3i, @splat(newRenderDistance*chunk.chunkSize))) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newBoxEnd = (newPos +% @as(Vec3i, @splat(newRenderDistance*chunk.chunkSize))) +% @as(Vec3i, @splat(chunk.chunkSize - 1)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		// Clear all chunks not inside the new box:
		var x: i32 = newBoxStart[0];
		while(x != newBoxEnd[0]) : (x +%= chunk.chunkSize) {
			const inXDistance = x -% lastBoxStart[0] >= 0 and x -% lastBoxEnd[0] < 0;
			var y: i32 = newBoxStart[1];
			while(y != newBoxEnd[1]) : (y +%= chunk.chunkSize) {
				const inYDistance = y -% lastBoxStart[1] >= 0 and y -% lastBoxEnd[1] < 0;
				var z: i32 = newBoxStart[2];
				while(z != newBoxEnd[2]) : (z +%= chunk.chunkSize) {
					const inZDistance = z -% lastBoxStart[2] >= 0 and z -% lastBoxEnd[2] < 0;
					if(!inXDistance or !inYDistance or !inZDistance) {
						self.loadedChunks[simArrIndex(x)][simArrIndex(y)][simArrIndex(z)] = @TypeOf(world.?.chunkManager).getOrGenerateEntityChunkAndIncreaseRefCount(.{.wx = x, .wy = y, .wz = z, .voxelSize = 1});
					}
				}
			}
		}
	}

	fn loadUnloadChunks(self: *User) void {
		const newPos: Vec3i = @as(Vec3i, @intFromFloat(self.player.pos)) +% @as(Vec3i, @splat(chunk.chunkSize/2)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newRenderDistance = main.settings.simulationDistance;
		if(@reduce(.Or, newPos != self.lastPos) or newRenderDistance != self.lastRenderDistance) {
			self.unloadOldChunk(newPos, newRenderDistance);
			self.loadNewChunk(newPos, newRenderDistance);
			self.lastRenderDistance = newRenderDistance;
			self.lastPos = newPos;
		}
	}

	pub fn update(self: *User) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% main.settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		self.interpolation.update(time, self.lastTime);
		self.lastTime = time;

		const saveTime = std.time.milliTimestamp();
		if (saveTime -% self.lastSaveTime > 5000) {
			world.?.savePlayer(self) catch |err| {
				std.log.err("Failed to save player {s}: {s}", .{self.name, @errorName(err)});
			};
			self.lastSaveTime = saveTime;
		}

		self.loadUnloadChunks();
	}

	pub fn receiveData(self: *User, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();
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

	pub fn sendMessage(self: *User, comptime fmt: []const u8, args: anytype) void {
		const msg = std.fmt.allocPrint(main.stackAllocator.allocator, fmt, args) catch unreachable;
		defer main.stackAllocator.free(msg);
		self.sendRawMessage(msg);
	}
	fn sendRawMessage(self: *User, msg: []const u8) void {
		main.network.Protocols.chat.send(self.conn, msg);
	}
};

pub const updatesPerSec: u32 = 20;
const updateNanoTime: u32 = 1000000000/20;

pub var world: ?*ServerWorld = null;
var userMutex: std.Thread.Mutex = .{};
var users: main.List(*User) = undefined;
var userDeinitList: main.utils.ConcurrentQueue(*User) = undefined;
var userConnectList: main.utils.ConcurrentQueue(*User) = undefined;

pub var connectionManager: *ConnectionManager = undefined;

pub var running: std.atomic.Value(bool) = .init(false);
var lastTime: i128 = undefined;

pub var thread: ?std.Thread = null;

fn init(name: []const u8, singlePlayerPort: ?u16) void { // MARK: init()
	std.debug.assert(world == null); // There can only be one world.
	command.init();
	users = .init(main.globalAllocator);
	userDeinitList = .init(main.globalAllocator, 16);
	userConnectList = .init(main.globalAllocator, 16);
	lastTime = std.time.nanoTimestamp();
	connectionManager = ConnectionManager.init(main.settings.defaultPort, false) catch |err| {
		std.log.err("Couldn't create socket: {s}", .{@errorName(err)});
		@panic("Could not open Server.");
	}; // TODO Configure the second argument in the server settings.

	main.items.Inventory.Sync.ServerSide.init();

	world = ServerWorld.init(name, null) catch |err| {
		std.log.err("Failed to create world: {s}", .{@errorName(err)});
		@panic("Can't create world.");
	};
	world.?.generate() catch |err| {
		std.log.err("Failed to generate world: {s}", .{@errorName(err)});
		@panic("Can't generate world.");
	};
	if(singlePlayerPort) |port| blk: {
		const ipString = std.fmt.allocPrint(main.stackAllocator.allocator, "127.0.0.1:{}", .{port}) catch unreachable;
		defer main.stackAllocator.free(ipString);
		const user = User.initAndIncreaseRefCount(connectionManager, ipString) catch |err| {
			std.log.err("Cannot create singleplayer user {s}", .{@errorName(err)});
			break :blk;
		};
		defer user.decreaseRefCount();
		user.isLocal = true;
	}
}

fn deinit() void {
	users.clearAndFree();
	while(userDeinitList.dequeue()) |user| {
		user.deinit();
	}
	userDeinitList.deinit();
	userConnectList.deinit();
	for(connectionManager.connections.items) |conn| {
		conn.user.?.decreaseRefCount();
	}
	connectionManager.deinit();
	connectionManager = undefined;

	main.items.Inventory.Sync.ServerSide.deinit();

	if(world) |_world| {
		_world.deinit();
	}
	world = null;
	command.deinit();
}

pub fn getUserListAndIncreaseRefCount(allocator: utils.NeverFailingAllocator) []*User {
	userMutex.lock();
	defer userMutex.unlock();
	const result = allocator.dupe(*User, users.items);
	for(result) |user| {
		user.increaseRefCount();
	}
	return result;
}

pub fn freeUserListAndDecreaseRefCount(allocator: utils.NeverFailingAllocator, list: []*User) void {
	for(list) |user| {
		user.decreaseRefCount();
	}
	allocator.free(list);
}

fn getInitialEntityList(allocator: utils.NeverFailingAllocator) []const u8 {
	// Send the entity updates:
	var initialList: []const u8 = undefined;
	const list = main.ZonElement.initArray(main.stackAllocator);
	defer list.deinit(main.stackAllocator);
	list.array.append(.null);
	const itemDropList = world.?.itemDropManager.getInitialList(main.stackAllocator);
	list.array.appendSlice(itemDropList.array.items);
	itemDropList.array.items.len = 0;
	itemDropList.deinit(main.stackAllocator);
	initialList = list.toStringEfficient(allocator, &.{});
	return initialList;
}

fn update() void { // MARK: update()
	world.?.update();

	while(userConnectList.dequeue()) |user| {
		connectInternal(user);
	}

	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for(userList) |user| {
		user.update();
	}

	// Send the entity data:
	const data = main.stackAllocator.alloc(u8, (4 + 24 + 12 + 24)*userList.len);
	defer main.stackAllocator.free(data);
	const itemData = world.?.itemDropManager.getPositionAndVelocityData(main.stackAllocator);
	defer main.stackAllocator.free(itemData);
	var remaining = data;
	for(userList) |user| {
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
	for(userList) |user| {
		main.network.Protocols.entityPosition.send(user.conn, data, itemData);
	}

	while(userDeinitList.dequeue()) |user| {
		user.decreaseRefCount();
	}
}

pub fn start(name: []const u8, port: ?u16) void {
	var sta = utils.StackAllocator.init(main.globalAllocator, 1 << 23);
	defer sta.deinit();
	main.stackAllocator = sta.allocator();
	std.debug.assert(!running.load(.monotonic)); // There can only be one server.
	init(name, port);
	defer deinit();
	running.store(true, .release);
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

pub fn disconnect(user: *User) void { // MARK: disconnect()
	if(!user.connected.load(.unordered)) return;
	removePlayer(user);
	userDeinitList.enqueue(user);
	user.connected.store(false, .unordered);
}

pub fn removePlayer(user: *User) void { // MARK: removePlayer()
	if(!user.connected.load(.unordered)) return;

	userMutex.lock();
	for(users.items, 0..) |other, i| {
		if(other == user) {
			_ = users.swapRemove(i);
			break;
		}
	}
	userMutex.unlock();

	sendMessage("{s}§#ffff00 left", .{user.name});
	// Let the other clients know about that this new one left.
	const zonArray = main.ZonElement.initArray(main.stackAllocator);
	defer zonArray.deinit(main.stackAllocator);
	zonArray.array.append(.{.int = user.id});
	const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(data);
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for(userList) |other| {
		main.network.Protocols.entity.send(other.conn, data);
	}
}

pub fn connect(user: *User) void {
	userConnectList.enqueue(user);
}

var freeId: u32 = 0;
pub fn connectInternal(user: *User) void {
	// TODO: addEntity(player);
	user.id = freeId;
	freeId += 1;
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	// Let the other clients know about this new one.
	{
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.deinit(main.stackAllocator);
		const entityZon = main.ZonElement.initObject(main.stackAllocator);
		entityZon.put("id", user.id);
		entityZon.put("name", user.name);
		zonArray.array.append(entityZon);
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		for(userList) |other| {
			main.network.Protocols.entity.send(other.conn, data);
		}
	}
	{ // Let this client know about the others:
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.deinit(main.stackAllocator);
		for(userList) |other| {
			const entityZon = main.ZonElement.initObject(main.stackAllocator);
			entityZon.put("id", other.id);
			entityZon.put("name", other.name);
			zonArray.array.append(entityZon);
		}
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		if(user.connected.load(.unordered)) main.network.Protocols.entity.send(user.conn, data);
	}
	const initialList = getInitialEntityList(main.stackAllocator);
	main.network.Protocols.entity.send(user.conn, initialList);
	main.stackAllocator.free(initialList);
	sendMessage("{s}§#ffff00 joined", .{user.name});

	userMutex.lock();
	users.append(user);
	userMutex.unlock();
}

pub fn messageFrom(msg: []const u8, source: *User) void { // MARK: message
	if(msg[0] == '/') { // Command.
		if (world.?.allowCheats) {
			std.log.info("User \"{s}\" executed command \"{s}\"", .{source.name, msg}); // TODO use color \033[0;32m
			command.execute(msg[1..], source);
		} else {
			source.sendRawMessage("Commands are not allowed because cheats are disabled");
		}
	} else {
		main.server.sendMessage("[{s}§#ffffff] {s}", .{source.name, msg});
	}
}

fn sendRawMessage(msg: []const u8) void {
	chatMutex.lock();
	defer chatMutex.unlock();
	std.log.info("Chat: {s}", .{msg}); // TODO use color \033[0;32m
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for(userList) |user| {
		user.sendRawMessage(msg);
	}
}

var chatMutex: std.Thread.Mutex = .{};
pub fn sendMessage(comptime fmt: []const u8, args: anytype) void {
	const msg = std.fmt.allocPrint(main.stackAllocator.allocator, fmt, args) catch unreachable;
	defer main.stackAllocator.free(msg);
	sendRawMessage(msg);
}