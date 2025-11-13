const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const Cache = main.utils.Cache;
const chunk = main.chunk;
const ChunkPosition = chunk.ChunkPosition;
const ServerChunk = chunk.ServerChunk;
const files = main.files;
const utils = main.utils;
const ItemDropManager = main.itemdrop.ItemDropManager;
const ItemStack = main.items.ItemStack;
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const terrain = server.terrain;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const server = @import("server.zig");
const User = server.User;
const Entity = server.Entity;
const Palette = main.assets.Palette;

const storage = @import("storage.zig");
const Gamemode = main.game.Gamemode;

pub const WorldSettings = struct {
	gamemode: Gamemode = .creative,
	allowCheats: bool = false,
	testingMode: bool = false,
};
fn findValidFolderName(allocator: main.heap.NeverFailingAllocator, name: []const u8) []const u8 {
	// Remove illegal ASCII characters:
	const escapedName = main.stackAllocator.alloc(u8, name.len);
	defer main.stackAllocator.free(escapedName);
	for(name, 0..) |char, i| {
		escapedName[i] = switch(char) {
			'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.', ' ' => char,
			128...255 => char,
			else => '-',
		};
	}

	// Avoid duplicates:
	var resultName = main.stackAllocator.dupe(u8, escapedName);
	defer main.stackAllocator.free(resultName);
	var i: usize = 0;
	while(true) {
		const resultPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{resultName}) catch unreachable;
		defer main.stackAllocator.free(resultPath);

		if(!main.files.cubyzDir().hasDir(resultPath)) break;

		main.stackAllocator.free(resultName);
		resultName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}_{}", .{escapedName, i}) catch unreachable;
		i += 1;
	}
	return allocator.dupe(u8, resultName);
}

pub fn tryCreateWorld(worldName: []const u8, worldSettings: WorldSettings) !void {
	const worldPath = findValidFolderName(main.stackAllocator, worldName);
	defer main.stackAllocator.free(worldPath);
	const saveFolder = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{worldPath}) catch unreachable;
	defer main.stackAllocator.free(saveFolder);
	try main.files.cubyzDir().makePath(saveFolder);
	{
		const generatorSettingsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/generatorSettings.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(generatorSettingsPath);
		const generatorSettings = main.ZonElement.initObject(main.stackAllocator);
		defer generatorSettings.deinit(main.stackAllocator);
		const climateGenerator = main.ZonElement.initObject(main.stackAllocator);
		climateGenerator.put("id", "cubyz:noise_based_voronoi"); // TODO: Make this configurable
		generatorSettings.put("climateGenerator", climateGenerator);
		const mapGenerator = main.ZonElement.initObject(main.stackAllocator);
		mapGenerator.put("id", "cubyz:mapgen_v1"); // TODO: Make this configurable
		generatorSettings.put("mapGenerator", mapGenerator);
		const climateWavelengths = main.ZonElement.initObject(main.stackAllocator);
		climateWavelengths.put("hot_cold", 2400);
		climateWavelengths.put("land_ocean", 3200);
		climateWavelengths.put("wet_dry", 1800);
		climateWavelengths.put("vegetation", 1600);
		climateWavelengths.put("mountain", 512);
		generatorSettings.put("climateWavelengths", climateWavelengths);
		try main.files.cubyzDir().writeZon(generatorSettingsPath, generatorSettings);
	}
	{
		const worldInfoPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/world.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(worldInfoPath);
		const worldInfo = main.ZonElement.initObject(main.stackAllocator);
		defer worldInfo.deinit(main.stackAllocator);

		worldInfo.put("name", worldName);
		worldInfo.put("version", main.server.world_zig.worldDataVersion);
		worldInfo.put("lastUsedTime", std.time.milliTimestamp());

		try main.files.cubyzDir().writeZon(worldInfoPath, worldInfo);
	}
	{
		const gamerulePath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/gamerules.zig.zon", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(gamerulePath);
		const gamerules = main.ZonElement.initObject(main.stackAllocator);
		defer gamerules.deinit(main.stackAllocator);

		gamerules.put("default_gamemode", @tagName(worldSettings.gamemode));
		gamerules.put("cheats", worldSettings.allowCheats);
		gamerules.put("testingMode", worldSettings.testingMode);

		try main.files.cubyzDir().writeZon(gamerulePath, gamerules);
	}
	{ // Make assets subfolder
		const assetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets", .{worldPath}) catch unreachable;
		defer main.stackAllocator.free(assetsPath);
		try main.files.cubyzDir().makePath(assetsPath);
	}
	// TODO: Make the seed configurable

}

pub const EntityChunk = struct {
	chunk: std.atomic.Value(?*ServerChunk) = .init(null),
	refCount: std.atomic.Value(u32),
	pos: chunk.ChunkPosition,

	pub fn initAndIncreaseRefCount(pos: ChunkPosition) *EntityChunk {
		const self = main.globalAllocator.create(EntityChunk);
		self.* = .{
			.refCount = .init(1),
			.pos = pos,
		};
		return self;
	}

	fn deinit(self: *const EntityChunk) void {
		std.debug.assert(self.refCount.load(.monotonic) == 0);
		if(self.chunk.raw) |ch| ch.decreaseRefCount();
		main.globalAllocator.destroy(self);
	}

	pub fn increaseRefCount(self: *EntityChunk) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *EntityChunk) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 2) {
			ChunkManager.tryRemoveEntityChunk(self);
		}
		if(prevVal == 1) {
			self.deinit();
		}
	}

	pub fn getChunk(self: *EntityChunk) ?*ServerChunk {
		return self.chunk.load(.acquire);
	}

	pub fn setChunkAndDecreaseRefCount(self: *EntityChunk, ch: *ServerChunk) void {
		std.debug.assert(self.chunk.swap(ch, .release) == null);
	}
};

const ChunkManager = struct { // MARK: ChunkManager
	world: *ServerWorld,
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
	var entityChunkHashMap: std.HashMap(chunk.ChunkPosition, *EntityChunk, HashContext, 50) = undefined;
	var mutex: std.Thread.Mutex = .{};

	fn getEntityChunkAndIncreaseRefCount(pos: chunk.ChunkPosition) ?*EntityChunk {
		std.debug.assert(pos.voxelSize == 1);
		mutex.lock();
		defer mutex.unlock();
		if(entityChunkHashMap.get(pos)) |entityChunk| {
			entityChunk.increaseRefCount();
			return entityChunk;
		}
		return null;
	}

	pub fn getOrGenerateEntityChunkAndIncreaseRefCount(pos: chunk.ChunkPosition) *EntityChunk {
		std.debug.assert(pos.voxelSize == 1);
		mutex.lock();
		if(entityChunkHashMap.get(pos)) |entityChunk| {
			entityChunk.increaseRefCount();
			mutex.unlock();
			return entityChunk;
		}
		const entityChunk = EntityChunk.initAndIncreaseRefCount(pos);
		entityChunk.increaseRefCount();
		entityChunk.increaseRefCount();
		entityChunkHashMap.put(pos, entityChunk) catch unreachable;
		mutex.unlock();
		ChunkLoadTask.scheduleAndDecreaseRefCount(pos, .{.entityChunk = entityChunk});
		return entityChunk;
	}

	fn tryRemoveEntityChunk(ch: *EntityChunk) void {
		mutex.lock();
		defer mutex.unlock();
		if(ch.refCount.load(.monotonic) == 1) { // Only we hold it.
			std.debug.assert(entityChunkHashMap.remove(ch.pos));
			ch.decreaseRefCount();
		}
	}

	const Source = union(enum) {
		user: *User,
		entityChunk: *EntityChunk,
	};

	const ChunkLoadTask = struct { // MARK: ChunkLoadTask
		pos: ChunkPosition,
		source: Source,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
			.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
			.run = main.utils.castFunctionSelfToAnyopaque(run),
			.clean = main.utils.castFunctionSelfToAnyopaque(clean),
			.taskType = .chunkgen,
		};

		pub fn scheduleAndDecreaseRefCount(pos: ChunkPosition, source: Source) void {
			const task = main.globalAllocator.create(ChunkLoadTask);
			task.* = ChunkLoadTask{
				.pos = pos,
				.source = source,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(self: *ChunkLoadTask) f32 {
			switch(self.source) {
				.user => |user| return self.pos.getPriority(user.player.pos),
				else => return std.math.floatMax(f32),
			}
		}

		pub fn isStillNeeded(self: *ChunkLoadTask) bool {
			switch(self.source) { // Remove the task if the player disconnected
				.user => |user| if(!user.connected.load(.unordered)) return false,
				.entityChunk => |ch| if(ch.refCount.load(.monotonic) == 2) return false,
			}
			switch(self.source) { // Remove the task if it's far enough away from the player:
				.user => |user| {
					const minDistSquare = self.pos.getMinDistanceSquared(user.clientUpdatePos);
					//                                                                              ↓ Margin for error. (diagonal of 1 chunk)
					var targetRenderDistance: i64 = @as(i64, user.renderDistance)*chunk.chunkSize + @as(i64, @intFromFloat(@as(comptime_int, chunk.chunkSize)*@sqrt(3.0)));
					targetRenderDistance *= self.pos.voxelSize;
					return minDistSquare <= targetRenderDistance*targetRenderDistance;
				},
				.entityChunk => {},
			}
			return true;
		}

		pub fn run(self: *ChunkLoadTask) void {
			defer self.clean();
			generateChunk(self.pos, self.source);
		}

		pub fn clean(self: *ChunkLoadTask) void {
			switch(self.source) {
				.user => |user| user.decreaseRefCount(),
				.entityChunk => |ch| ch.decreaseRefCount(),
			}
			main.globalAllocator.destroy(self);
		}
	};

	const LightMapLoadTask = struct { // MARK: LightMapLoadTask
		pos: terrain.SurfaceMap.MapFragmentPosition,
		source: ?*User,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
			.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
			.run = main.utils.castFunctionSelfToAnyopaque(run),
			.clean = main.utils.castFunctionSelfToAnyopaque(clean),
			.taskType = .misc,
		};

		pub fn scheduleAndDecreaseRefCount(pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
			const task = main.globalAllocator.create(LightMapLoadTask);
			task.* = LightMapLoadTask{
				.pos = pos,
				.source = source,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(self: *LightMapLoadTask) f32 {
			if(self.source) |user| {
				return self.pos.getPriority(user.player.pos, terrain.LightMap.LightMapFragment.mapSize) + 100;
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
			if(self.source) |source| {
				if(source.connected.load(.unordered)) main.network.Protocols.lightMapTransmission.sendLightMap(source.conn, map);
			} else {
				const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
				defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
				for(userList) |user| {
					main.network.Protocols.lightMapTransmission.sendLightMap(user.conn, map);
				}
			}
		}

		pub fn clean(self: *LightMapLoadTask) void {
			if(self.source) |source| {
				source.decreaseRefCount();
			}
			main.globalAllocator.destroy(self);
		}
	};

	pub fn init(world: *ServerWorld, settings: ZonElement) !ChunkManager { // MARK: init()
		const self = ChunkManager{
			.world = world,
			.terrainGenerationProfile = try server.terrain.TerrainGenerationProfile.init(settings, world.seed),
		};
		entityChunkHashMap = .init(main.globalAllocator.allocator);
		server.terrain.init(self.terrainGenerationProfile);
		storage.init();
		return self;
	}

	pub fn deinit(_: ChunkManager) void {
		for(0..main.settings.highestSupportedLod) |_| {
			chunkCache.clear();
		}
		entityChunkHashMap.deinit();
		server.terrain.deinit();
		main.assets.unloadAssets();
		storage.deinit();
	}

	pub fn queueLightMapAndDecreaseRefCount(self: ChunkManager, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		_ = self;
		LightMapLoadTask.scheduleAndDecreaseRefCount(pos, source);
	}

	pub fn queueChunkAndDecreaseRefCount(self: ChunkManager, pos: ChunkPosition, source: *User) void {
		_ = self;
		ChunkLoadTask.scheduleAndDecreaseRefCount(pos, .{.user = source});
	}

	pub fn generateChunk(pos: ChunkPosition, source: Source) void { // MARK: generateChunk()
		const ch = getOrGenerateChunkAndIncreaseRefCount(pos);
		switch(source) {
			.user => |user| {
				main.network.Protocols.chunkTransmission.sendChunk(user.conn, ch);
				ch.decreaseRefCount();
			},
			.entityChunk => |entityChunk| {
				entityChunk.setChunkAndDecreaseRefCount(ch);
			},
		}
	}

	fn chunkInitFunctionForCacheAndIncreaseRefCount(pos: ChunkPosition) *ServerChunk {
		if(pos.voxelSize == 1) if(getEntityChunkAndIncreaseRefCount(pos)) |entityChunk| { // Check if we already have it in memory.
			defer entityChunk.decreaseRefCount();
			if(entityChunk.getChunk()) |ch| {
				ch.increaseRefCount();
				return ch;
			}
		};
		const regionSize = pos.voxelSize*chunk.chunkSize*storage.RegionFile.regionSize;
		const regionMask: i32 = regionSize - 1;
		const region = storage.loadRegionFileAndIncreaseRefCount(pos.wx & ~regionMask, pos.wy & ~regionMask, pos.wz & ~regionMask, pos.voxelSize);
		defer region.decreaseRefCount();
		const ch = ServerChunk.initAndIncreaseRefCount(pos);
		ch.mutex.lock();
		defer ch.mutex.unlock();
		if(region.getChunk(
			main.stackAllocator,
			@as(usize, @intCast(pos.wx -% region.pos.wx))/pos.voxelSize/chunk.chunkSize,
			@as(usize, @intCast(pos.wy -% region.pos.wy))/pos.voxelSize/chunk.chunkSize,
			@as(usize, @intCast(pos.wz -% region.pos.wz))/pos.voxelSize/chunk.chunkSize,
		)) |data| blk: { // Load chunk from file:
			defer main.stackAllocator.free(data);
			storage.ChunkCompression.loadChunk(&ch.super, .server, data) catch {
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
		for(server.world.?.chunkManager.terrainGenerationProfile.generators) |generator| {
			generator.generate(server.world.?.seed ^ generator.generatorSeed, ch, caveMap, biomeMap);
		}
		if(pos.voxelSize != 1) { // Generate LOD replacements
			for(ch.super.data.palette()) |*block| {
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
};

pub const worldDataVersion: u32 = 2;

const WorldIO = struct { // MARK: WorldIO

	dir: files.Dir,
	world: *ServerWorld,

	pub fn init(dir: files.Dir, world: *ServerWorld) WorldIO {
		return WorldIO{
			.dir = dir,
			.world = world,
		};
	}

	pub fn deinit(self: *WorldIO) void {
		self.dir.close();
	}

	/// Load the seed, which is needed before custom item and ore generation.
	pub fn loadWorldSeed(self: WorldIO) !u64 {
		const worldData = try self.dir.readToZon(main.stackAllocator, "world.zig.zon");
		defer worldData.deinit(main.stackAllocator);
		if(worldData.get(u32, "version", 0) != worldDataVersion) {
			std.log.err("Cannot read world file version {}. Expected version {}.", .{worldData.get(u32, "version", 0), worldDataVersion});
			return error.OldWorld;
		}
		return worldData.get(?u64, "seed", null) orelse main.random.nextInt(u48, &main.seed);
	}

	pub fn loadWorldData(self: WorldIO) !void {
		const worldData = try self.dir.readToZon(main.stackAllocator, "world.zig.zon");
		defer worldData.deinit(main.stackAllocator);

		self.world.doGameTimeCycle = worldData.get(bool, "doGameTimeCycle", true);
		self.world.gameTime = worldData.get(i64, "gameTime", 0);
		self.world.spawn = worldData.get(Vec3i, "spawn", .{0, 0, 0});
		self.world.biomeChecksum = worldData.get(i64, "biomeChecksum", 0);
		self.world.name = main.globalAllocator.dupe(u8, worldData.get([]const u8, "name", self.world.path));
		self.world.tickSpeed = .init(worldData.get(u32, "tickSpeed", 12));
	}

	pub fn saveWorldData(self: WorldIO) !void {
		const worldData = ZonElement.initObject(main.stackAllocator);
		defer worldData.deinit(main.stackAllocator);
		worldData.put("version", worldDataVersion);
		worldData.put("seed", self.world.seed);
		worldData.put("doGameTimeCycle", self.world.doGameTimeCycle);
		worldData.put("gameTime", self.world.gameTime);
		worldData.put("spawn", self.world.spawn);
		worldData.put("biomeChecksum", self.world.biomeChecksum);
		worldData.put("name", self.world.name);
		worldData.put("lastUsedTime", std.time.milliTimestamp());
		worldData.put("tickSpeed", self.world.tickSpeed.load(.monotonic));
		// TODO: Save entities
		try self.dir.writeZon("world.zig.zon", worldData);
	}
};

pub const ServerWorld = struct { // MARK: ServerWorld
	pub const dayCycle: u31 = 12000; // Length of one in-game day in units of 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes

	itemDropManager: ItemDropManager = undefined,
	blockPalette: *main.assets.Palette = undefined,
	itemPalette: *main.assets.Palette = undefined,
	toolPalette: *main.assets.Palette = undefined,
	biomePalette: *main.assets.Palette = undefined,
	chunkManager: ChunkManager = undefined,

	gameTime: i64 = 0,
	milliTime: i64,
	lastUpdateTime: i64,
	lastUnimportantDataSent: i64,
	doGameTimeCycle: bool = true,

	tickSpeed: std.atomic.Value(u32) = .init(12),

	defaultGamemode: main.game.Gamemode = undefined,
	allowCheats: bool = undefined,
	testingMode: bool = undefined,

	seed: u64,
	path: []const u8,
	name: []const u8 = &.{},
	spawn: Vec3i = undefined,

	wio: WorldIO = undefined,

	mutex: std.Thread.Mutex = .{},

	chunkUpdateQueue: main.utils.CircularBufferQueue(ChunkUpdateRequest),
	regionUpdateQueue: main.utils.CircularBufferQueue(RegionUpdateRequest),

	biomeChecksum: i64 = 0,

	const ChunkUpdateRequest = struct {
		ch: *ServerChunk,
		milliTimeStamp: i64,
	};

	const RegionUpdateRequest = struct {
		region: *storage.RegionFile,
		milliTimeStamp: i64,
	};

	pub fn init(path: []const u8, nullGeneratorSettings: ?ZonElement) !*ServerWorld { // MARK: init()
		const self = main.globalAllocator.create(ServerWorld);
		errdefer main.globalAllocator.destroy(self);
		self.* = ServerWorld{
			.lastUpdateTime = std.time.milliTimestamp(),
			.milliTime = std.time.milliTimestamp(),
			.lastUnimportantDataSent = std.time.milliTimestamp(),
			.seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp()))),
			.path = main.globalAllocator.dupe(u8, path),
			.chunkUpdateQueue = .init(main.globalAllocator, 256),
			.regionUpdateQueue = .init(main.globalAllocator, 256),
		};
		self.itemDropManager.init(main.globalAllocator, self);
		errdefer self.itemDropManager.deinit();

		const arena = main.stackAllocator.createArena();
		defer main.stackAllocator.destroyArena(arena);
		var generatorSettings: ZonElement = undefined;

		if(nullGeneratorSettings) |_generatorSettings| {
			generatorSettings = _generatorSettings;
			// Store generator settings:
			try files.cubyzDir().writeZon(try std.fmt.allocPrint(arena.allocator, "saves/{s}/generatorSettings.zig.zon", .{path}), generatorSettings);
		} else { // Read the generator settings:
			generatorSettings = try files.cubyzDir().readToZon(arena, try std.fmt.allocPrint(arena.allocator, "saves/{s}/generatorSettings.zig.zon", .{path}));
		}
		self.wio = WorldIO.init(try files.cubyzDir().openDir(try std.fmt.allocPrint(arena.allocator, "saves/{s}", .{path})), self);
		errdefer self.wio.deinit();

		self.blockPalette = try loadPalette(arena, path, "palette", "cubyz:air");
		errdefer self.blockPalette.deinit();

		self.itemPalette = try loadPalette(arena, path, "item_palette", null);
		errdefer self.itemPalette.deinit();

		self.toolPalette = try loadPalette(arena, path, "tool_palette", null);
		errdefer self.toolPalette.deinit();

		self.biomePalette = try loadPalette(arena, path, "biome_palette", null);
		errdefer self.biomePalette.deinit();

		errdefer main.assets.unloadAssets();

		self.seed = try self.wio.loadWorldSeed();
		try main.assets.loadWorldAssets(try std.fmt.allocPrint(arena.allocator, "{s}/saves/{s}/assets/", .{files.cubyzDirStr(), path}), self.blockPalette, self.itemPalette, self.toolPalette, self.biomePalette);
		// Store the block palette now that everything is loaded.
		try files.cubyzDir().writeZon(try std.fmt.allocPrint(arena.allocator, "saves/{s}/palette.zig.zon", .{path}), self.blockPalette.storeToZon(arena));
		try files.cubyzDir().writeZon(try std.fmt.allocPrint(arena.allocator, "saves/{s}/item_palette.zig.zon", .{path}), self.itemPalette.storeToZon(arena));
		try files.cubyzDir().writeZon(try std.fmt.allocPrint(arena.allocator, "saves/{s}/tool_palette.zig.zon", .{path}), self.toolPalette.storeToZon(arena));
		try files.cubyzDir().writeZon(try std.fmt.allocPrint(arena.allocator, "saves/{s}/biome_palette.zig.zon", .{path}), self.biomePalette.storeToZon(arena));

		var gamerules = files.cubyzDir().readToZon(arena, try std.fmt.allocPrint(arena.allocator, "saves/{s}/gamerules.zig.zon", .{path})) catch ZonElement.initObject(arena);

		self.defaultGamemode = std.meta.stringToEnum(main.game.Gamemode, gamerules.get([]const u8, "default_gamemode", "creative")) orelse .creative;
		self.allowCheats = gamerules.get(bool, "cheats", true);
		self.testingMode = gamerules.get(bool, "testingMode", false);

		self.chunkManager = try ChunkManager.init(self, generatorSettings);
		errdefer self.chunkManager.deinit();
		return self;
	}

	pub fn loadPalette(allocator: NeverFailingAllocator, worldName: []const u8, paletteName: []const u8, firstEntry: ?[]const u8) !*Palette {
		const path = try std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/{s}.zig.zon", .{worldName, paletteName});
		defer main.stackAllocator.allocator.free(path);
		const paletteZon = files.cubyzDir().readToZon(allocator, path) catch .null;
		const palette = try main.assets.Palette.init(main.globalAllocator, paletteZon, firstEntry);
		std.log.info("Loaded {s} with {} entries.", .{paletteName, palette.size()});
		return palette;
	}

	pub fn deinit(self: *ServerWorld) void {
		self.forceSave() catch |err| {
			std.log.err("Error while saving the world: {s}", .{@errorName(err)});
		};
		while(self.chunkUpdateQueue.popFront()) |updateRequest| {
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
		}
		self.chunkUpdateQueue.deinit();
		while(self.regionUpdateQueue.popFront()) |updateRequest| {
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
		}
		self.regionUpdateQueue.deinit();
		self.chunkManager.deinit();
		self.itemDropManager.deinit();
		self.blockPalette.deinit();
		self.itemPalette.deinit();
		self.toolPalette.deinit();
		self.biomePalette.deinit();
		self.wio.deinit();
		main.globalAllocator.free(self.path);
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}

	const RegenerateLODTask = struct { // MARK: RegenerateLODTask
		pos: ChunkPosition,
		storeMaps: bool,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
			.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
			.run = main.utils.castFunctionSelfToAnyopaque(run),
			.clean = main.utils.castFunctionSelfToAnyopaque(clean),
			.taskType = .chunkgen,
		};

		pub fn schedule(pos: ChunkPosition, storeMaps: bool) void {
			const task = main.globalAllocator.create(RegenerateLODTask);
			task.* = .{
				.pos = pos,
				.storeMaps = storeMaps,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(_: *RegenerateLODTask) f32 {
			return std.math.floatMax(f32);
		}

		pub fn isStillNeeded(_: *RegenerateLODTask) bool {
			return true;
		}

		pub fn run(self: *RegenerateLODTask) void {
			defer self.clean();
			const region = storage.loadRegionFileAndIncreaseRefCount(self.pos.wx, self.pos.wy, self.pos.wz, self.pos.voxelSize);
			defer region.decreaseRefCount();
			region.mutex.lock();
			defer region.mutex.unlock();
			for(0..storage.RegionFile.regionSize) |x| {
				for(0..storage.RegionFile.regionSize) |y| {
					for(0..storage.RegionFile.regionSize) |z| {
						if(region.chunks[storage.RegionFile.getIndex(x, y, z)].len != 0) {
							region.mutex.unlock();
							defer region.mutex.lock();
							const pos = ChunkPosition{
								.wx = self.pos.wx + @as(i32, @intCast(x))*chunk.chunkSize,
								.wy = self.pos.wy + @as(i32, @intCast(y))*chunk.chunkSize,
								.wz = self.pos.wz + @as(i32, @intCast(z))*chunk.chunkSize,
								.voxelSize = 1,
							};
							const ch = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(pos);
							defer ch.decreaseRefCount();
							var nextPos = pos;
							nextPos.wx &= ~@as(i32, self.pos.voxelSize*chunk.chunkSize);
							nextPos.wy &= ~@as(i32, self.pos.voxelSize*chunk.chunkSize);
							nextPos.wz &= ~@as(i32, self.pos.voxelSize*chunk.chunkSize);
							nextPos.voxelSize *= 2;
							const nextHigherLod = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(nextPos);
							defer nextHigherLod.decreaseRefCount();
							ch.mutex.lock();
							defer ch.mutex.unlock();
							nextHigherLod.updateFromLowerResolution(ch);
						}
					}
				}
			}
		}

		pub fn clean(self: *RegenerateLODTask) void {
			main.globalAllocator.destroy(self);
		}
	};

	fn regenerateLOD(self: *ServerWorld, newBiomeCheckSum: i64) !void {
		std.log.info("Biomes have changed. Regenerating LODs... (this might take some time)", .{});
		const mapsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps", .{self.path}) catch unreachable;
		defer main.stackAllocator.free(mapsPath);
		const hasSurfaceMaps = main.files.cubyzDir().hasDir(mapsPath);
		if(hasSurfaceMaps) {
			try terrain.SurfaceMap.regenerateLOD(self.path);
		}
		// Delete old LODs:
		for(1..main.settings.highestSupportedLod + 1) |i| {
			const lod = @as(u32, 1) << @intCast(i);
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks/{}", .{self.path, lod}) catch unreachable;
			defer main.stackAllocator.free(path);
			main.files.cubyzDir().deleteTree(path) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Error while deleting directory {s}: {s}", .{path, @errorName(err)});
				}
			};
		}
		// Find all the stored chunks:
		var chunkPositions = main.List(ChunkPosition).init(main.stackAllocator);
		defer chunkPositions.deinit();
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks/1", .{self.path}) catch unreachable;
		defer main.stackAllocator.free(path);
		blk: {
			var dirX = main.files.cubyzDir().openIterableDir(path) catch |err| {
				if(err == error.FileNotFound) break :blk;
				return err;
			};
			defer dirX.close();
			var iterX = dirX.iterate();
			while(try iterX.next()) |entryX| {
				if(entryX.kind != .directory) continue;
				const wx = std.fmt.parseInt(i32, entryX.name, 0) catch continue;
				var dirY = try dirX.openIterableDir(entryX.name);
				defer dirY.close();
				var iterY = dirY.iterate();
				while(try iterY.next()) |entryY| {
					if(entryY.kind != .directory) continue;
					const wy = std.fmt.parseInt(i32, entryY.name, 0) catch continue;
					var dirZ = try dirY.openIterableDir(entryY.name);
					defer dirZ.close();
					var iterZ = dirZ.iterate();
					while(try iterZ.next()) |entryZ| {
						if(entryZ.kind != .file) continue;
						const nameZ = entryZ.name[0 .. std.mem.indexOfScalar(u8, entryZ.name, '.') orelse entryZ.name.len];
						const wz = std.fmt.parseInt(i32, nameZ, 0) catch continue;
						chunkPositions.append(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1});
					}
				}
			}
		}
		// Load all the stored chunks and update their next LODs.
		for(chunkPositions.items) |pos| {
			RegenerateLODTask.schedule(pos, !hasSurfaceMaps);
		}

		self.mutex.lock();
		defer self.mutex.unlock();
		while(true) {
			while(self.chunkUpdateQueue.popFront()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.ch.save(self);
				updateRequest.ch.decreaseRefCount();
				main.heap.GarbageCollection.syncPoint();
			}
			while(self.regionUpdateQueue.popFront()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.region.store();
				updateRequest.region.decreaseRefCount();
				main.heap.GarbageCollection.syncPoint();
			}
			self.mutex.unlock();
			std.Thread.sleep(1_000_000);
			main.heap.GarbageCollection.syncPoint();
			self.mutex.lock();
			if(main.threadPool.queueSize() == 0 and self.chunkUpdateQueue.peekFront() == null and self.regionUpdateQueue.peekFront() == null) break;
		}
		std.log.info("Finished LOD update.", .{});

		self.biomeChecksum = newBiomeCheckSum;
	}

	pub fn generate(self: *ServerWorld) !void {
		try self.wio.loadWorldData(); // load data here in order for entities to also be loaded.

		if(@reduce(.And, self.spawn == Vec3i{0, 0, 0})) {
			var seed: u64 = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
			std.log.info("Finding position..", .{});
			foundPosition: {
				// Explore chunks in a spiral from the center:
				const radius = 65536;
				const mapSize = terrain.ClimateMap.ClimateMapFragment.mapSize;
				const spiralLen = 2*radius/mapSize*2*radius/mapSize;
				var wx: i32 = 0;
				var wy: i32 = 0;
				var dirChanges: usize = 1;
				var dir: main.chunk.Neighbor = .dirNegX;
				var stepsRemaining: usize = 1;
				for(0..spiralLen) |_| {
					const map = main.server.terrain.ClimateMap.getOrGenerateFragment(wx, wy);
					for(0..map.map.len) |_| {
						const x = main.random.nextIntBounded(u31, &main.seed, map.map.len);
						const y = main.random.nextIntBounded(u31, &main.seed, map.map.len);
						const biomeSize = main.server.terrain.SurfaceMap.MapFragment.biomeSize;
						std.log.info("Trying roughly ({}, {})", .{wx + x*biomeSize, wy + y*biomeSize});
						const sample = map.map[x][y];
						if(sample.biome.isValidPlayerSpawn) {
							for(0..16) |_| {
								self.spawn[0] = wx + x*biomeSize + main.random.nextIntBounded(u31, &seed, biomeSize*2) - biomeSize;
								self.spawn[1] = wy + y*biomeSize + main.random.nextIntBounded(u31, &seed, biomeSize*2) - biomeSize;
								std.log.info("Trying ({}, {})", .{self.spawn[0], self.spawn[1]});
								if(self.isValidSpawnLocation(self.spawn[0], self.spawn[1])) break :foundPosition;
							}
						}
					}
					switch(dir) {
						.dirNegX => wx -%= mapSize,
						.dirPosX => wx +%= mapSize,
						.dirNegY => wy -%= mapSize,
						.dirPosY => wy +%= mapSize,
						else => unreachable,
					}
					stepsRemaining -= 1;
					if(stepsRemaining == 0) {
						switch(dir) {
							.dirNegX => dir = .dirNegY,
							.dirPosX => dir = .dirPosY,
							.dirNegY => dir = .dirPosX,
							.dirPosY => dir = .dirNegX,
							else => unreachable,
						}
						dirChanges += 1;
						// Every second turn the number of steps needed doubles.
						stepsRemaining = dirChanges/2;
					}
				}
				std.log.err("Found no valid spawn location", .{});
			}
			const map = terrain.SurfaceMap.getOrGenerateFragment(self.spawn[0], self.spawn[1], 1);
			self.spawn[2] = map.getHeight(self.spawn[0], self.spawn[1]) + 1;
		}
		const newBiomeCheckSum: i64 = @bitCast(terrain.biomes.getBiomeCheckSum(self.seed));
		if(newBiomeCheckSum != self.biomeChecksum) {
			if(self.testingMode) {
				const dir = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps", .{self.path}) catch unreachable;
				defer main.stackAllocator.free(dir);
				main.files.cubyzDir().deleteTree("maps") catch |err| {
					std.log.err("Error while trying to remove maps folder of testingMode world: {s}", .{@errorName(err)});
				};
			} else {
				self.regenerateLOD(newBiomeCheckSum) catch |err| {
					std.log.err("Error while trying to regenerate LODs: {s}", .{@errorName(err)});
				};
			}
		}
		try self.wio.saveWorldData();
		loadItemDrops: {
			const itemsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/itemdrops.bin", .{self.path}) catch unreachable;
			defer main.stackAllocator.free(itemsPath);
			const itemDropData: []const u8 = files.cubyzDir().read(main.stackAllocator, itemsPath) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Got error while loading {s}: {s}", .{itemsPath, @errorName(err)});
				}
				break :loadItemDrops;
			};
			defer main.stackAllocator.free(itemDropData);
			var reader = main.utils.BinaryReader.init(itemDropData);
			self.itemDropManager.loadFromBytes(&reader) catch |err| {
				std.log.err("Failed to load item drop data: {s}", .{@errorName(err)});
				std.log.debug("Data: {any}", .{itemDropData});
			};
		}
	}

	pub fn findPlayer(self: *ServerWorld, user: *User) void {
		const dest: []u8 = main.stackAllocator.alloc(u8, std.base64.url_safe.Encoder.calcSize(user.name.len));
		defer main.stackAllocator.free(dest);
		const hashedName = std.base64.url_safe.Encoder.encode(dest, user.name);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{s}.zig.zon", .{self.path, hashedName}) catch unreachable;
		defer main.stackAllocator.free(path);

		const playerData = files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
		defer playerData.deinit(main.stackAllocator);
		const player = &user.player;
		if(playerData == .null) {
			player.pos = @floatFromInt(self.spawn);

			main.items.Inventory.Sync.setGamemode(user, self.defaultGamemode);
		} else {
			player.loadFrom(playerData.getChild("entity"));

			main.items.Inventory.Sync.setGamemode(user, std.meta.stringToEnum(main.game.Gamemode, playerData.get([]const u8, "gamemode", @tagName(self.defaultGamemode))) orelse self.defaultGamemode);
		}
		user.inventory = loadPlayerInventory(main.game.Player.inventorySize, playerData.get([]const u8, "playerInventory", ""), .{.playerInventory = user.id}, path);
		user.handInventory = loadPlayerInventory(1, playerData.get([]const u8, "hand", ""), .{.hand = user.id}, path);
	}

	fn loadPlayerInventory(size: usize, base64EncodedData: []const u8, source: main.items.Inventory.Source, playerDataFilePath: []const u8) main.items.Inventory.InventoryId {
		const decodedSize = std.base64.url_safe.Decoder.calcSizeForSlice(base64EncodedData) catch |err| blk: {
			std.log.err("Encountered incorrectly encoded inventory data ({s}) while loading data from file '{s}': '{s}'", .{@errorName(err), playerDataFilePath, base64EncodedData});
			break :blk 0;
		};

		const bytes: []u8 = main.stackAllocator.alloc(u8, decodedSize);
		defer main.stackAllocator.free(bytes);

		var readerInput: []const u8 = bytes;

		std.base64.url_safe.Decoder.decode(bytes, base64EncodedData) catch |err| {
			std.log.err("Encountered incorrectly encoded inventory data ({s}) while loading data from file '{s}': '{s}'", .{@errorName(err), playerDataFilePath, base64EncodedData});
			readerInput = "";
		};
		var reader: main.utils.BinaryReader = .init(readerInput);
		return main.items.Inventory.Sync.ServerSide.createExternallyManagedInventory(size, .normal, source, &reader, .{});
	}

	fn savePlayerInventory(allocator: NeverFailingAllocator, inv: main.items.Inventory) []const u8 {
		var writer = main.utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();

		inv.toBytes(&writer);

		const destination: []u8 = allocator.alloc(u8, std.base64.url_safe.Encoder.calcSize(writer.data.items.len));
		return std.base64.url_safe.Encoder.encode(destination, writer.data.items);
	}

	pub fn savePlayer(self: *ServerWorld, user: *User) !void {
		const dest: []u8 = main.stackAllocator.alloc(u8, std.base64.url_safe.Encoder.calcSize(user.name.len));
		defer main.stackAllocator.free(dest);
		const hashedName = std.base64.url_safe.Encoder.encode(dest, user.name);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{s}.zig.zon", .{self.path, hashedName}) catch unreachable;
		defer main.stackAllocator.free(path);

		var playerZon: ZonElement = files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
		defer playerZon.deinit(main.stackAllocator);

		if(playerZon != .object) {
			playerZon.deinit(main.stackAllocator);
			playerZon = ZonElement.initObject(main.stackAllocator);
		}

		playerZon.put("name", user.name);

		playerZon.put("entity", user.player.save(main.stackAllocator));
		playerZon.put("gamemode", @tagName(user.gamemode.load(.monotonic)));

		{
			main.items.Inventory.Sync.ServerSide.mutex.lock();
			defer main.items.Inventory.Sync.ServerSide.mutex.unlock();
			if(main.items.Inventory.Sync.ServerSide.getInventoryFromSource(.{.playerInventory = user.id})) |inv| {
				playerZon.put("playerInventory", ZonElement{.stringOwned = savePlayerInventory(main.stackAllocator, inv)});
			} else @panic("The player inventory wasn't found. Cannot save player data.");

			if(main.items.Inventory.Sync.ServerSide.getInventoryFromSource(.{.hand = user.id})) |inv| {
				playerZon.put("hand", ZonElement{.stringOwned = savePlayerInventory(main.stackAllocator, inv)});
			} else @panic("The player hand inventory wasn't found. Cannot save player data.");
		}

		const playerPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players", .{self.path}) catch unreachable;
		defer main.stackAllocator.free(playerPath);

		try files.cubyzDir().makePath(playerPath);

		try files.cubyzDir().writeZon(path, playerZon);
	}

	pub fn saveAllPlayers(self: *ServerWorld) !void {
		const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);

		for(userList) |user| {
			try savePlayer(self, user);
		}
	}

	pub fn forceSave(self: *ServerWorld) !void {
		// TODO: Save chunks and player data
		try self.wio.saveWorldData();

		try self.saveAllPlayers();

		var itemDropData = main.utils.BinaryWriter.init(main.stackAllocator);
		defer itemDropData.deinit();
		self.itemDropManager.storeToBytes(&itemDropData);
		const itemsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/itemdrops.bin", .{self.path}) catch unreachable;
		defer main.stackAllocator.free(itemsPath);
		try files.cubyzDir().write(itemsPath, itemDropData.data.items);
	}

	fn isValidSpawnLocation(_: *ServerWorld, wx: i32, wy: i32) bool {
		const map = terrain.SurfaceMap.getOrGenerateFragment(wx, wy, 1);
		return map.getBiome(wx, wy).isValidPlayerSpawn;
	}

	pub fn dropWithCooldown(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32, pickupCooldown: i32) void {
		const vel: Vec3d = @floatCast(dir*@as(Vec3f, @splat(velocity)));
		const rot = main.random.nextFloatVector(3, &main.seed)*@as(Vec3f, @splat(2*std.math.pi));
		self.itemDropManager.add(pos, vel, rot, stack, server.updatesPerSec*900, pickupCooldown);
	}

	pub fn drop(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32) void {
		self.dropWithCooldown(stack, pos, dir, velocity, 0);
	}

	fn tickBlocksInChunk(self: *ServerWorld, _chunk: *chunk.ServerChunk) void {
		for(0..self.tickSpeed.load(.monotonic)) |_| {
			const blockIndex: i32 = main.random.nextInt(i32, &main.seed);

			const x: i32 = blockIndex >> chunk.chunkShift2 & chunk.chunkMask;
			const y: i32 = blockIndex >> chunk.chunkShift & chunk.chunkMask;
			const z: i32 = blockIndex & chunk.chunkMask;

			_chunk.mutex.lock();
			const block = _chunk.getBlock(x, y, z);
			_chunk.mutex.unlock();
			_ = block.onTick().run(.{.block = block, .chunk = _chunk, .x = x, .y = y, .z = z});
		}
	}

	fn tick(self: *ServerWorld) void {
		ChunkManager.mutex.lock();
		var iter = ChunkManager.entityChunkHashMap.valueIterator();
		var currentChunks: main.ListUnmanaged(*EntityChunk) = .initCapacity(main.stackAllocator, iter.len);
		defer currentChunks.deinit(main.stackAllocator);
		while(iter.next()) |entityChunk| {
			entityChunk.*.increaseRefCount();
			currentChunks.append(main.stackAllocator, entityChunk.*);
		}
		ChunkManager.mutex.unlock();

		// tick blocks
		for(currentChunks.items) |entityChunk| {
			defer entityChunk.decreaseRefCount();
			const ch = entityChunk.getChunk() orelse continue;
			self.tickBlocksInChunk(ch);
		}
	}

	pub fn update(self: *ServerWorld) void { // MARK: update()
		const newTime = std.time.milliTimestamp();
		var deltaTime = @as(f32, @floatFromInt(newTime - self.lastUpdateTime))/1000.0;
		self.lastUpdateTime = newTime;
		if(deltaTime > 0.3) {
			std.log.warn("Update time is getting too high. It's already at {} s!", .{deltaTime});
			deltaTime = 0.3;
		}

		while(self.milliTime + 100 < newTime) {
			self.milliTime += 100;
			if(self.doGameTimeCycle) self.gameTime +%= 1; // gameTime is measured in 100ms.
		}
		if(self.lastUnimportantDataSent + 2000 < newTime) { // Send unimportant data every ~2s.
			self.lastUnimportantDataSent = newTime;
			const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
			for(userList) |user| {
				main.network.Protocols.genericUpdate.sendTime(user.conn, self);
			}
		}
		self.tick();
		// TODO: Entities

		// Item Entities
		self.itemDropManager.update(deltaTime);
		{ // Collect item entities:
			const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
			for(userList) |user| {
				self.itemDropManager.checkEntity(user);
			}
		}

		// Store chunks and regions.
		// Stores at least one chunk and one region per iteration.
		// All chunks and regions will be stored within the storage time.
		const insertionTime = newTime -% main.settings.storageTime;
		self.mutex.lock();
		defer self.mutex.unlock();
		while(self.chunkUpdateQueue.popFront()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
			if(updateRequest.milliTimeStamp -% insertionTime <= 0) break;
		}
		while(self.regionUpdateQueue.popFront()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
			if(updateRequest.milliTimeStamp -% insertionTime <= 0) break;
		}
	}

	pub fn queueChunkAndDecreaseRefCount(self: *ServerWorld, pos: ChunkPosition, source: *User) void {
		self.chunkManager.queueChunkAndDecreaseRefCount(pos, source);
	}

	pub fn queueLightMapAndDecreaseRefCount(self: *ServerWorld, pos: terrain.SurfaceMap.MapFragmentPosition, source: *User) void {
		self.chunkManager.queueLightMapAndDecreaseRefCount(pos, source);
	}

	pub fn getSimulationChunkAndIncreaseRefCount(_: *ServerWorld, x: i32, y: i32, z: i32) ?*EntityChunk {
		if(ChunkManager.getEntityChunkAndIncreaseRefCount(.{.wx = x & ~@as(i32, chunk.chunkMask), .wy = y & ~@as(i32, chunk.chunkMask), .wz = z & ~@as(i32, chunk.chunkMask), .voxelSize = 1})) |entityChunk| {
			return entityChunk;
		}
		return null;
	}

	pub fn getOrGenerateChunkAndIncreaseRefCount(_: *ServerWorld, pos: chunk.ChunkPosition) *ServerChunk {
		return ChunkManager.getOrGenerateChunkAndIncreaseRefCount(pos);
	}

	pub fn getChunkFromCacheAndIncreaseRefCount(_: *ServerWorld, pos: chunk.ChunkPosition) ?*ServerChunk {
		return ChunkManager.getChunkFromCacheAndIncreaseRefCount(pos);
	}

	pub fn getBiome(_: *const ServerWorld, wx: i32, wy: i32, wz: i32) *const terrain.biomes.Biome {
		const map = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView.init(main.stackAllocator, .{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1}, 1, 0);
		defer map.deinit();
		return map.getRoughBiome(wx, wy, wz, false, undefined, true);
	}

	pub fn getBlock(self: *ServerWorld, x: i32, y: i32, z: i32) ?Block {
		const chunkPos = Vec3i{x, y, z} & ~@as(Vec3i, @splat(main.chunk.chunkMask));
		const otherChunk = self.getSimulationChunkAndIncreaseRefCount(chunkPos[0], chunkPos[1], chunkPos[2]) orelse return null;
		defer otherChunk.decreaseRefCount();
		const ch = otherChunk.getChunk() orelse return null;
		ch.mutex.lock();
		defer ch.mutex.unlock();
		return ch.getBlock(x - ch.super.pos.wx, y - ch.super.pos.wy, z - ch.super.pos.wz);
	}

	pub fn getBlockAndBlockEntityData(self: *ServerWorld, x: i32, y: i32, z: i32, blockEntityDataWriter: *utils.BinaryWriter) ?Block {
		const chunkPos = Vec3i{x, y, z} & ~@as(Vec3i, @splat(main.chunk.chunkMask));
		const otherChunk = self.getSimulationChunkAndIncreaseRefCount(chunkPos[0], chunkPos[1], chunkPos[2]) orelse return null;
		defer otherChunk.decreaseRefCount();
		const ch = otherChunk.getChunk() orelse return null;
		ch.mutex.lock();
		defer ch.mutex.unlock();
		const block = ch.getBlock(x - ch.super.pos.wx, y - ch.super.pos.wy, z - ch.super.pos.wz);
		if(block.blockEntity()) |blockEntity| {
			blockEntity.getServerToClientData(.{x, y, z}, &ch.super, blockEntityDataWriter);
		}
		return block;
	}

	/// Returns the actual block on failure
	pub fn cmpxchgBlock(_: *ServerWorld, wx: i32, wy: i32, wz: i32, oldBlock: ?Block, _newBlock: Block) ?Block {
		main.utils.assertLocked(&main.items.Inventory.Sync.ServerSide.mutex); // Block entities with inventories need this mutex to be locked
		const baseChunk = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{.wx = wx & ~@as(i32, chunk.chunkMask), .wy = wy & ~@as(i32, chunk.chunkMask), .wz = wz & ~@as(i32, chunk.chunkMask), .voxelSize = 1});
		defer baseChunk.decreaseRefCount();
		const x: u5 = @intCast(wx & chunk.chunkMask);
		const y: u5 = @intCast(wy & chunk.chunkMask);
		const z: u5 = @intCast(wz & chunk.chunkMask);
		baseChunk.mutex.lock();
		const currentBlock = baseChunk.getBlock(x, y, z);
		if(oldBlock != null) {
			if(oldBlock.? != currentBlock) {
				baseChunk.mutex.unlock();
				return currentBlock;
			}
		}
		baseChunk.mutex.unlock();

		var newBlock = _newBlock;
		for(chunk.Neighbor.iterable) |neighbor| {
			const nx = x + neighbor.relX();
			const ny = y + neighbor.relY();
			const nz = z + neighbor.relZ();
			var ch = baseChunk;
			if(!ch.liesInChunk(nx, ny, nz)) {
				ch = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{
					.wx = baseChunk.super.pos.wx + nx & ~@as(i32, chunk.chunkMask),
					.wy = baseChunk.super.pos.wy + ny & ~@as(i32, chunk.chunkMask),
					.wz = baseChunk.super.pos.wz + nz & ~@as(i32, chunk.chunkMask),
					.voxelSize = 1,
				});
			}
			defer if(ch != baseChunk) {
				ch.decreaseRefCount();
			};

			ch.mutex.lock();
			defer ch.mutex.unlock();

			var neighborBlock = ch.getBlock(nx & chunk.chunkMask, ny & chunk.chunkMask, nz & chunk.chunkMask);
			if(neighborBlock.mode().dependsOnNeighbors and neighborBlock.mode().updateData(&neighborBlock, neighbor.reverse(), newBlock)) {
				ch.updateBlockAndSetChanged(nx & chunk.chunkMask, ny & chunk.chunkMask, nz & chunk.chunkMask, neighborBlock);
			}
			if(newBlock.mode().dependsOnNeighbors) {
				_ = newBlock.mode().updateData(&newBlock, neighbor, neighborBlock);
			}
		}
		baseChunk.mutex.lock();
		defer baseChunk.mutex.unlock();

		if(currentBlock != _newBlock) {
			if(currentBlock.blockEntity()) |blockEntity| blockEntity.updateServerData(.{wx, wy, wz}, &baseChunk.super, .remove) catch |err| {
				std.log.err("Got error {s} while trying to remove entity data in position {} for block {s}", .{@errorName(err), Vec3i{wx, wy, wz}, currentBlock.id()});
			};
		}
		baseChunk.updateBlockAndSetChanged(x, y, z, newBlock);

		const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);

		for(userList) |user| {
			main.network.Protocols.blockUpdate.send(user.conn, &.{.{.x = wx, .y = wy, .z = wz, .newBlock = newBlock, .blockEntityData = &.{}}});
		}
		return null;
	}

	pub fn updateBlock(self: *ServerWorld, wx: i32, wy: i32, wz: i32, newBlock: Block) void {
		_ = self.cmpxchgBlock(wx, wy, wz, null, newBlock);
	}

	pub fn queueChunkUpdateAndDecreaseRefCount(self: *ServerWorld, ch: *ServerChunk) void {
		self.mutex.lock();
		self.chunkUpdateQueue.pushBack(.{.ch = ch, .milliTimeStamp = std.time.milliTimestamp()});
		self.mutex.unlock();
	}

	pub fn queueRegionFileUpdateAndDecreaseRefCount(self: *ServerWorld, region: *storage.RegionFile) void {
		self.mutex.lock();
		self.regionUpdateQueue.pushBack(.{.region = region, .milliTimeStamp = std.time.milliTimestamp()});
		self.mutex.unlock();
	}
};
