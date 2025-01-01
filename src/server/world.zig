const std = @import("std");

const main = @import("root");
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

const server = @import("server.zig");
const User = server.User;
const Entity = server.Entity;

const storage = @import("storage.zig");

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
	var chunkCache: Cache(ServerChunk, reducedChunkCacheMask+1, 4, chunkDeinitFunctionForCache) = .{};
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
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
			.taskType = .chunkgen,
		};
		
		pub fn scheduleAndDecreaseRefCount(pos: ChunkPosition, source: Source) void {
			const task = main.globalAllocator.create(ChunkLoadTask);
			task.* = ChunkLoadTask {
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
			switch (self.source) {
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
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
			.taskType = .misc,
		};
		
		pub fn scheduleAndDecreaseRefCount(pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
			const task = main.globalAllocator.create(LightMapLoadTask);
			task.* = LightMapLoadTask {
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
			const map = terrain.LightMap.getOrGenerateFragmentAndIncreaseRefCount(self.pos.wx, self.pos.wy, self.pos.voxelSize);
			defer map.decreaseRefCount();
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
		const self = ChunkManager {
			.world = world,
			.terrainGenerationProfile = try server.terrain.TerrainGenerationProfile.init(settings, world.seed),
		};
		entityChunkHashMap = .init(main.globalAllocator.allocator);
		server.terrain.init(self.terrainGenerationProfile);
		storage.init();
		return self;
	}

	pub fn deinit(self: ChunkManager) void {
		for(0..main.settings.highestSupportedLod) |_| {
			chunkCache.clear();
		}
		entityChunkHashMap.deinit();
		server.terrain.deinit();
		main.assets.unloadAssets();
		self.terrainGenerationProfile.deinit();
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
			storage.ChunkCompression.decompressChunk(&ch.super, data) catch {
				std.log.err("Storage for chunk {} in region file at {} is corrupted", .{pos, region.pos});
				break :blk;
			};
			ch.wasStored = true;
			return ch;
		}
		ch.generated = true;
		const caveMap = terrain.CaveMap.CaveMapView.init(ch);
		defer caveMap.deinit();
		const biomeMap = terrain.CaveBiomeMap.CaveBiomeMapView.init(main.stackAllocator, ch.super.pos, ch.super.width, 32);
		defer biomeMap.deinit();
		for(server.world.?.chunkManager.terrainGenerationProfile.generators) |generator| {
			generator.generate(server.world.?.seed ^ generator.generatorSeed, ch, caveMap, biomeMap);
		}
		if(pos.voxelSize != 1) { // Generate LOD replacements
			for(ch.super.data.palette[0..ch.super.data.paletteLength]) |*block| {
				block.typ = block.lodReplacement();
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

const WorldIO = struct { // MARK: WorldIO
	const worldDataVersion: u32 = 2;

	dir: files.Dir,
	world: *ServerWorld,

	pub fn init(dir: files.Dir, world: *ServerWorld) WorldIO {
		return WorldIO {
			.dir = dir,
			.world = world,
		};
	}

	pub fn deinit(self: *WorldIO) void {
		self.dir.close();
	}

	pub fn hasWorldData(self: WorldIO) bool {
		return self.dir.hasFile("world.zig.zon");
	}

	/// Load the seed, which is needed before custom item and ore generation.
	pub fn loadWorldSeed(self: WorldIO) !u64 {
		const worldData = try self.dir.readToZon(main.stackAllocator, "world.zig.zon");
		defer worldData.deinit(main.stackAllocator);
		if(worldData.get(u32, "version", 0) != worldDataVersion) {
			std.log.err("Cannot read world file version {}. Expected version {}.", .{worldData.get(u32, "version", 0), worldDataVersion});
			return error.OldWorld;
		}
		return worldData.get(u64, "seed", 0);
	}

	pub fn loadWorldData(self: WorldIO) !void {
		const worldData = try self.dir.readToZon(main.stackAllocator, "world.zig.zon");
		defer worldData.deinit(main.stackAllocator);

		self.world.doGameTimeCycle = worldData.get(bool, "doGameTimeCycle", true);
		self.world.gameTime = worldData.get(i64, "gameTime", 0);
		self.world.spawn = worldData.get(Vec3i, "spawn", .{0, 0, 0});
		self.world.biomeChecksum = worldData.get(i64, "biomeChecksum", 0);
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
		// TODO: Save entities
		try self.dir.writeZon("world.zig.zon", worldData);
	}
};

pub const ServerWorld = struct { // MARK: ServerWorld
	pub const dayCycle: u31 = 12000; // Length of one in-game day in units of 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	pub const earthGravity: f32 = 9.81;

	itemDropManager: ItemDropManager = undefined,
	blockPalette: *main.assets.Palette = undefined,
	biomePalette: *main.assets.Palette = undefined,
	chunkManager: ChunkManager = undefined,

	generated: bool = false,

	gameTime: i64 = 0,
	milliTime: i64,
	lastUpdateTime: i64,
	lastUnimportantDataSent: i64,
	doGameTimeCycle: bool = true,
	gravity: f32 = earthGravity,

	seed: u64,
	name: []const u8,
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

	pub fn init(name: []const u8, nullGeneratorSettings: ?ZonElement) !*ServerWorld { // MARK: init()
		covert_old_worlds: { // TODO: Remove after #480
			const worldDatPath = try std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/world.dat", .{name});
			defer main.stackAllocator.free(worldDatPath);
			if(std.fs.cwd().openFile(worldDatPath, .{})) |file| {
				file.close();
				std.log.warn("Detected old world in saves/{s}. Converting all .json files to .zig.zon", .{name});
				const dirPath = try std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}", .{name});
				defer main.stackAllocator.free(dirPath);
				var dir = std.fs.cwd().openDir(dirPath, .{.iterate = true}) catch |err| {
					std.log.err("Could not open world directory to convert json files: {s}. Conversion aborted", .{@errorName(err)});
					break :covert_old_worlds;
				};
				defer dir.close();

				var walker = dir.walk(main.stackAllocator.allocator) catch unreachable;
				defer walker.deinit();
				while(walker.next() catch |err| {
					std.log.err("Got error while iterating through json files directory: {s}", .{@errorName(err)});
					break :covert_old_worlds;
				}) |entry| {
					if(entry.kind == .file and (std.ascii.endsWithIgnoreCase(entry.basename, ".json") or std.mem.eql(u8, entry.basename, "world.dat"))) {
						const fullPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}", .{dirPath, entry.path}) catch unreachable;
						defer main.stackAllocator.free(fullPath);
						main.convertJsonToZon(fullPath);
					}
				}
			} else |_| {}
		}
		const self = main.globalAllocator.create(ServerWorld);
		errdefer main.globalAllocator.destroy(self);
		self.* = ServerWorld {
			.lastUpdateTime = std.time.milliTimestamp(),
			.milliTime = std.time.milliTimestamp(),
			.lastUnimportantDataSent = std.time.milliTimestamp(),
			.seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp()))),
			.name = main.globalAllocator.dupe(u8, name),
			.chunkUpdateQueue = .init(main.globalAllocator, 256),
			.regionUpdateQueue = .init(main.globalAllocator, 256),
		};
		self.itemDropManager.init(main.globalAllocator, self, self.gravity);
		errdefer self.itemDropManager.deinit();

		var loadArena = main.utils.NeverFailingArenaAllocator.init(main.stackAllocator);
		defer loadArena.deinit();
		const arenaAllocator = loadArena.allocator();
		var buf: [32768]u8 = undefined;
		var generatorSettings: ZonElement = undefined;
		if(nullGeneratorSettings) |_generatorSettings| {
			generatorSettings = _generatorSettings;
			// Store generator settings:
			try files.writeZon(try std.fmt.bufPrint(&buf, "saves/{s}/generatorSettings.zig.zon", .{name}), generatorSettings);
		} else { // Read the generator settings:
			generatorSettings = try files.readToZon(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/generatorSettings.zig.zon", .{name}));
		}
		self.wio = WorldIO.init(try files.openDir(try std.fmt.bufPrint(&buf, "saves/{s}", .{name})), self);
		errdefer self.wio.deinit();
		const blockPaletteZon = files.readToZon(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/palette.zig.zon", .{name})) catch .null;
		self.blockPalette = try main.assets.Palette.init(main.globalAllocator, blockPaletteZon, "cubyz:air");
		errdefer self.blockPalette.deinit();
		const biomePaletteZon = files.readToZon(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/biome_palette.zig.zon", .{name})) catch .null;
		self.biomePalette = try main.assets.Palette.init(main.globalAllocator, biomePaletteZon, null);
		errdefer self.biomePalette.deinit();
		errdefer main.assets.unloadAssets();
		if(self.wio.hasWorldData()) {
			self.seed = try self.wio.loadWorldSeed();
			self.generated = true;
			try main.assets.loadWorldAssets(try std.fmt.bufPrint(&buf, "saves/{s}/assets/", .{name}), self.blockPalette, self.biomePalette);
		} else {
			self.seed = main.random.nextInt(u48, &main.seed);
			try main.assets.loadWorldAssets(try std.fmt.bufPrint(&buf, "saves/{s}/assets/", .{name}), self.blockPalette, self.biomePalette);
			try self.wio.saveWorldData();
		}
		// Store the block palette now that everything is loaded.
		try files.writeZon(try std.fmt.bufPrint(&buf, "saves/{s}/palette.zig.zon", .{name}), self.blockPalette.save(arenaAllocator));
		try files.writeZon(try std.fmt.bufPrint(&buf, "saves/{s}/biome_palette.zig.zon", .{name}), self.biomePalette.save(arenaAllocator));

		self.chunkManager = try ChunkManager.init(self, generatorSettings);
		errdefer self.chunkManager.deinit();
		return self;
	}

	pub fn deinit(self: *ServerWorld) void {
		self.forceSave() catch |err| {
			std.log.err("Error while saving the world: {s}", .{@errorName(err)});
		};
		while(self.chunkUpdateQueue.dequeue()) |updateRequest| {
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
		}
		self.chunkUpdateQueue.deinit();
		while(self.regionUpdateQueue.dequeue()) |updateRequest| {
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
		}
		self.regionUpdateQueue.deinit();
		self.chunkManager.deinit();
		self.itemDropManager.deinit();
		self.blockPalette.deinit();
		self.biomePalette.deinit();
		self.wio.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}


	const RegenerateLODTask = struct { // MARK: RegenerateLODTask
		pos: ChunkPosition,
		storeMaps: bool,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
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
							const pos = ChunkPosition {
								.wx = self.pos.wx + @as(i32, @intCast(x))*chunk.chunkSize,
								.wy = self.pos.wy + @as(i32, @intCast(y))*chunk.chunkSize,
								.wz = self.pos.wz + @as(i32, @intCast(z))*chunk.chunkSize,
								.voxelSize = 1,
							};
							const ch = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(pos);
							defer ch.decreaseRefCount();
							if(self.storeMaps and ch.super.pos.voxelSize == 1) { // TODO: Remove after first release
								// Store the surrounding map pieces as well:
								const mapStartX = ch.super.pos.wx -% main.server.terrain.SurfaceMap.MapFragment.mapSize/2 & ~@as(i32, main.server.terrain.SurfaceMap.MapFragment.mapMask);
								const mapStartY = ch.super.pos.wy -% main.server.terrain.SurfaceMap.MapFragment.mapSize/2 & ~@as(i32, main.server.terrain.SurfaceMap.MapFragment.mapMask);
								for(0..2) |dx| {
									for(0..2) |dy| {
										const mapX = mapStartX +% main.server.terrain.SurfaceMap.MapFragment.mapSize*@as(i32, @intCast(dx));
										const mapY = mapStartY +% main.server.terrain.SurfaceMap.MapFragment.mapSize*@as(i32, @intCast(dy));
										const map = main.server.terrain.SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(mapX, mapY, ch.super.pos.voxelSize);
										defer map.decreaseRefCount();
										if(!map.wasStored.swap(true, .monotonic)) {
											map.save(null, .{});
										}
									}
								}
							}
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
		const hasSurfaceMaps = blk: {
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps", .{self.name}) catch unreachable;
			defer main.stackAllocator.free(path);
			var dir = std.fs.cwd().openDir(path, .{}) catch break :blk false;
			defer dir.close();
			break :blk true;
		};
		if(hasSurfaceMaps) {
			try terrain.SurfaceMap.regenerateLOD(self.name);
		}
		// Delete old LODs:
		for(1..main.settings.highestSupportedLod+1) |i| {
			const lod = @as(u32, 1) << @intCast(i);
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks", .{self.name}) catch unreachable;
			defer main.stackAllocator.free(path);
			const dir = std.fmt.allocPrint(main.stackAllocator.allocator, "{}", .{lod}) catch unreachable;
			defer main.stackAllocator.free(dir);
			main.files.deleteDir(path, dir) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Error while deleting directory {s}/{s}: {s}", .{path, dir, @errorName(err)});
				}
			};
		}
		// Find all the stored chunks:
		var chunkPositions = main.List(ChunkPosition).init(main.stackAllocator);
		defer chunkPositions.deinit();
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks/1", .{self.name}) catch unreachable;
		defer main.stackAllocator.free(path);
		blk: {
			var dirX = std.fs.cwd().openDir(path, .{.iterate = true}) catch |err| {
				if(err == error.FileNotFound) break :blk;
				return err;
			};
			defer dirX.close();
			var iterX = dirX.iterate();
			while(try iterX.next()) |entryX| {
				if(entryX.kind != .directory) continue;
				const wx = std.fmt.parseInt(i32, entryX.name, 0) catch continue;
				var dirY = try dirX.openDir(entryX.name, .{.iterate = true});
				defer dirY.close();
				var iterY = dirY.iterate();
				while(try iterY.next()) |entryY| {
					if(entryY.kind != .directory) continue;
					const wy = std.fmt.parseInt(i32, entryY.name, 0) catch continue;
					var dirZ = try dirY.openDir(entryY.name, .{.iterate = true});
					defer dirZ.close();
					var iterZ = dirZ.iterate();
					while(try iterZ.next()) |entryZ| {
						if(entryZ.kind != .file) continue;
						const nameZ = entryZ.name[0..std.mem.indexOfScalar(u8, entryZ.name, '.') orelse entryZ.name.len];
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
			while(self.chunkUpdateQueue.dequeue()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.ch.save(self);
				updateRequest.ch.decreaseRefCount();
			}
			while(self.regionUpdateQueue.dequeue()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.region.store();
				updateRequest.region.decreaseRefCount();
			}
			self.mutex.unlock();
			std.time.sleep(1_000_000);
			self.mutex.lock();
			if(main.threadPool.queueSize() == 0 and self.chunkUpdateQueue.peek() == null and self.regionUpdateQueue.peek() == null) break;
		}
		std.log.info("Finished LOD update.", .{});

		self.biomeChecksum = newBiomeCheckSum;
	}

	pub fn generate(self: *ServerWorld) !void {
		try self.wio.loadWorldData(); // load data here in order for entities to also be loaded.

		if(!self.generated) {
			var seed: u64 = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
			std.log.info("Finding position..", .{});
			for(0..1000) |_| {
				self.spawn[0] = main.random.nextIntBounded(u31, &seed, 65536);
				self.spawn[1] = main.random.nextIntBounded(u31, &seed, 65536);
				std.log.info("Trying ({}, {})", .{self.spawn[0], self.spawn[1]});
				if(self.isValidSpawnLocation(self.spawn[0], self.spawn[1])) break;
			}
			const map = terrain.SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(self.spawn[0], self.spawn[1], 1);
			defer map.decreaseRefCount();
			self.spawn[2] = map.getHeight(self.spawn[0], self.spawn[1]) + 1;
		}
		self.generated = true;
		const newBiomeCheckSum: i64 = @bitCast(terrain.biomes.getBiomeCheckSum(self.seed));
		if(newBiomeCheckSum != self.biomeChecksum) {
			self.regenerateLOD(newBiomeCheckSum) catch |err| {
				std.log.err("Error while trying to regenerate LODs: {s}", .{@errorName(err)});
			};
		}
		try self.wio.saveWorldData();
		var buf: [32768]u8 = undefined;
		const zon = files.readToZon(main.stackAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/items.zig.zon", .{self.name})) catch .null;
		defer zon.deinit(main.stackAllocator);
		self.itemDropManager.loadFrom(zon);
	}


	pub fn findPlayer(self: *ServerWorld, user: *User) void {
		var buf: [1024]u8 = undefined;
		const playerData = files.readToZon(main.stackAllocator, std.fmt.bufPrint(&buf, "saves/{s}/player/{s}.zig.zon", .{self.name, user.name}) catch "") catch .null; // TODO: Utils.escapeFolderName(user.name)
		defer playerData.deinit(main.stackAllocator);
		const player = &user.player;
		if(playerData == .null) {
			// Generate a new player:
			player.pos = @floatFromInt(self.spawn);
		} else {
			player.loadFrom(playerData);
		}
	}

	pub fn forceSave(self: *ServerWorld) !void {
		// TODO: Save chunks and player data
		try self.wio.saveWorldData();
		const itemDropZon = self.itemDropManager.store(main.stackAllocator);
		defer itemDropZon.deinit(main.stackAllocator);
		var buf: [32768]u8 = undefined;
		try files.writeZon(try std.fmt.bufPrint(&buf, "saves/{s}/items.zig.zon", .{self.name}), itemDropZon);
	}

	fn isValidSpawnLocation(_: *ServerWorld, wx: i32, wy: i32) bool {
		const map = terrain.SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(wx, wy, 1);
		defer map.decreaseRefCount();
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
			if(self.doGameTimeCycle) self.gameTime += 1; // gameTime is measured in 100ms.
		}
		if(self.lastUnimportantDataSent + 2000 < newTime) {// Send unimportant data every ~2s.
			self.lastUnimportantDataSent = newTime;
			const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
			for(userList) |user| {
				main.network.Protocols.genericUpdate.sendTimeAndBiome(user.conn, self);
			}
		}
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
		while(self.chunkUpdateQueue.dequeue()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
			if(updateRequest.milliTimeStamp -% insertionTime <= 0) break;
		}
		while(self.regionUpdateQueue.dequeue()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
			if(updateRequest.milliTimeStamp -% insertionTime <= 0) break;
		}
	}

	pub fn queueChunks(self: *ServerWorld, positions: []ChunkPosition, source: ?*User) void {
		for(positions) |pos| {
			self.queueChunk(pos, source);
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

	/// Returns the actual block on failure
	pub fn cmpxchgBlock(_: *ServerWorld, wx: i32, wy: i32, wz: i32, oldBlock: ?Block, _newBlock: Block) ?Block {
		const baseChunk = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{.wx = wx & ~@as(i32, chunk.chunkMask), .wy = wy & ~@as(i32, chunk.chunkMask), .wz = wz & ~@as(i32, chunk.chunkMask), .voxelSize = 1});
		defer baseChunk.decreaseRefCount();
		const x: u5 = @intCast(wx & chunk.chunkMask);
		const y: u5 = @intCast(wy & chunk.chunkMask);
		const z: u5 = @intCast(wz & chunk.chunkMask);
		baseChunk.mutex.lock();
		const currentBlock = baseChunk.getBlock(x, y, z);
		if(oldBlock != null) {
			if(!std.meta.eql(oldBlock.?, currentBlock)) {
				baseChunk.mutex.unlock();
				return currentBlock;
			}
			baseChunk.updateBlockAndSetChanged(x, y, z, _newBlock);
		}
		baseChunk.mutex.unlock();
		var newBlock = _newBlock;
		for(chunk.Neighbor.iterable) |neighbor| {
			const nx = x + neighbor.relX();
			const ny = y + neighbor.relY();
			const nz = z + neighbor.relZ();
			var ch = baseChunk;
			if(nx & chunk.chunkMask != nx or ny & chunk.chunkMask != ny or nz & chunk.chunkMask != nz) {
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
			if(neighborBlock.mode().dependsOnNeighbors) {
				if(neighborBlock.mode().updateData(&neighborBlock, neighbor.reverse(), newBlock)) {
					ch.updateBlockAndSetChanged(nx & chunk.chunkMask, ny & chunk.chunkMask, nz & chunk.chunkMask, neighborBlock);
				}
			}
			if(newBlock.mode().dependsOnNeighbors) {
				_ = newBlock.mode().updateData(&newBlock, neighbor, neighborBlock);
			}
		}
		baseChunk.mutex.lock();
		defer baseChunk.mutex.unlock();
		baseChunk.updateBlockAndSetChanged(x, y, z, newBlock);
		const userList = server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
		for(userList) |user| {
			main.network.Protocols.blockUpdate.send(user.conn, wx, wy, wz, _newBlock);
		}
		return null;
	}

	pub fn updateBlock(self: *ServerWorld, wx: i32, wy: i32, wz: i32, newBlock: Block) void {
		_ = self.cmpxchgBlock(wx, wy, wz, null, newBlock);
	}

	pub fn queueChunkUpdateAndDecreaseRefCount(self: *ServerWorld, ch: *ServerChunk) void {
		self.mutex.lock();
		self.chunkUpdateQueue.enqueue(.{.ch = ch, .milliTimeStamp = std.time.milliTimestamp()});
		self.mutex.unlock();
	}

	pub fn queueRegionFileUpdateAndDecreaseRefCount(self: *ServerWorld, region: *storage.RegionFile) void {
		self.mutex.lock();
		self.regionUpdateQueue.enqueue(.{.region = region, .milliTimeStamp = std.time.milliTimestamp()});
		self.mutex.unlock();
	}
};
