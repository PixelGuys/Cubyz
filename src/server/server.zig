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

pub const BlockUpdateSystem = @import("BlockUpdateSystem.zig");
pub const world_zig = @import("world.zig");
pub const ServerWorld = world_zig.ServerWorld;
pub const terrain = @import("terrain/terrain.zig");
pub const Entity = @import("Entity.zig");
pub const SimulationChunk = @import("SimulationChunk.zig");
pub const storage = @import("storage.zig");
pub const permission = @import("permission.zig");

pub const command = @import("command/_command.zig");

pub const WorldEditData = struct {
	const maxWorldEditHistoryCapacity: u32 = 1024;

	selectionPosition1: ?Vec3i = null,
	selectionPosition2: ?Vec3i = null,
	clipboard: ?Blueprint = null,
	undoHistory: History,
	redoHistory: History,
	mask: ?Mask = null,

	const History = struct {
		changes: CircularBufferQueue(Value),

		const Value = struct {
			blueprint: Blueprint,
			position: Vec3i,
			message: []const u8,

			pub fn init(blueprint: Blueprint, position: Vec3i, message: []const u8) Value {
				return .{.blueprint = blueprint, .position = position, .message = main.globalAllocator.dupe(u8, message)};
			}
			pub fn deinit(self: Value) void {
				main.globalAllocator.free(self.message);
				self.blueprint.deinit(main.globalAllocator);
			}
		};
		pub fn init() History {
			return .{.changes = .init(main.globalAllocator, maxWorldEditHistoryCapacity)};
		}
		pub fn deinit(self: *History) void {
			self.clear();
			self.changes.deinit();
		}
		pub fn clear(self: *History) void {
			while (self.changes.popFront()) |item| item.deinit();
		}
		pub fn push(self: *History, value: Value) void {
			if (self.changes.reachedCapacity()) {
				if (self.changes.popFront()) |oldValue| oldValue.deinit();
			}

			self.changes.pushBack(value);
		}
		pub fn pop(self: *History) ?Value {
			return self.changes.popBack();
		}
	};
	pub fn init() WorldEditData {
		return .{.undoHistory = History.init(), .redoHistory = History.init()};
	}
	pub fn deinit(self: *WorldEditData) void {
		if (self.clipboard != null) {
			self.clipboard.?.deinit(main.globalAllocator);
		}
		self.undoHistory.deinit();
		self.redoHistory.deinit();
		if (self.mask) |mask| {
			mask.deinit(main.globalAllocator);
		}
	}
};

pub const User = struct { // MARK: User
	const maxSimulationDistance = 8;
	const simulationSize = 2*maxSimulationDistance;
	const simulationMask = simulationSize - 1;
	conn: *Connection = undefined,
	player: Entity = .{},
	timeDifference: utils.TimeDifference = .{},
	interpolation: utils.GenericInterpolation(3) = undefined,
	lastTime: i16 = undefined,
	lastSaveTime: std.Io.Timestamp = .fromNanoseconds(0),
	name: []const u8 = "",
	renderDistance: u16 = undefined,
	clientUpdatePos: Vec3i = .{0, 0, 0},
	receivedFirstEntityData: bool = false,
	isLocal: bool = false,
	id: u32 = 0, // TODO: Use entity id.
	// TODO: ipPort: []const u8,
	loadedChunks: [simulationSize][simulationSize][simulationSize]*SimulationChunk = undefined,
	lastRenderDistance: u16 = 0,
	lastPos: Vec3i = @splat(0),
	gamemode: std.atomic.Value(main.game.Gamemode) = .init(.creative),
	spawnPos: Vec3d = .{0, 0, 0},
	worldEditData: WorldEditData = undefined,

	playerIndex: usize = undefined,

	jobQueue: main.utils.ConcurrentMaxHeap(main.utils.ThreadPool.Task) = undefined,
	jobQueueScheduled: bool = false,
	jobQueueLastUpdate: struct { position: Vec3i, time: std.Io.Timestamp, alreadyInUpdate: bool = false } = .{.position = @splat(0), .time = .{.nanoseconds = 0}},

	lastSentBiomeId: u32 = 0xffffffff,

	newKeyString: []const u8 = &.{},
	key: network.authentication.PublicKey = undefined,
	legacyKey: ?network.authentication.PublicKey = null,

	inventoryClientToServerIdMap: std.AutoHashMap(InventoryId, InventoryId) = undefined,
	inventory: ?InventoryId = null,
	handInventory: ?InventoryId = null,

	connected: Atomic(bool) = .init(true),

	refCount: Atomic(u32) = .init(1),

	mutex: std.Thread.Mutex = .{},

	inventoryCommands: main.ListUnmanaged([]const u8) = .{},

	permissions: permission.Permissions = undefined,

	pub fn initAndIncreaseRefCount(manager: *ConnectionManager, ipPort: []const u8) !*User {
		const self = main.globalAllocator.create(User);
		errdefer main.globalAllocator.destroy(self);
		self.* = .{};
		self.inventoryClientToServerIdMap = .init(main.globalAllocator.allocator);
		self.jobQueue = .init(main.globalAllocator);
		self.conn = try Connection.init(manager, ipPort, self);
		self.increaseRefCount();
		self.worldEditData = .init();
		self.permissions = .init(main.globalAllocator);
		network.protocols.handShake.serverSide(self.conn);
		return self;
	}

	pub fn deinit(self: *User) void {
		std.debug.assert(self.refCount.load(.monotonic) == 0);

		main.items.Inventory.ServerSide.disconnectUser(self);
		std.debug.assert(self.inventoryClientToServerIdMap.count() == 0); // leak
		self.inventoryClientToServerIdMap.deinit();

		if (self.inventory != null) {
			world.?.savePlayer(self) catch |err| {
				std.log.err("Failed to save player: {s}", .{@errorName(err)});
				return;
			};

			main.items.Inventory.ServerSide.destroyExternallyManagedInventory(self.inventory.?);
			main.items.Inventory.ServerSide.destroyExternallyManagedInventory(self.handInventory.?);
		}

		self.permissions.deinit();

		self.worldEditData.deinit();

		self.unloadOldChunk(.{0, 0, 0}, 0);
		self.conn.deinit();
		self.jobQueue.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.free(self.newKeyString);
		for (self.inventoryCommands.items) |commandData| {
			main.globalAllocator.free(commandData);
		}
		self.inventoryCommands.deinit(main.globalAllocator);
		main.globalAllocator.destroy(self);
	}

	pub fn increaseRefCount(self: *User) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *User) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if (prevVal == 1) {
			self.deinit();
		}
	}

	pub fn identifyFromKeysAndName(self: *User, name: []const u8, keys: main.ZonElement) !void {
		std.debug.assert(self.name.len == 0);
		self.name = main.globalAllocator.dupe(u8, name);
		{
			const keyBase64 = keys.get(?[]const u8, @tagName(main.settings.launchConfig.preferredAuthenticationAlgorithm), null) orelse return error.PublicKeyNotPresent;
			self.key = try .initFromBase64(keyBase64, main.settings.launchConfig.preferredAuthenticationAlgorithm);
			self.newKeyString = std.fmt.allocPrint(main.globalAllocator.allocator, "{s}:{s}", .{@tagName(main.settings.launchConfig.preferredAuthenticationAlgorithm), keyBase64}) catch unreachable;
		}
		var foundKey: bool = false;
		for (std.meta.fieldNames(main.network.authentication.KeyTypeEnum)) |keyTypeName| {
			const keyBase64 = keys.get(?[]const u8, keyTypeName, null) orelse continue;
			const keyWithType = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}:{s}", .{keyTypeName, keyBase64}) catch unreachable;
			defer main.stackAllocator.free(keyWithType);
			self.playerIndex = world.?.playerDatabase.get(keyWithType) orelse continue;
			foundKey = true;
			const keyType = std.meta.stringToEnum(main.network.authentication.KeyTypeEnum, keyTypeName) orelse unreachable;
			if (keyType == self.key) break;
			self.legacyKey = try .initFromBase64(keyBase64, keyType);
			break;
		}
		if (!foundKey) {
			const nameEntry = std.fmt.allocPrint(main.stackAllocator.allocator, "name:{s}", .{name}) catch unreachable;
			defer main.stackAllocator.free(nameEntry);
			self.playerIndex = world.?.playerDatabase.get(nameEntry) orelse world.?.nextPlayerIndex.fetchAdd(1, .monotonic);
		}
	}

	pub fn verifySignatures(self: *User, reader: *BinaryReader) !void {
		try self.key.verifySignature(reader, self.conn.secureChannel.verificationDataForClientSignature.items);
		if (self.legacyKey) |key| {
			try key.verifySignature(reader, self.conn.secureChannel.verificationDataForClientSignature.items);
		}
	}

	var freeId: u32 = 0;
	pub fn initPlayer(self: *User) void {
		self.id = freeId;
		freeId += 1;

		world.?.loadPlayer(self);
		self.interpolation.init(@ptrCast(&self.player.pos), @ptrCast(&self.player.vel));
		self.loadUnloadChunks();
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
		while (x != lastBoxEnd[0]) : (x +%= chunk.chunkSize) {
			const inXDistance = x -% newBoxStart[0] >= 0 and x -% newBoxEnd[0] < 0;
			var y: i32 = lastBoxStart[1];
			while (y != lastBoxEnd[1]) : (y +%= chunk.chunkSize) {
				const inYDistance = y -% newBoxStart[1] >= 0 and y -% newBoxEnd[1] < 0;
				var z: i32 = lastBoxStart[2];
				while (z != lastBoxEnd[2]) : (z +%= chunk.chunkSize) {
					const inZDistance = z -% newBoxStart[2] >= 0 and z -% newBoxEnd[2] < 0;
					if (!inXDistance or !inYDistance or !inZDistance) {
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
		while (x != newBoxEnd[0]) : (x +%= chunk.chunkSize) {
			const inXDistance = x -% lastBoxStart[0] >= 0 and x -% lastBoxEnd[0] < 0;
			var y: i32 = newBoxStart[1];
			while (y != newBoxEnd[1]) : (y +%= chunk.chunkSize) {
				const inYDistance = y -% lastBoxStart[1] >= 0 and y -% lastBoxEnd[1] < 0;
				var z: i32 = newBoxStart[2];
				while (z != newBoxEnd[2]) : (z +%= chunk.chunkSize) {
					const inZDistance = z -% lastBoxStart[2] >= 0 and z -% lastBoxEnd[2] < 0;
					if (!inXDistance or !inYDistance or !inZDistance) {
						self.loadedChunks[simArrIndex(x)][simArrIndex(y)][simArrIndex(z)] = world_zig.ChunkManager.getOrGenerateSimulationChunkAndIncreaseRefCount(.{.wx = x, .wy = y, .wz = z, .voxelSize = 1});
					}
				}
			}
		}
	}

	fn loadUnloadChunks(self: *User) void {
		const newPos: Vec3i = @as(Vec3i, @intFromFloat(self.player.pos)) +% @as(Vec3i, @splat(chunk.chunkSize/2)) & ~@as(Vec3i, @splat(chunk.chunkMask));
		const newRenderDistance = main.settings.simulationDistance;
		if (@reduce(.Or, newPos != self.lastPos) or newRenderDistance != self.lastRenderDistance) {
			self.unloadOldChunk(newPos, newRenderDistance);
			self.loadNewChunk(newPos, newRenderDistance);
			self.lastRenderDistance = newRenderDistance;
			self.lastPos = newPos;
		}
	}

	pub fn getTaskFromJobQueue(self: *User) ?struct { main.utils.ThreadPool.Task, enum { hasMoreTasks, empty } } {
		self.mutex.lock();
		defer self.mutex.unlock();
		if (vec.lengthSquare(@as(@Vector(3, i64), self.jobQueueLastUpdate.position -% self.lastPos)) > 32*32) {
			const startTime = main.timestamp();
			if (self.jobQueueLastUpdate.time.durationTo(startTime).toMilliseconds() > 100 and !self.jobQueueLastUpdate.alreadyInUpdate) {
				const ResortTaskTask = struct { // MARK: ResortTaskTask
					const vtable = utils.ThreadPool.VTable{
						.getPriority = &getPriority,
						.isStillNeeded = &isStillNeeded,
						.run = main.meta.castFunctionSelfToAnyopaque(run),
						.clean = main.meta.castFunctionSelfToAnyopaque(clean),
						.taskType = .taskPriorityUpdate,
					};

					pub fn getPriority(_: *anyopaque) f32 {
						return undefined;
					}

					pub fn isStillNeeded(_: *anyopaque) bool {
						return true;
					}

					pub fn run(user: *User) void {
						defer user.decreaseRefCount();

						var newTasks: main.ListUnmanaged(main.utils.ThreadPool.Task) = .initCapacity(main.stackAllocator, user.jobQueue.size);
						defer newTasks.deinit(main.stackAllocator);
						while (user.jobQueue.extractAny()) |_task| {
							var task = _task;
							if (!task.vtable.isStillNeeded(task.self)) {
								task.vtable.clean(task.self);
								continue;
							}
							task.cachedPriority = task.vtable.getPriority(task.self);
							newTasks.append(main.stackAllocator, task);
						}
						user.jobQueue.addMany(newTasks.items);
						user.mutex.lock();
						defer user.mutex.unlock();
						user.jobQueueLastUpdate = .{
							.position = user.lastPos,
							.time = main.timestamp(),
						};
					}

					pub fn clean(user: *User) void {
						user.decreaseRefCount();
					}
				};
				// Create a task to resort tasks:
				self.jobQueueLastUpdate.alreadyInUpdate = true;
				self.increaseRefCount();
				return .{
					.{
						.cachedPriority = undefined,
						.vtable = &ResortTaskTask.vtable,
						.self = self,
					},
					.hasMoreTasks,
				};
			}
		}
		if (self.isNetworkQueueFull()) {
			self.jobQueueScheduled = false;
			return null;
		}
		const task = self.jobQueue.extractMax() orelse {
			self.jobQueueScheduled = false;
			return null;
		};
		if (self.jobQueue.size == 0) {
			self.jobQueueScheduled = false;
			return .{task, .empty};
		} else {
			return .{task, .hasMoreTasks};
		}
	}

	pub fn addTask(self: *User, task: *anyopaque, vtable: *const main.utils.ThreadPool.VTable) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.jobQueue.add(.{
			.cachedPriority = vtable.getPriority(task),
			.vtable = vtable,
			.self = task,
		});
	}

	fn isNetworkQueueFull(self: *User) bool {
		return self.conn.secureChannel.super.sendBuffer.buffer.len > 900000;
	}

	fn scheduleJobQueue(self: *User) void {
		main.utils.assertLocked(&self.mutex);
		if (self.jobQueueScheduled) return;
		if (self.jobQueue.size == 0) return;
		if (self.isNetworkQueueFull()) return;
		self.jobQueueScheduled = true;
		main.threadPool.addPlayer(self);
	}

	pub fn update(self: *User) void {
		self.mutex.lock();
		self.scheduleJobQueue();
		const commands = self.inventoryCommands;
		defer commands.deinit(main.globalAllocator);
		self.inventoryCommands = .{};
		self.mutex.unlock();

		for (commands.items) |commandData| {
			defer main.globalAllocator.free(commandData);
			var reader: BinaryReader = .init(commandData);
			main.sync.ServerSide.executeUserCommand(self, &reader) catch |err| {
				if (err == error.InventoryNotFound) {
					main.network.protocols.inventory.sendFailure(self.conn);
				} else {
					std.log.err("Got error while executing user command: {s}. Disconnecting.", .{@errorName(err)});
					std.log.debug("Command data: {any}", .{commandData});
					self.conn.disconnect();
				}
			};
		}

		self.mutex.lock();
		defer self.mutex.unlock();
		var time = @as(i16, @truncate(main.timestamp().toMilliseconds())) -% main.settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		self.interpolation.update(time, self.lastTime);
		self.lastTime = time;

		const saveTime = main.timestamp();
		if (self.lastSaveTime.durationTo(saveTime).toSeconds() > 5) {
			world.?.savePlayer(self) catch |err| {
				std.log.err("Failed to save player {s}: {s}", .{self.name, @errorName(err)});
			};
			self.lastSaveTime = saveTime;
		}

		self.loadUnloadChunks();
	}

	pub fn receiveCommand(self: *User, commandData: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.inventoryCommands.append(main.globalAllocator, main.globalAllocator.dupe(u8, commandData));
	}

	pub fn receiveData(self: *User, reader: *BinaryReader) !void {
		self.mutex.lock();
		defer self.mutex.unlock();
		const position: [3]f64 = try reader.readVec(Vec3d);
		const velocity: [3]f64 = try reader.readVec(Vec3d);
		const rotation: [3]f32 = try reader.readVec(Vec3f);
		self.player.rot = rotation;
		const time = try reader.readInt(i16);
		self.timeDifference.addDataPoint(time);
		self.interpolation.updatePosition(&position, &velocity, time);
	}

	pub fn sendMessage(self: *User, comptime fmt: []const u8, args: anytype) void {
		const msg = std.fmt.allocPrint(main.stackAllocator.allocator, fmt, args) catch unreachable;
		defer main.stackAllocator.free(msg);
		self.sendRawMessage(msg);
	}
	pub fn sendRawMessage(self: *User, msg: []const u8) void {
		main.network.protocols.chat.send(self.conn, msg);
	}

	pub fn hasPermission(user: *User, permissionPath: []const u8) bool {
		return switch (user.permissions.hasPermission(permissionPath)) {
			.yes => true,
			.no, .neutral => false,
		};
	}
};

pub const updatesPerSec: u32 = 20;
const updateTime: std.Io.Duration = .fromNanoseconds(1000000000/20);

pub var world: ?*ServerWorld = null;
var userMutex: std.Thread.Mutex = .{};
var users: main.List(*User) = undefined;
var userDeinitList: main.utils.ConcurrentQueue(*User) = undefined;
var userConnectList: main.utils.ConcurrentQueue(*User) = undefined;

pub var connectionManager: *ConnectionManager = undefined;

pub var running: std.atomic.Value(bool) = .init(false);
var lastTime: std.Io.Timestamp = undefined;

pub var thread: ?std.Thread = null;

fn init(name: []const u8, singlePlayerPort: ?u16) void { // MARK: init()
	main.heap.allocators.createWorldArena();
	std.debug.assert(world == null); // There can only be one world.
	command.init();
	users = .init(main.globalAllocator);
	userDeinitList = .init(main.globalAllocator, 16);
	userConnectList = .init(main.globalAllocator, 16);
	lastTime = main.timestamp();
	connectionManager = ConnectionManager.init(main.settings.defaultPort, false) catch |err| {
		std.log.err("Couldn't create socket: {s}", .{@errorName(err)});
		@panic("Could not open Server.");
	}; // TODO Configure the second argument in the server settings.

	main.items.Inventory.ServerSide.init();
	main.sync.ServerSide.init();

	world = ServerWorld.init(name) catch |err| {
		std.log.err("Failed to create world: {s}", .{@errorName(err)});
		@panic("Can't create world.");
	};
	world.?.generate() catch |err| {
		std.log.err("Failed to generate world: {s}", .{@errorName(err)});
		@panic("Can't generate world.");
	};
	if (singlePlayerPort) |port| blk: {
		const ipString = std.fmt.allocPrint(main.stackAllocator.allocator, "127.0.0.1:{}", .{port}) catch unreachable;
		defer main.stackAllocator.free(ipString);
		const user = User.initAndIncreaseRefCount(connectionManager, ipString) catch |err| {
			std.log.err("Cannot create singleplayer user {s}", .{@errorName(err)});
			break :blk;
		};
		defer user.decreaseRefCount();
		user.isLocal = true;
		user.permissions.addPermission(.white, "/");
	}
}

fn deinit() void {
	users.clearAndFree();
	while (userDeinitList.popFront()) |user| {
		user.deinit();
	}
	userDeinitList.deinit();
	userConnectList.deinit();
	for (connectionManager.connections.items) |conn| {
		conn.user.?.decreaseRefCount();
	}
	connectionManager.deinit();
	connectionManager = undefined;

	if (world) |_world| {
		_world.deinit();
	}
	world = null;

	main.sync.ServerSide.deinit();
	main.items.Inventory.ServerSide.deinit();

	command.deinit();
	main.heap.allocators.destroyWorldArena();
}

pub fn getUserListAndIncreaseRefCount(allocator: main.heap.NeverFailingAllocator) []*User {
	userMutex.lock();
	defer userMutex.unlock();
	const result = allocator.dupe(*User, users.items);
	for (result) |user| {
		user.increaseRefCount();
	}
	return result;
}

pub fn freeUserListAndDecreaseRefCount(allocator: main.heap.NeverFailingAllocator, list: []*User) void {
	for (list) |user| {
		user.decreaseRefCount();
	}
	allocator.free(list);
}

fn getInitialEntityList(allocator: main.heap.NeverFailingAllocator) []const u8 {
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

	while (userConnectList.popFront()) |user| {
		connectInternal(user);
		user.decreaseRefCount();
	}

	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for (userList) |user| {
		user.update();
	}

	// Send the entity data:
	const itemData = world.?.itemDropManager.getPositionAndVelocityData(main.stackAllocator);
	defer main.stackAllocator.free(itemData);

	var entityData: main.List(main.entity.EntityNetworkData) = .init(main.stackAllocator);
	defer entityData.deinit();

	for (userList) |user| {
		const id = user.id; // TODO
		entityData.append(.{
			.id = id,
			.pos = user.player.pos,
			.vel = user.player.vel,
			.rot = user.player.rot,
		});
	}
	for (userList) |user| {
		main.network.protocols.entityPosition.send(user.conn, user.player.pos, entityData.items, itemData);
	}

	for (userList) |user| {
		const pos = @as(Vec3i, @intFromFloat(user.player.pos));
		const biomeId = world.?.getBiome(pos[0], pos[1], pos[2]).paletteId;
		if (biomeId != user.lastSentBiomeId) {
			user.lastSentBiomeId = biomeId;
			main.network.protocols.genericUpdate.sendBiome(user.conn, biomeId);
		}
	}

	while (userDeinitList.popFront()) |user| {
		if (user.refCount.load(.monotonic) == 1) {
			user.decreaseRefCount();
		} else {
			userDeinitList.pushBack(user);
			break;
		}
	}
}

pub fn startFromNewThread(name: []const u8, port: ?u16) void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();
	startFromExistingThread(name, port);
}

pub fn startFromExistingThread(name: []const u8, port: ?u16) void {
	std.debug.assert(!running.load(.monotonic)); // There can only be one server.
	init(name, port);
	defer deinit();
	running.store(true, .release);
	while (running.load(.monotonic)) {
		main.heap.GarbageCollection.syncPoint();
		const newTime = main.timestamp();
		if (lastTime.durationTo(newTime).nanoseconds < updateTime.nanoseconds) {
			main.io.sleep(newTime.durationTo(lastTime.addDuration(updateTime)), .awake) catch {};
			lastTime = lastTime.addDuration(updateTime);
		} else {
			std.log.warn("The server is lagging behind by {d:.1} ms", .{@as(f32, @floatFromInt(newTime.nanoseconds -% lastTime.nanoseconds -% updateTime.nanoseconds))/1000000.0});
			lastTime = newTime;
		}
		update();
	}
}

pub fn stop() void {
	running.store(false, .monotonic);
}

pub fn disconnect(user: *User) void { // MARK: disconnect()
	if (!user.connected.load(.monotonic)) return;
	removePlayer(user);
	userDeinitList.pushBack(user);
	user.connected.store(false, .monotonic);
}

pub fn removePlayer(user: *User) void { // MARK: removePlayer()
	if (!user.connected.load(.monotonic)) return;

	const foundUser = blk: {
		userMutex.lock();
		defer userMutex.unlock();
		for (users.items, 0..) |other, i| {
			if (other == user) {
				_ = users.swapRemove(i);
				break :blk true;
			}
		}
		break :blk false;
	};
	if (!foundUser) return;

	sendMessage("{s}§#ffff00 left", .{user.name});
	// Let the other clients know about that this new one left.
	const zonArray = main.ZonElement.initArray(main.stackAllocator);
	defer zonArray.deinit(main.stackAllocator);
	zonArray.array.append(.{.int = user.id});
	const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
	defer main.stackAllocator.free(data);
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for (userList) |other| {
		main.network.protocols.entity.send(other.conn, data);
	}
}

pub fn connect(user: *User) void {
	user.increaseRefCount();
	userConnectList.pushBack(user);
}

pub fn connectInternal(user: *User) void {
	user.initPlayer();
	main.network.protocols.handShake.sendServerPlayerData(user.conn);
	// TODO: addEntity(player);
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	// Check if a user with that account is already present
	if (!world.?.settings.testingMode) {
		for (userList) |other| {
			if (other.playerIndex == user.playerIndex) {
				user.conn.disconnect();
				return;
			}
		}
	}
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
		for (userList) |other| {
			main.network.protocols.entity.send(other.conn, data);
		}
	}
	{ // Let this client know about the others:
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.deinit(main.stackAllocator);
		for (userList) |other| {
			const entityZon = main.ZonElement.initObject(main.stackAllocator);
			entityZon.put("id", other.id);
			entityZon.put("name", other.name);
			zonArray.array.append(entityZon);
		}
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		if (user.connected.load(.monotonic)) main.network.protocols.entity.send(user.conn, data);
	}
	const initialList = getInitialEntityList(main.stackAllocator);
	main.network.protocols.entity.send(user.conn, initialList);
	main.stackAllocator.free(initialList);
	sendMessage("{s}§#ffff00 joined", .{user.name});

	userMutex.lock();
	users.append(user);
	userMutex.unlock();
	user.conn.handShakeState.store(.complete, .monotonic);
}

pub fn messageFrom(msg: []const u8, source: *User) void { // MARK: message
	sendMessage("[{s}§#ffffff] {s}", .{source.name, msg});
}

fn sendRawMessage(msg: []const u8) void {
	chatMutex.lock();
	defer chatMutex.unlock();
	std.log.info("Chat: {s}", .{msg}); // TODO use color \033[0;32m
	const userList = getUserListAndIncreaseRefCount(main.stackAllocator);
	defer freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for (userList) |user| {
		user.sendRawMessage(msg);
	}
}

var chatMutex: std.Thread.Mutex = .{};
pub fn sendMessage(comptime fmt: []const u8, args: anytype) void {
	const msg = std.fmt.allocPrint(main.stackAllocator.allocator, fmt, args) catch unreachable;
	defer main.stackAllocator.free(msg);
	sendRawMessage(msg);
}
