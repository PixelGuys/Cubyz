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
const JsonElement = main.JsonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const terrain = server.terrain;

const server = @import("server.zig");
const User = server.User;
const Entity = server.Entity;

const storage = @import("storage.zig");

const ChunkManager = struct {
	world: *ServerWorld,
	terrainGenerationProfile: server.terrain.TerrainGenerationProfile,

	// There will be at most 1 GiB of chunks in here. TODO: Allow configuring this in the server settings.
	const reducedChunkCacheMask = 2047;
	var chunkCache: Cache(ServerChunk, reducedChunkCacheMask+1, 4, chunkDeinitFunctionForCache) = .{};

	const ChunkLoadTask = struct {
		pos: ChunkPosition,
		creationTime: i64,
		source: ?*User,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
		};
		
		pub fn scheduleAndDecreaseRefCount(pos: ChunkPosition, source: ?*User) void {
			const task = main.globalAllocator.create(ChunkLoadTask);
			task.* = ChunkLoadTask {
				.pos = pos,
				.creationTime = std.time.milliTimestamp(),
				.source = source,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(self: *ChunkLoadTask) f32 {
			if(self.source) |user| {
				return self.pos.getPriority(user.player.pos);
			} else {
				return std.math.floatMax(f32);
			}
		}

		pub fn isStillNeeded(self: *ChunkLoadTask, milliTime: i64) bool {
			if(self.source) |source| { // Remove the task if the player disconnected
				if(!source.connected.load(.unordered)) return false;
			}
			if(milliTime - self.creationTime > 10000) { // Only remove stuff after 10 seconds to account for trouble when for example teleporting.
				server.mutex.lock();
				defer server.mutex.unlock();
				for(server.users.items) |user| {
					const minDistSquare = self.pos.getMinDistanceSquared(user.player.pos);
					//                                                                  ↓ Margin for error. (diagonal of 1 chunk)
					var targetRenderDistance = (@as(f32, @floatFromInt(user.renderDistance*chunk.chunkSize)) + @as(f32, @floatFromInt(chunk.chunkSize))*@sqrt(3.0));
					targetRenderDistance *= @as(f32, @floatFromInt(self.pos.voxelSize));
					if(minDistSquare <= targetRenderDistance*targetRenderDistance) {
						return true;
					}
				}
				return false;
			}
			return true;
		}

		pub fn run(self: *ChunkLoadTask) void {
			defer self.clean();
			generateChunk(self.pos, self.source);
		}

		pub fn clean(self: *ChunkLoadTask) void {
			if(self.source) |source| {
				source.decreaseRefCount();
			}
			main.globalAllocator.destroy(self);
		}
	};

	const LightMapLoadTask = struct {
		pos: terrain.SurfaceMap.MapFragmentPosition,
		creationTime: i64,
		source: ?*User,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
		};
		
		pub fn scheduleAndDecreaseRefCount(pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
			const task = main.globalAllocator.create(LightMapLoadTask);
			task.* = LightMapLoadTask {
				.pos = pos,
				.creationTime = std.time.milliTimestamp(),
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

		pub fn isStillNeeded(self: *LightMapLoadTask, _: i64) bool {
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
				server.mutex.lock();
				defer server.mutex.unlock();
				for(server.users.items) |user| {
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

	pub fn init(world: *ServerWorld, settings: JsonElement) !ChunkManager {
		const self = ChunkManager {
			.world = world,
			.terrainGenerationProfile = try server.terrain.TerrainGenerationProfile.init(settings, world.seed),
		};
		server.terrain.init(self.terrainGenerationProfile);
		storage.init();
		return self;
	}

	pub fn deinit(self: ChunkManager) void {
		for(0..main.settings.highestLOD) |_| {
			chunkCache.clear();
		}
		server.terrain.deinit();
		main.assets.unloadAssets();
		self.terrainGenerationProfile.deinit();
		storage.deinit();
	}

	pub fn queueLightMapAndDecreaseRefCount(self: ChunkManager, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		_ = self;
		LightMapLoadTask.scheduleAndDecreaseRefCount(pos, source);
	}

	pub fn queueChunkAndDecreaseRefCount(self: ChunkManager, pos: ChunkPosition, source: ?*User) void {
		_ = self;
		ChunkLoadTask.scheduleAndDecreaseRefCount(pos, source);
	}

	pub fn generateChunk(pos: ChunkPosition, source: ?*User) void {
		if(source != null and !source.?.connected.load(.unordered)) return; // User disconnected.
		const ch = getOrGenerateChunkAndIncreaseRefCount(pos);
		defer ch.decreaseRefCount();
		if(source) |_source| {
			main.network.Protocols.chunkTransmission.sendChunk(_source.conn, ch);
		} else {
			server.mutex.lock();
			defer server.mutex.unlock();
			for(server.users.items) |user| {
				main.network.Protocols.chunkTransmission.sendChunk(user.conn, ch);
			}
		}
	}

	fn chunkInitFunctionForCacheAndIncreaseRefCount(pos: ChunkPosition) *ServerChunk {
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
		const biomeMap = terrain.CaveBiomeMap.CaveBiomeMapView.init(ch);
		defer biomeMap.deinit();
		for(server.world.?.chunkManager.terrainGenerationProfile.generators) |generator| {
			generator.generate(server.world.?.seed ^ generator.generatorSeed, ch, caveMap, biomeMap);
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

const WorldIO = struct {
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
		return self.dir.hasFile("world.dat");
	}

	/// Load the seed, which is needed before custom item and ore generation.
	pub fn loadWorldSeed(self: WorldIO) !u64 {
		const worldData: JsonElement = try self.dir.readToJson(main.stackAllocator, "world.dat");
		defer worldData.free(main.stackAllocator);
		if(worldData.get(u32, "version", 0) != worldDataVersion) {
			std.log.err("Cannot read world file version {}. Expected version {}.", .{worldData.get(u32, "version", 0), worldDataVersion});
			return error.OldWorld;
		}
		return worldData.get(u64, "seed", 0);
	}

	pub fn loadWorldData(self: WorldIO) !void {
		const worldData: JsonElement = try self.dir.readToJson(main.stackAllocator, "world.dat");
		defer worldData.free(main.stackAllocator);

		self.world.doGameTimeCycle = worldData.get(bool, "doGameTimeCycle", true);
		self.world.gameTime = worldData.get(i64, "gameTime", 0);
		self.world.spawn = worldData.get(Vec3i, "spawn", .{0, 0, 0});
		self.world.biomeChecksum = worldData.get(i64, "biomeChecksum", 0);
	}

	pub fn saveWorldData(self: WorldIO) !void {
		const worldData: JsonElement = JsonElement.initObject(main.stackAllocator);
		defer worldData.free(main.stackAllocator);
		worldData.put("version", worldDataVersion);
		worldData.put("seed", self.world.seed);
		worldData.put("doGameTimeCycle", self.world.doGameTimeCycle);
		worldData.put("gameTime", self.world.gameTime);
		worldData.put("spawn", self.world.spawn);
		worldData.put("biomeChecksum", self.world.biomeChecksum);
		// TODO: Save entities
		try self.dir.writeJson("world.dat", worldData);
	}
};

pub const ServerWorld = struct {
	pub const dayCycle: u31 = 12000; // Length of one in-game day in units of 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	pub const earthGravity: f32 = 9.81;

	itemDropManager: ItemDropManager = undefined,
	blockPalette: *main.assets.BlockPalette = undefined,
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

	pub fn init(name: []const u8, nullGeneratorSettings: ?JsonElement) !*ServerWorld {
		const self = main.globalAllocator.create(ServerWorld);
		errdefer main.globalAllocator.destroy(self);
		self.* = ServerWorld {
			.lastUpdateTime = std.time.milliTimestamp(),
			.milliTime = std.time.milliTimestamp(),
			.lastUnimportantDataSent = std.time.milliTimestamp(),
			.seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp()))),
			.name = main.globalAllocator.dupe(u8, name),
			.chunkUpdateQueue = main.utils.CircularBufferQueue(ChunkUpdateRequest).init(main.globalAllocator, 256),
			.regionUpdateQueue = main.utils.CircularBufferQueue(RegionUpdateRequest).init(main.globalAllocator, 256),
		};
		self.itemDropManager.init(main.globalAllocator, self, self.gravity);
		errdefer self.itemDropManager.deinit();

		var loadArena = main.utils.NeverFailingArenaAllocator.init(main.stackAllocator);
		defer loadArena.deinit();
		const arenaAllocator = loadArena.allocator();
		var buf: [32768]u8 = undefined;
		var generatorSettings: JsonElement = undefined;
		if(nullGeneratorSettings) |_generatorSettings| {
			generatorSettings = _generatorSettings;
			// Store generator settings:
			try files.writeJson(try std.fmt.bufPrint(&buf, "saves/{s}/generatorSettings.json", .{name}), generatorSettings);
		} else { // Read the generator settings:
			generatorSettings = try files.readToJson(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/generatorSettings.json", .{name}));
		}
		self.wio = WorldIO.init(try files.openDir(try std.fmt.bufPrint(&buf, "saves/{s}", .{name})), self);
		errdefer self.wio.deinit();
		const blockPaletteJson = try files.readToJson(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/palette.json", .{name}));
		self.blockPalette = try main.assets.BlockPalette.init(main.globalAllocator, blockPaletteJson);
		errdefer self.blockPalette.deinit();
		errdefer main.assets.unloadAssets();

		if(self.wio.hasWorldData()) {
			self.seed = try self.wio.loadWorldSeed();
			self.generated = true;
			try main.assets.loadWorldAssets(try std.fmt.bufPrint(&buf, "saves/{s}/assets/", .{name}), self.blockPalette);
		} else {
			self.seed = main.random.nextInt(u48, &main.seed);
			try main.assets.loadWorldAssets(try std.fmt.bufPrint(&buf, "saves/{s}/assets/", .{name}), self.blockPalette);
			try self.wio.saveWorldData();
		}
		// Store the block palette now that everything is loaded.
		try files.writeJson(try std.fmt.bufPrint(&buf, "saves/{s}/palette.json", .{name}), self.blockPalette.save(arenaAllocator));

		self.chunkManager = try ChunkManager.init(self, generatorSettings);
		errdefer self.chunkManager.deinit();
		return self;
	}

	pub fn deinit(self: *ServerWorld) void {
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
		self.wio.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}


	const RegenerateLODTask = struct {
		pos: ChunkPosition,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
		};
		
		pub fn schedule(pos: ChunkPosition) void {
			const task = main.globalAllocator.create(RegenerateLODTask);
			task.* = .{
				.pos = pos,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(_: *RegenerateLODTask) f32 {
			return std.math.floatMax(f32);
		}

		pub fn isStillNeeded(_: *RegenerateLODTask, _: i64) bool {
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
		// Delete old LODs:
		for(1..main.settings.highestLOD+1) |i| {
			const lod = @as(u32, 1) << @intCast(i);
			const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks", .{self.name}) catch unreachable;
			defer main.stackAllocator.free(path);
			const dir = std.fmt.allocPrint(main.stackAllocator.allocator, "{}", .{lod}) catch unreachable;
			defer main.stackAllocator.free(dir);
			main.files.deleteDir(path, dir) catch |err| {
				std.log.err("Error while deleting directory {s}/{s}: {s}", .{path, dir, @errorName(err)});
			};
		}
		// Find all the stored chunks:
		var chunkPositions = main.List(ChunkPosition).init(main.stackAllocator);
		defer chunkPositions.deinit();
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/chunks/1", .{self.name}) catch unreachable;
		defer main.stackAllocator.free(path);
		{
			var dirX = try std.fs.cwd().openDir(path, .{.iterate = true});
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
			RegenerateLODTask.schedule(pos);
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
			self.spawn[2] = @intFromFloat(map.getHeight(self.spawn[0], self.spawn[1]) + 1);
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
		const json = try files.readToJson(main.stackAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/items.json", .{self.name}));
		defer json.free(main.stackAllocator);
		self.itemDropManager.loadFrom(json);
	}


	pub fn findPlayer(self: *ServerWorld, user: *User) void {
		var buf: [1024]u8 = undefined;
		const playerData = files.readToJson(main.stackAllocator, std.fmt.bufPrint(&buf, "saves/{s}/player/{s}.json", .{self.name, user.name}) catch "") catch .JsonNull; // TODO: Utils.escapeFolderName(user.name)
		defer playerData.free(main.stackAllocator);
		const player = &user.player;
		if(playerData == .JsonNull) {
			// Generate a new player:
			player.pos = @floatFromInt(self.spawn);
		} else {
			player.loadFrom(playerData);
		}
	}

	pub fn forceSave(self: *ServerWorld) !void {
		// TODO: Save chunks and player data
		try self.wio.saveWorldData();
		const itemDropJson = self.itemDropManager.store(main.stackAllocator);
		defer itemDropJson.free(main.stackAllocator);
		var buf: [32768]u8 = undefined;
		try files.writeJson(try std.fmt.bufPrint(&buf, "saves/{s}/items.json", .{self.name}), itemDropJson);
	}

	fn isValidSpawnLocation(_: *ServerWorld, wx: i32, wy: i32) bool {
		const map = terrain.SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(wx, wy, 1);
		defer map.decreaseRefCount();
		return map.getBiome(wx, wy).isValidPlayerSpawn;
	}

	pub fn dropWithCooldown(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32, pickupCooldown: u32) void {
		const vel = vec.floatCast(f64, dir*@as(Vec3d, @splat(velocity)));
		self.itemDropManager.add(pos, vel, stack, server.updatesPerSec*900, pickupCooldown);
	}

	pub fn drop(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32) void {
		self.dropWithCooldown(stack, pos, dir, velocity, 0);
	}

	pub fn update(self: *ServerWorld) void {
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
			server.mutex.lock();
			defer server.mutex.unlock();
			for(server.users.items) |user| {
				main.network.Protocols.genericUpdate.sendTimeAndBiome(user.conn, self);
			}
		}
		// TODO: Entities

		// Item Entities
		self.itemDropManager.update(deltaTime);

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

	pub fn queueChunkAndDecreaseRefCount(self: *ServerWorld, pos: ChunkPosition, source: ?*User) void {
		self.chunkManager.queueChunkAndDecreaseRefCount(pos, source);
	}

	pub fn queueLightMapAndDecreaseRefCount(self: *ServerWorld, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		self.chunkManager.queueLightMapAndDecreaseRefCount(pos, source);
	}

	pub fn getChunk(self: *ServerWorld, x: i32, y: i32, z: i32) ?*ServerChunk {
		_ = self;
		_ = x;
		_ = y;
		_ = z;
		// TODO
		return null;
	}

	pub fn getOrGenerateChunkAndIncreaseRefCount(_: *ServerWorld, pos: chunk.ChunkPosition) *ServerChunk {
		return ChunkManager.getOrGenerateChunkAndIncreaseRefCount(pos);
	}

	pub fn getBiome(_: *const ServerWorld, wx: i32, wy: i32, wz: i32) *const terrain.biomes.Biome {
		const map = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView.init(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1}, 1);
		defer map.deinit();
		return map.getRoughBiome(wx, wy, wz, false, undefined, true);
	}

	pub fn getBlock(self: *ServerWorld, x: i32, y: i32, z: i32) Block {
		if(self.getChunk(x, y, z)) |ch| {
			return ch.getBlock(x & chunk.chunkMask, y & chunk.chunkMask, z & chunk.chunkMask);
		}
		return Block {.typ = 0, .data = 0};
	}

	pub fn updateBlock(_: *ServerWorld, wx: i32, wy: i32, wz: i32, _newBlock: Block) void {
		const baseChunk = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{.wx = wx & ~@as(i32, chunk.chunkMask), .wy = wy & ~@as(i32, chunk.chunkMask), .wz = wz & ~@as(i32, chunk.chunkMask), .voxelSize = 1});
		defer baseChunk.decreaseRefCount();
		const x: u5 = @intCast(wx & chunk.chunkMask);
		const y: u5 = @intCast(wy & chunk.chunkMask);
		const z: u5 = @intCast(wz & chunk.chunkMask);
		var newBlock = _newBlock;
		for(chunk.Neighbors.iterable) |neighbor| {
			const nx = x + chunk.Neighbors.relX[neighbor];
			const ny = y + chunk.Neighbors.relY[neighbor];
			const nz = z + chunk.Neighbors.relZ[neighbor];
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
				if(neighborBlock.mode().updateData(&neighborBlock, neighbor ^ 1, newBlock)) {
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
		server.mutex.lock();
		defer server.mutex.unlock();
		for(main.server.users.items) |user| {
			main.network.Protocols.blockUpdate.send(user.conn, wx, wy, wz, _newBlock);
		}
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
