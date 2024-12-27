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
		main.utils.assertLocked(&mutex);
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% main.settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		self.interpolation.update(time, self.lastTime);
		self.lastTime = time;
		self.loadUnloadChunks();
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

	pub fn sendMessage(user: *User, msg: []const u8) void {
		main.network.Protocols.chat.send(user.conn, msg);
	}
};

pub const updatesPerSec: u32 = 20;
const updateNanoTime: u32 = 1000000000/20;

pub var world: ?*ServerWorld = null;
pub var users: main.List(*User) = undefined;
pub var userDeinitList: main.List(*User) = undefined;

pub var connectionManager: *ConnectionManager = undefined;

pub var running: std.atomic.Value(bool) = .init(false);
var lastTime: i128 = undefined;

pub var mutex: std.Thread.Mutex = .{};

pub var thread: ?std.Thread = null;

fn init(name: []const u8, singlePlayerPort: ?u16) void { // MARK: init()
	std.debug.assert(world == null); // There can only be one world.
	command.init();
	users = .init(main.globalAllocator);
	userDeinitList = .init(main.globalAllocator);
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
	for(userDeinitList.items) |user| {
		user.deinit();
	}
	userDeinitList.clearAndFree();
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

fn sendEntityUpdates(comptime getInitialList: bool, allocator: utils.NeverFailingAllocator) if(getInitialList) []const u8 else void {
	// Send the entity updates:
	const updateList = main.ZonElement.initArray(main.stackAllocator);
	defer updateList.free(main.stackAllocator);
	defer updateList.array.clearAndFree(); // The children are freed in other locations.
	world.?.itemDropManager.mutex.lock();
	if(world.?.itemDropManager.lastUpdates.array.items.len != 0) {
		updateList.array.append(.null);
		updateList.array.appendSlice(world.?.itemDropManager.lastUpdates.array.items);
	}
	if(!getInitialList and updateList.array.items.len == 0) {
		world.?.itemDropManager.mutex.unlock();
		return;
	}
	const updateData = updateList.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(updateData);
	if(world.?.itemDropManager.lastUpdates.array.items.len != 0) {
		const alloc = world.?.itemDropManager.lastUpdates.array.allocator;
		world.?.itemDropManager.lastUpdates.free(alloc);
		world.?.itemDropManager.lastUpdates = main.ZonElement.initArray(alloc);
	}
	var initialList: []const u8 = undefined;
	if(getInitialList) {
		const list = main.ZonElement.initArray(main.stackAllocator);
		defer list.free(main.stackAllocator);
		list.array.append(.null);
		const itemDropList = world.?.itemDropManager.getInitialList(main.stackAllocator);
		list.array.appendSlice(itemDropList.array.items);
		itemDropList.array.items.len = 0;
		itemDropList.free(main.stackAllocator);
		initialList = list.toStringEfficient(allocator, &.{});
	}
	world.?.itemDropManager.mutex.unlock();
	mutex.lock();
	for(users.items) |user| {
		main.network.Protocols.entity.send(user.conn, updateData);
	}
	mutex.unlock();
	if(getInitialList) {
		return initialList;
	}
}

fn update() void { // MARK: update()
	world.?.update();
	mutex.lock();
	for(users.items) |user| {
		user.update();
	}
	mutex.unlock();

	sendEntityUpdates(false, main.stackAllocator);


	// Send the entity data:
	const data = main.stackAllocator.alloc(u8, (4 + 24 + 12 + 24)*users.items.len);
	defer main.stackAllocator.free(data);
	const itemData = world.?.itemDropManager.getPositionAndVelocityData(main.stackAllocator);
	defer main.stackAllocator.free(itemData);
	var remaining = data;
	mutex.lock();
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
		main.network.Protocols.entityPosition.send(user.conn, data, itemData);
	}

	while(userDeinitList.popOrNull()) |user| {
		mutex.unlock();
		user.decreaseRefCount();
		mutex.lock();
	}
	mutex.unlock();
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
	userDeinitList.append(user);
	user.connected.store(false, .unordered);
}

pub fn removePlayer(user: *User) void { // MARK: removePlayer()
	if(!user.connected.load(.unordered)) return;
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}§#ffff00 left", .{user.name}) catch unreachable;
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
	const zonArray = main.ZonElement.initArray(main.stackAllocator);
	defer zonArray.free(main.stackAllocator);
	zonArray.array.append(.{.int = user.id});
	const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(data);
	for(users.items) |other| {
		main.network.Protocols.entity.send(other.conn, data);
	}
}

var freeId: u32 = 0;
pub fn connect(user: *User) void {
	// TODO: addEntity(player);
	user.id = freeId;
	freeId += 1;
	// Let the other clients know about this new one.
	{
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.free(main.stackAllocator);
		const entityZon = main.ZonElement.initObject(main.stackAllocator);
		entityZon.put("id", user.id);
		entityZon.put("name", user.name);
		zonArray.array.append(entityZon);
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		mutex.lock();
		defer mutex.unlock();
		for(users.items) |other| {
			main.network.Protocols.entity.send(other.conn, data);
		}
	}
	{ // Let this client know about the others:
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.free(main.stackAllocator);
		mutex.lock();
		for(users.items) |other| {
			const entityZon = main.ZonElement.initObject(main.stackAllocator);
			entityZon.put("id", other.id);
			entityZon.put("name", other.name);
			zonArray.array.append(entityZon);
		}
		mutex.unlock();
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		if(user.connected.load(.unordered)) main.network.Protocols.entity.send(user.conn, data);

	}
	const initialList = sendEntityUpdates(true, main.stackAllocator);
	main.network.Protocols.entity.send(user.conn, initialList);
	main.stackAllocator.free(initialList);
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}§#ffff00 joined", .{user.name}) catch unreachable;
	defer main.stackAllocator.free(message);
	mutex.lock();
	defer mutex.unlock();
	sendMessage(message);

	users.append(user);
}

pub fn messageFrom(msg: []const u8, source: *User) void { // MARK: message
	if(msg[0] == '/') { // Command.
		std.log.info("User \"{s}\" executed command \"{s}\"", .{source.name, msg}); // TODO use color \033[0;32m
		command.execute(msg[1..], source);
	} else {
		const newMessage = std.fmt.allocPrint(main.stackAllocator.allocator, "[{s}§#ffffff] {s}", .{source.name, msg}) catch unreachable;
		defer main.stackAllocator.free(newMessage);
		main.server.mutex.lock();
		defer main.server.mutex.unlock();
		main.server.sendMessage(newMessage);
	}
}

pub fn sendMessage(msg: []const u8) void {
	main.utils.assertLocked(&mutex);
	std.log.info("Chat: {s}", .{msg}); // TODO use color \033[0;32m
	for(users.items) |user| {
		user.sendMessage(msg);
	}
}