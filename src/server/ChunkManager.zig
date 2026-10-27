const std = @import("std");

const main = @import("main");
const Cache = main.utils.Cache;
const chunk = main.chunk;
const ChunkPosition = chunk.ChunkPosition;
const ServerChunk = chunk.ServerChunk;
const utils = main.utils;
const ZonElement = main.ZonElement;
const terrain = server.terrain;

const server = @import("server.zig");
const User = server.User;
const Entity = server.Entity;
const permission = server.permission;
const players = server.players;
const World = server.ServerWorld;
const storage = server.storage;

const SimulationChunk = main.server.SimulationChunk;

const ChunkManager = @This();

world: *World,
terrainGenerationProfile: server.terrain.TerrainGenerationProfile,

// There will be at most 1 GiB of chunks in here. TODO: Allow configuring this in the server settings.
const reducedChunkCacheMask = 2047;
var chunkCache: Cache(ServerChunk, reducedChunkCacheMask + 1, 4, chunkDeinitFunctionForCache) = .{};
const HashContext = struct {
	pub fn hash(_: HashContext, a: chunk.ChunkPosition) u64 {
		return a.hashCode();
	}
	pub fn eql(_: HashContext, a: chunk.ChunkPosition, b: chunk.ChunkPosition) bool {
		return std.meta.eql(a, b);
	}
};
pub var simulationChunkHashMap: std.HashMap(chunk.ChunkPosition, *SimulationChunk, HashContext, 50) = undefined;
pub var mutex: main.utils.Mutex = .{};

pub fn getSimulationChunkAndIncreaseRefCount(pos: chunk.ChunkPosition) ?*SimulationChunk {
	std.debug.assert(pos.voxelSize == 1);
	mutex.lock();
	defer mutex.unlock();
	if (simulationChunkHashMap.get(pos)) |ch| {
		ch.increaseRefCount();
		return ch;
	}
	return null;
}

pub fn getOrGenerateSimulationChunkAndIncreaseRefCount(pos: chunk.ChunkPosition) *SimulationChunk {
	std.debug.assert(pos.voxelSize == 1);
	mutex.lock();
	if (simulationChunkHashMap.get(pos)) |ch| {
		ch.increaseRefCount();
		mutex.unlock();
		return ch;
	}
	const ch = SimulationChunk.initAndIncreaseRefCount(pos);
	ch.increaseRefCount();
	simulationChunkHashMap.put(pos, ch) catch unreachable;
	mutex.unlock();
	ch.increaseRefCount();
	ChunkLoadTask.scheduleAndDecreaseRefCount(pos, .{.simulationChunk = ch});
	return ch;
}

pub fn tryRemoveSimulationChunk(ch: *SimulationChunk) void {
	mutex.lock();
	defer mutex.unlock();
	if (ch.refCount.load(.monotonic) == 1) { // Only we hold it.
		std.debug.assert(simulationChunkHashMap.remove(ch.pos));
		ch.decreaseRefCount();
	}
}

const Source = union(enum) {
	player: server.PlayerIndex,
	simulationChunk: *SimulationChunk,
};

const ChunkLoadTask = struct { // MARK: ChunkLoadTask
	pos: ChunkPosition,
	source: Source,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.meta.castFunctionSelfToAnyopaque(run),
		.clean = main.meta.castFunctionSelfToAnyopaque(clean),
		.taskType = .chunkgen,
	};

	pub fn scheduleAndDecreaseRefCount(pos: ChunkPosition, source: Source) void {
		const task = main.globalAllocator.create(ChunkLoadTask);
		task.* = ChunkLoadTask{
			.pos = pos,
			.source = source,
		};
		switch (source) {
			.player => |player| {
				const user = server.getUserByIndex(player) orelse {
					main.globalAllocator.destroy(task);
					return;
				};
				user.addTask(task, &vtable);
			},
			else => {
				main.threadPool.addTask(task, &vtable);
			},
		}
	}

	pub fn getPriority(self: *ChunkLoadTask) f32 {
		switch (self.source) {
			.player => |player| {
				const user = server.getUserByIndex(player) orelse return 0;
				return self.pos.getPriority(user.player().pos);
			},
			else => return std.math.floatMax(f32),
		}
	}

	pub fn isStillNeeded(self: *ChunkLoadTask) bool {
		switch (self.source) { // Remove the task if it's far enough away from the player:
			.player => |player| {
				const user = server.getUserByIndex(player) orelse return false;
				const minDistSquare = self.pos.getMinDistanceSquared(user.clientUpdatePos);
				//                                                                              ↓ Margin for error. (diagonal of 1 chunk)
				var targetRenderDistance: i64 = @as(i64, user.renderDistance)*chunk.chunkSize + @as(i64, @ceil(@as(comptime_int, chunk.chunkSize)*@sqrt(3.0)));
				targetRenderDistance *= self.pos.voxelSize;
				return minDistSquare <= targetRenderDistance*targetRenderDistance;
			},
			.simulationChunk => |ch| if (ch.refCount.load(.monotonic) == 2) return false,
		}
		return true;
	}

	pub fn run(self: *ChunkLoadTask) void {
		defer self.clean();
		generateChunk(self.pos, self.source);
	}

	pub fn clean(self: *ChunkLoadTask) void {
		switch (self.source) {
			.player => {},
			.simulationChunk => |ch| ch.decreaseRefCount(),
		}
		main.globalAllocator.destroy(self);
	}
};

const LightMapLoadTask = struct { // MARK: LightMapLoadTask
	pos: terrain.SurfaceMap.MapFragmentPosition,
	source: ?main.server.PlayerIndex,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.meta.castFunctionSelfToAnyopaque(run),
		.clean = main.meta.castFunctionSelfToAnyopaque(clean),
		.taskType = .misc,
	};

	pub fn schedule(pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		const task = main.globalAllocator.create(LightMapLoadTask);
		task.* = LightMapLoadTask{
			.pos = pos,
			.source = if (source) |u| u.playerIndex else null,
		};
		if (source) |user| {
			user.addTask(task, &vtable);
		} else {
			main.threadPool.addTask(task, &vtable);
		}
	}

	pub fn getPriority(self: *LightMapLoadTask) f32 {
		if (self.source) |playerIndex| {
			const user = server.getUserByIndex(playerIndex) orelse return 0;
			return self.pos.getPriority(user.player().pos, terrain.LightMap.LightMapFragment.mapSize) + 100;
		} else {
			return std.math.floatMax(f32);
		}
	}

	pub fn isStillNeeded(self: *LightMapLoadTask) bool {
		_ = self; // TODO: Do these tasks need to be culled?
		return true;
	}

	pub fn run(self: *LightMapLoadTask) void {
		defer self.clean();
		const map = terrain.LightMap.getOrGenerateFragment(self.pos.wx, self.pos.wy, self.pos.voxelSize);
		if (self.source) |source| {
			const user = server.getUserByIndex(source) orelse return;
			if (user.connected.load(.monotonic)) main.network.protocols.light_map_transmission.sendLightMap(user.conn, map);
		} else {
			const userList = server.getUserList(main.stackAllocator);
			defer main.stackAllocator.free(userList);
			for (userList) |user| {
				main.network.protocols.light_map_transmission.sendLightMap(user.conn, map);
			}
		}
	}

	pub fn clean(self: *LightMapLoadTask) void {
		main.globalAllocator.destroy(self);
	}
};

pub fn init(world: *World, settings: ZonElement) !ChunkManager { // MARK: init()
	const self = ChunkManager{
		.world = world,
		.terrainGenerationProfile = try server.terrain.TerrainGenerationProfile.init(settings, world.settings.seed),
	};
	simulationChunkHashMap = .init(main.globalAllocator.allocator);
	server.terrain.init(self.terrainGenerationProfile);
	storage.init();
	return self;
}

pub fn deinit(_: ChunkManager) void {
	main.threadPool.updateTaskPriority();
	for (0..main.settings.highestSupportedLod) |_| {
		chunkCache.clear();
	}
	simulationChunkHashMap.deinit();
	server.terrain.deinit();
	main.assets.unloadAssets();
	storage.deinit();
}

pub fn queueLightMap(self: ChunkManager, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
	_ = self;
	LightMapLoadTask.schedule(pos, source);
}

pub fn queueChunk(self: ChunkManager, pos: ChunkPosition, source: *User) void {
	_ = self;
	ChunkLoadTask.scheduleAndDecreaseRefCount(pos, .{.player = source.playerIndex});
}

pub fn generateChunk(pos: ChunkPosition, source: Source) void { // MARK: generateChunk()
	const ch = getOrGenerateChunkAndIncreaseRefCount(pos);
	switch (source) {
		.player => |player| {
			const user = server.getUserByIndex(player) orelse return;
			main.network.protocols.chunk_transmisison.sendChunk(user.conn, ch);
			ch.decreaseRefCount();
		},
		.simulationChunk => |simulationChunk| {
			simulationChunk.setChunkAndDecreaseRefCount(ch);
		},
	}
}

fn chunkInitFunctionForCacheAndIncreaseRefCount(pos: ChunkPosition) *ServerChunk {
	if (pos.voxelSize == 1) {
		if (getSimulationChunkAndIncreaseRefCount(pos)) |simulationChunk| { // Check if we already have it in memory.
			defer simulationChunk.decreaseRefCount();
			if (simulationChunk.getChunk()) |ch| {
				ch.increaseRefCount();
				return ch;
			}
		}
	}
	const regionSize = pos.voxelSize*chunk.chunkSize*storage.RegionFile.regionSize;
	const regionMask: i32 = regionSize - 1;
	const region = storage.loadRegionFileAndIncreaseRefCount(pos.wx & ~regionMask, pos.wy & ~regionMask, pos.wz & ~regionMask, pos.voxelSize);
	defer region.decreaseRefCount();
	const ch = ServerChunk.initAndIncreaseRefCount(pos);
	ch.mutex.lock();
	defer ch.mutex.unlock();
	if (region.getChunk(
		main.stackAllocator,
		@as(usize, @intCast(pos.wx -% region.pos.wx))/pos.voxelSize/chunk.chunkSize,
		@as(usize, @intCast(pos.wy -% region.pos.wy))/pos.voxelSize/chunk.chunkSize,
		@as(usize, @intCast(pos.wz -% region.pos.wz))/pos.voxelSize/chunk.chunkSize,
	)) |data| blk: { // Load chunk from file:
		defer main.stackAllocator.free(data);
		storage.chunk_compression.loadChunk(&ch.super, .server, data) catch {
			std.log.err("Storage for chunk {} in region file at {} is corrupted", .{pos, region.pos});
			break :blk;
		};
		ch.wasStored = true;
		return ch;
	}
	ch.generated = true;
	const caveMap = terrain.CaveMap.CaveMapView.init(main.stackAllocator, ch.super.pos, ch.super.width, 32);
	defer caveMap.deinit(main.stackAllocator);
	const biomeMap = terrain.CaveBiomeMap.CaveBiomeMapView.init(main.stackAllocator, ch.super.pos, ch.super.width, 32);
	defer biomeMap.deinit();
	for (server.world.?.chunkManager.terrainGenerationProfile.generators) |generator| {
		generator.generate(server.world.?.settings.seed ^ generator.generatorSeed, ch, caveMap, biomeMap);
	}
	if (pos.voxelSize != 1) { // Generate LOD replacements
		for (ch.super.data.palette()) |*block| {
			block.store(.{.typ = block.load(.unordered).lodReplacement(), .data = block.load(.unordered).data}, .unordered);
		}
	}
	return ch;
}

fn chunkDeinitFunctionForCache(ch: *ServerChunk) void {
	ch.decreaseRefCount();
}
/// Generates a normal chunk at a given location, or if possible gets it from the cache.
pub fn getOrGenerateChunkAndIncreaseRefCount(pos: ChunkPosition) *ServerChunk {
	const mask = pos.voxelSize*chunk.chunkSize - 1;
	std.debug.assert(pos.wx & mask == 0 and pos.wy & mask == 0 and pos.wz & mask == 0);
	const result = chunkCache.findOrCreate(pos, chunkInitFunctionForCacheAndIncreaseRefCount, ServerChunk.increaseRefCount);
	return result;
}

pub fn getChunkFromCacheAndIncreaseRefCount(pos: ChunkPosition) ?*ServerChunk {
	const mask = pos.voxelSize*chunk.chunkSize - 1;
	std.debug.assert(pos.wx & mask == 0 and pos.wy & mask == 0 and pos.wz & mask == 0);
	const result = chunkCache.find(pos, ServerChunk.increaseRefCount) orelse return null;
	return result;
}
