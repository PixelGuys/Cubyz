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
const ChunkManager = server.ChunkManager;
const User = server.User;
const Entity = server.Entity;
const permission = server.permission;
const players = server.players;
const Palette = main.assets.Palette;

const storage = @import("storage.zig");
const Gamemode = main.game.Gamemode;

const BlockUpdateSystem = main.server.BlockUpdateSystem;
const SimulationChunk = main.server.SimulationChunk;

pub const Settings = struct {
	defaultGamemode: Gamemode = .creative,
	allowCheats: bool = true,
	testingMode: bool = false,
	whitelistEnabled: std.atomic.Value(bool) = .init(false),
	seed: u64 = undefined,

	pub const defaults: Settings = .{};

	pub fn fromZon(zon: ZonElement) error{NoSeed}!Settings {
		return .{
			.seed = zon.get(u64, "seed") orelse {
				std.log.err("Cannot load world. World has no seed!", .{});
				return error.NoSeed;
			},
			.defaultGamemode = std.meta.stringToEnum(main.game.Gamemode, zon.get([]const u8, "defaultGamemode") orelse @tagName(defaults.defaultGamemode)) orelse defaults.defaultGamemode,
			.allowCheats = zon.get(bool, "allowCheats") orelse defaults.allowCheats,
			.testingMode = zon.get(bool, "testingMode") orelse defaults.testingMode,
			.whitelistEnabled = .init(zon.get(bool, "whitelistEnabled") orelse defaults.whitelistEnabled.load(.monotonic)),
		};
	}

	pub fn toZon(self: *const Settings, allocator: NeverFailingAllocator) ZonElement {
		const zon = main.ZonElement.initObject(allocator);

		zon.put("defaultGamemode", @tagName(self.defaultGamemode));
		zon.put("allowCheats", self.allowCheats);
		zon.put("testingMode", self.testingMode);
		zon.put("whitelistEnabled", self.whitelistEnabled.load(.monotonic));
		zon.put("seed", self.seed);

		return zon;
	}
};

fn findValidFolderName(allocator: main.heap.NeverFailingAllocator, name: []const u8) []const u8 {
	// Remove illegal ASCII characters:
	const escapedName = main.stackAllocator.alloc(u8, name.len);
	defer main.stackAllocator.free(escapedName);
	for (name, 0..) |char, i| {
		escapedName[i] = switch (char) {
			'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.', ' ' => char,
			128...255 => char,
			else => '-',
		};
	}

	// Avoid duplicates:
	var resultName = main.stackAllocator.dupe(u8, escapedName);
	defer main.stackAllocator.free(resultName);
	var i: usize = 0;
	while (true) {
		const resultPath = main.stackAllocator.print("saves/{s}", .{resultName});
		defer main.stackAllocator.free(resultPath);

		if (!main.files.cubyzDir().hasDir(resultPath)) break;

		main.stackAllocator.free(resultName);
		resultName = main.stackAllocator.print("{s}_{}", .{escapedName, i});
		i += 1;
	}
	return allocator.dupe(u8, resultName);
}

pub fn tryCreateWorld(worldName: []const u8, worldSettings: Settings, preset: ZonElement) !void {
	const worldPath = findValidFolderName(main.stackAllocator, worldName);
	defer main.stackAllocator.free(worldPath);
	const saveFolder = main.stackAllocator.print("saves/{s}", .{worldPath});
	defer main.stackAllocator.free(saveFolder);
	try main.files.cubyzDir().makePath(saveFolder);

	const worldInfo = main.ZonElement.initObject(main.stackAllocator);
	defer worldInfo.deinit(main.stackAllocator);

	worldInfo.put("generatorSettings", preset.clone(main.stackAllocator));
	worldInfo.put("settings", worldSettings.toZon(main.stackAllocator));

	{
		const worldInfoPath = main.stackAllocator.print("saves/{s}/world.zig.zon", .{worldPath});
		defer main.stackAllocator.free(worldInfoPath);

		worldInfo.put("name", worldName);
		worldInfo.put("version", worldDataVersion);
		worldInfo.put("lastUsedTime", std.Io.Clock.Timestamp.now(main.io, .real).raw.toMilliseconds());

		try main.files.cubyzDir().writeZon(worldInfoPath, worldInfo);
	}
	{ // Make assets subfolder
		const assetsPath = main.stackAllocator.print("saves/{s}/assets", .{worldPath});
		defer main.stackAllocator.free(assetsPath);
		try main.files.cubyzDir().makePath(assetsPath);
	}
}

pub const worldDataVersion: u32 = 5;

pub const ServerWorld = struct { // MARK: ServerWorld
	itemDropManager: ItemDropManager = undefined,
	blockPalette: *main.assets.Palette = undefined,
	itemPalette: *main.assets.Palette = undefined,
	proceduralItemPalette: *main.assets.Palette = undefined,
	biomePalette: *main.assets.Palette = undefined,
	entityModelPalette: *main.assets.Palette = undefined,
	entityComponentPalette: *main.assets.Palette = undefined,
	chunkManager: ChunkManager = undefined,

	gameTime: i64 = 0,
	milliTime: std.Io.Timestamp,
	lastUpdateTime: std.Io.Timestamp,
	lastUnimportantDataSent: std.Io.Timestamp,
	lastItemDropSaveTime: std.Io.Timestamp,
	doGameTimeCycle: bool = true,

	tickSpeed: std.atomic.Value(u32) = .init(12),

	settings: Settings = undefined,

	mode: Mode,

	path: []const u8,
	name: []const u8 = &.{},
	spawn: Vec3i = undefined,

	mutex: main.utils.Mutex = .{},

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

	pub const Mode = enum { singleplayer, multiplayer };

	pub fn init(path: []const u8, mode: Mode) !*ServerWorld { // MARK: init()
		const self = main.globalAllocator.create(ServerWorld);
		errdefer main.globalAllocator.destroy(self);
		self.* = ServerWorld{
			.lastUpdateTime = main.timestamp(),
			.milliTime = main.timestamp(),
			.lastUnimportantDataSent = main.timestamp(),
			.lastItemDropSaveTime = main.timestamp(),
			.path = main.globalAllocator.dupe(u8, path),
			.chunkUpdateQueue = .init(main.globalAllocator, 256),
			.regionUpdateQueue = .init(main.globalAllocator, 256),
			.mode = mode,
		};
		self.itemDropManager.init(main.globalAllocator, self);
		errdefer self.itemDropManager.deinit();

		const arena = main.stackAllocator.createArena();
		defer main.stackAllocator.destroyArena(arena);

		var dir = try files.cubyzDir().openDir(arena.print("saves/{s}", .{path}));
		defer dir.close();

		self.blockPalette = try loadPalette(arena, path, "palette", "cubyz:air");
		errdefer self.blockPalette.deinit();

		self.itemPalette = try loadPalette(arena, path, "item_palette", null);
		errdefer self.itemPalette.deinit();

		self.proceduralItemPalette = try loadPalette(arena, path, "tool_palette", null);
		errdefer self.proceduralItemPalette.deinit();

		self.biomePalette = try loadPalette(arena, path, "biome_palette", null);
		errdefer self.biomePalette.deinit();

		self.entityModelPalette = try loadPalette(arena, path, "entity_model_palette", "cubyz:missing");
		errdefer self.entityModelPalette.deinit();

		self.entityComponentPalette = try loadPalette(arena, path, "entity_component_palette", null);
		errdefer self.entityComponentPalette.deinit();

		errdefer main.assets.unloadAssets();

		const worldData = try dir.readToZon(arena, "world.zig.zon");
		try self.loadWorldConfig(arena, dir, worldData);
		try players.loadPlayerLoginInfo(dir, self.path, worldData.get(usize, "localPlayer") orelse 0);

		try main.assets.loadWorldAssets(arena.print("{s}/saves/{s}/assets/", .{files.cubyzDirStr(), path}), self.blockPalette, self.itemPalette, self.proceduralItemPalette, self.biomePalette, self.entityModelPalette, self.entityComponentPalette);
		// Store the block palette now that everything is loaded.
		try dir.writeZon("palette.zig.zon", self.blockPalette.storeToZon(arena));
		try dir.writeZon("item_palette.zig.zon", self.itemPalette.storeToZon(arena));
		try dir.writeZon("tool_palette.zig.zon", self.proceduralItemPalette.storeToZon(arena));
		try dir.writeZon("biome_palette.zig.zon", self.biomePalette.storeToZon(arena));
		try dir.writeZon("entity_model_palette.zig.zon", self.entityModelPalette.storeToZon(arena));
		try dir.writeZon("entity_component_palette.zig.zon", self.entityComponentPalette.storeToZon(arena));

		self.chunkManager = try ChunkManager.init(self, worldData.getChild("generatorSettings"));
		errdefer self.chunkManager.deinit();

		try permission.loadGroups(try dir.openIterableDir("permission"), self.path);
		std.debug.assert(main.entityModel.getById("cubyz:missing") != null);

		return self;
	}

	pub fn loadPalette(allocator: NeverFailingAllocator, worldName: []const u8, paletteName: []const u8, firstEntry: ?[]const u8) !*Palette {
		const path = main.stackAllocator.print("saves/{s}/{s}.zig.zon", .{worldName, paletteName});
		defer main.stackAllocator.allocator.free(path);
		const paletteZon = files.cubyzDir().readToZon(allocator, path) catch .null;
		const palette = try main.assets.Palette.init(main.globalAllocator, paletteZon, firstEntry);
		std.log.info("Loaded {s} with {} entries.", .{paletteName, palette.size()});
		return palette;
	}

	pub fn deinit(self: *ServerWorld) void {
		self.saveWorldConfig() catch |err| {
			std.log.err("Error while saving world config: {s}", .{@errorName(err)});
		};
		self.saveAllPlayers() catch |err| {
			std.log.err("Error while saving player data: {s}", .{@errorName(err)});
		};
		self.saveItemdrops() catch |err| {
			std.log.err("Error while saving item data: {s}", .{@errorName(err)});
		};
		while (self.chunkUpdateQueue.popFront()) |updateRequest| {
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
		}
		self.chunkUpdateQueue.deinit();
		while (self.regionUpdateQueue.popFront()) |updateRequest| {
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
		}
		self.regionUpdateQueue.deinit();
		self.chunkManager.deinit();
		self.itemDropManager.deinit();
		self.blockPalette.deinit();
		self.itemPalette.deinit();
		self.proceduralItemPalette.deinit();
		self.biomePalette.deinit();
		self.entityModelPalette.deinit();
		self.entityComponentPalette.deinit();
		permission.deinit();
		main.globalAllocator.free(self.path);
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}

	pub fn loadWorldConfig(self: *ServerWorld, arena: NeverFailingAllocator, dir: main.files.Dir, worldData: ZonElement) !void { // MARK: loadWorldConfig
		if ((worldData.get(u32, "version") orelse 0) == 2) { // TODO: #2458
			std.log.info("Migrating old world with world version 2 to version 3", .{});

			const gamerules = try dir.readToZon(arena, "gamerules.zig.zon");
			const settings = ZonElement.initObject(arena);
			settings.put("defaultGamemode", gamerules.getChild("default_gamemode"));
			settings.put("allowCheats", gamerules.getChild("cheats"));
			settings.put("testingMode", gamerules.getChild("testingMode"));
			settings.put("seed", worldData.get(u64, "seed") orelse {
				std.log.err("Cannot migrate world. World has no seed!", .{});
				return error.NoSeed;
			});
			worldData.put("settings", settings);

			const generatorSettings = try dir.readToZon(arena, "generatorSettings.zig.zon");
			worldData.put("generatorSettings", generatorSettings);

			worldData.put("version", 3);
			try dir.writeZon("world.zig.zon", worldData);
			try dir.deleteFile("gamerules.zig.zon");
			try dir.deleteFile("generatorSettings.zig.zon");
		}

		if ((worldData.get(u32, "version") orelse 0) == 3) { // TODO: #2458
			std.log.info("Migrating old world with world version 3 to version 4", .{});
			// In version 0.1.0 these values were written incorrectly
			const settings = worldData.getChild("settings");
			if (settings.removeChild("default_gamemode")) |gamemode| {
				settings.put("defaultGamemode", gamemode);
			}
			if (settings.removeChild("cheats")) |allowCheats| {
				settings.put("allowCheats", allowCheats);
			}

			worldData.put("version", 4);
			try dir.writeZon("world.zig.zon", worldData);
		}

		if ((worldData.get(u32, "version") orelse 0) == 4) { // TODO: #2458
			std.log.info("Migrating old world with world version 4 to version 5", .{});
			// Player file names are now numerical instead of based on the name.
			var fileNames: main.List([]const u8) = .empty;
			var playerDir = try dir.openIterableDir("players");
			defer playerDir.close();
			var iterator = playerDir.iterate();
			while (try iterator.next(main.io)) |file| {
				if (file.kind == .file and std.mem.endsWith(u8, file.name, ".zon")) {
					fileNames.append(arena, arena.dupe(u8, file.name));
				}
			}

			for (fileNames.items, 0..) |oldName, i| {
				const newName = arena.print("{}.zon", .{i});
				try playerDir.dir.rename(oldName, playerDir.dir, newName, main.io);
			}

			worldData.put("version", 5);
			try dir.writeZon("world.zig.zon", worldData);
		}

		if ((worldData.get(u32, "version") orelse 0) != worldDataVersion) {
			std.log.err("Cannot read world file version {}. Expected version {}.", .{worldData.get(u32, "version") orelse 0, worldDataVersion});
			return error.OldWorld;
		}
		self.settings = try .fromZon(worldData.getChild("settings"));

		self.doGameTimeCycle = worldData.get(bool, "doGameTimeCycle") orelse true;
		self.gameTime = worldData.get(i64, "gameTime") orelse 0;
		self.spawn = worldData.get(Vec3i, "spawn") orelse .{0, 0, 0};
		self.biomeChecksum = worldData.get(i64, "biomeChecksum") orelse 0;
		self.name = main.globalAllocator.dupe(u8, worldData.get([]const u8, "name") orelse self.path);
		self.tickSpeed = .init(worldData.get(u32, "tickSpeed") orelse 12);
	}

	pub fn saveWorldConfig(self: *ServerWorld) !void {
		const path = main.stackAllocator.print("saves/{s}/world.zig.zon", .{self.path});
		defer main.stackAllocator.free(path);
		const worldData = try files.cubyzDir().readToZon(main.stackAllocator, path);
		defer worldData.deinit(main.stackAllocator);
		worldData.put("version", worldDataVersion);
		worldData.put("doGameTimeCycle", self.doGameTimeCycle);
		worldData.put("gameTime", self.gameTime);
		worldData.put("spawn", self.spawn);
		worldData.put("biomeChecksum", self.biomeChecksum);
		worldData.put("name", self.name);
		worldData.put("lastUsedTime", std.Io.Clock.Timestamp.now(main.io, .real).raw.toMilliseconds());
		worldData.put("tickSpeed", self.tickSpeed.load(.monotonic));
		worldData.put("settings", self.settings.toZon(main.stackAllocator));
		worldData.put("localPlayer", players.getLocalPlayerIndex());

		try files.cubyzDir().writeZon(path, worldData);
	}

	const RegenerateLODTask = struct { // MARK: RegenerateLODTask
		pos: ChunkPosition,
		storeMaps: bool,

		const vtable = utils.ThreadPool.VTable{
			.getPriority = main.meta.castFunctionSelfToAnyopaque(getPriority),
			.isStillNeeded = main.meta.castFunctionSelfToAnyopaque(isStillNeeded),
			.run = main.meta.castFunctionSelfToAnyopaque(run),
			.clean = main.meta.castFunctionSelfToAnyopaque(clean),
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
			for (0..storage.RegionFile.regionSize) |x| {
				for (0..storage.RegionFile.regionSize) |y| {
					for (0..storage.RegionFile.regionSize) |z| {
						if (region.chunks[storage.RegionFile.getIndex(x, y, z)].len != 0) {
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
		const mapsPath = main.stackAllocator.print("saves/{s}/maps", .{self.path});
		defer main.stackAllocator.free(mapsPath);
		const hasSurfaceMaps = main.files.cubyzDir().hasDir(mapsPath);
		if (hasSurfaceMaps) {
			try terrain.SurfaceMap.regenerateLOD(self.path);
		}
		std.log.info("Regenerating chunk LODs...", .{});
		// Delete old LODs:
		for (1..main.settings.highestSupportedLod + 1) |i| {
			const lod = @as(u32, 1) << @intCast(i);
			const path = main.stackAllocator.print("saves/{s}/chunks/{}", .{self.path, lod});
			defer main.stackAllocator.free(path);
			main.files.cubyzDir().deleteTree(path) catch |err| {
				if (err != error.FileNotFound) {
					std.log.err("Error while deleting directory {s}: {s}", .{path, @errorName(err)});
				}
			};
		}
		// Find all the stored chunks:
		var chunkPositions: main.List(ChunkPosition) = .empty;
		defer chunkPositions.deinit(main.stackAllocator);
		const path = main.stackAllocator.print("saves/{s}/chunks/1", .{self.path});
		defer main.stackAllocator.free(path);
		blk: {
			var dirX = main.files.cubyzDir().openIterableDir(path) catch |err| {
				if (err == error.FileNotFound) break :blk;
				return err;
			};
			defer dirX.close();
			var iterX = dirX.iterate();
			while (try iterX.next(main.io)) |entryX| {
				if (entryX.kind != .directory) continue;
				const wx = std.fmt.parseInt(i32, entryX.name, 0) catch continue;
				var dirY = try dirX.openIterableDir(entryX.name);
				defer dirY.close();
				var iterY = dirY.iterate();
				while (try iterY.next(main.io)) |entryY| {
					if (entryY.kind != .directory) continue;
					const wy = std.fmt.parseInt(i32, entryY.name, 0) catch continue;
					var dirZ = try dirY.openIterableDir(entryY.name);
					defer dirZ.close();
					var iterZ = dirZ.iterate();
					while (try iterZ.next(main.io)) |entryZ| {
						if (entryZ.kind != .file) continue;
						const nameZ = entryZ.name[0 .. std.mem.indexOfScalar(u8, entryZ.name, '.') orelse entryZ.name.len];
						const wz = std.fmt.parseInt(i32, nameZ, 0) catch continue;
						chunkPositions.append(main.stackAllocator, .{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1});
					}
				}
			}
		}
		// Load all the stored chunks and update their next LODs.
		for (chunkPositions.items) |pos| {
			RegenerateLODTask.schedule(pos, !hasSurfaceMaps);
		}

		self.mutex.lock();
		defer self.mutex.unlock();
		while (true) {
			while (self.chunkUpdateQueue.popFront()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.ch.save(self);
				updateRequest.ch.decreaseRefCount();
				main.heap.garbage_collection.syncPoint();
			}
			while (self.regionUpdateQueue.popFront()) |updateRequest| {
				self.mutex.unlock();
				defer self.mutex.lock();
				updateRequest.region.store();
				updateRequest.region.decreaseRefCount();
				main.heap.garbage_collection.syncPoint();
			}
			self.mutex.unlock();
			main.io.sleep(.fromMilliseconds(1), .awake) catch {};
			main.heap.garbage_collection.syncPoint();
			self.mutex.lock();
			if (main.threadPool.queueSize() == 0 and self.chunkUpdateQueue.peekFront() == null and self.regionUpdateQueue.peekFront() == null) break;
		}
		std.log.info("Finished LOD update.", .{});

		self.biomeChecksum = newBiomeCheckSum;
	}

	pub fn generate(self: *ServerWorld) !void {
		if (@reduce(.And, self.spawn == Vec3i{0, 0, 0})) {
			var seed: u64 = self.settings.seed ^ 275892235728371;
			std.log.info("Finding spawn position...", .{});
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
				for (0..spiralLen) |_| {
					const map = main.server.terrain.ClimateMap.getOrGenerateFragment(wx, wy);
					for (0..map.map.len) |_| {
						const x = main.random.nextIntBounded(u31, &seed, map.map.len);
						const y = main.random.nextIntBounded(u31, &seed, map.map.len);
						const biomeSize = main.server.terrain.SurfaceMap.MapFragment.biomeSize;
						std.log.info("Trying roughly ({}, {})", .{wx + x*biomeSize, wy + y*biomeSize});
						const sample = map.map[x][y];
						if (sample.biome.isValidPlayerSpawn) {
							for (0..16) |_| {
								self.spawn[0] = wx + x*biomeSize + main.random.nextIntBounded(u31, &seed, biomeSize*2) - biomeSize;
								self.spawn[1] = wy + y*biomeSize + main.random.nextIntBounded(u31, &seed, biomeSize*2) - biomeSize;
								std.log.info("Trying ({}, {})", .{self.spawn[0], self.spawn[1]});
								if (self.isValidSpawnLocation(self.spawn[0], self.spawn[1])) break :foundPosition;
							}
						}
					}
					switch (dir) {
						.dirNegX => wx -%= mapSize,
						.dirPosX => wx +%= mapSize,
						.dirNegY => wy -%= mapSize,
						.dirPosY => wy +%= mapSize,
						else => unreachable,
					}
					stepsRemaining -= 1;
					if (stepsRemaining == 0) {
						switch (dir) {
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
				const map = terrain.SurfaceMap.getOrGenerateFragment(self.spawn[0], self.spawn[1], 1);
				self.spawn[2] = map.getHeight(self.spawn[0], self.spawn[1]) + 1;
			}
		}
		const newBiomeCheckSum: i64 = @bitCast(terrain.biomes.getBiomeCheckSum(self.settings.seed));
		if (newBiomeCheckSum != self.biomeChecksum) {
			if (self.settings.testingMode) {
				const dir = main.stackAllocator.print("saves/{s}/maps", .{self.path});
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
		try self.saveWorldConfig();
		loadItemDrops: {
			const itemsPath = main.stackAllocator.print("saves/{s}/itemdrops.bin", .{self.path});
			defer main.stackAllocator.free(itemsPath);
			const itemDropData: []const u8 = files.cubyzDir().read(main.stackAllocator, itemsPath) catch |err| {
				if (err != error.FileNotFound) {
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

	pub fn loadPlayer(self: *ServerWorld, user: *User) !void {
		const path = main.stackAllocator.print("saves/{s}/players/{}.zon", .{self.path, user.playerIndex});
		defer main.stackAllocator.free(path);

		const playerData = files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
		defer playerData.deinit(main.stackAllocator);
		if (user.newKeyString) |userKey| {
			const oldPublicKey = playerData.get([]const u8, "publicKey");
			if (oldPublicKey == null or !std.mem.eql(u8, oldPublicKey.?, userKey)) {
				players.rebindKey(oldPublicKey, playerData.get([]const u8, "name"), userKey, user.playerIndex);
			}
		}
		const player = user.player();
		const loadingError = player.loadFrom(user.id, playerData.getChild("entity"), .server, @floatFromInt(self.spawn));

		// override the name for players.
		if (player.name) |name| {
			main.globalAllocator.free(name);
		}
		player.name = main.globalAllocator.dupe(u8, user.name);

		if (playerData == .null) {
			user.gamemode = .init(self.settings.defaultGamemode);
		} else {
			user.gamemode = .init(std.meta.stringToEnum(main.game.Gamemode, playerData.get([]const u8, "gamemode") orelse @tagName(self.settings.defaultGamemode)) orelse self.settings.defaultGamemode);
		}
		user.inventory = loadPlayerInventory(main.game.player.inventorySize, playerData.get([]const u8, "playerInventory") orelse "", .{.playerInventory = user.id}, path);
		user.handInventory = loadPlayerInventory(1, playerData.get([]const u8, "hand") orelse "", .{.hand = user.id}, path);

		user.spawnPos = playerData.get(Vec3d, "playerSpawnPos");

		return loadingError;
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
		return main.items.Inventory.server.createExternallyManagedInventory(size, source, &reader, .{});
	}

	fn savePlayerInventory(allocator: NeverFailingAllocator, inv: main.items.Inventory) []const u8 {
		var writer = main.utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();

		inv.toBytes(&writer);

		const destination: []u8 = allocator.alloc(u8, std.base64.url_safe.Encoder.calcSize(writer.data.items.len));
		return std.base64.url_safe.Encoder.encode(destination, writer.data.items);
	}

	pub fn savePlayer(self: *ServerWorld, user: *User) !void {
		const path = main.stackAllocator.print("saves/{s}/players/{}.zon", .{self.path, user.playerIndex});
		defer main.stackAllocator.free(path);

		var playerZon: ZonElement = files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
		defer playerZon.deinit(main.stackAllocator);

		if (playerZon != .object) {
			playerZon.deinit(main.stackAllocator);
			playerZon = ZonElement.initObject(main.stackAllocator);
		}

		playerZon.put("name", user.name);
		if (user.newKeyString) |key| {
			playerZon.put("publicKey", key);
		}

		playerZon.put("entity", user.player().save(main.stackAllocator, .disk));
		playerZon.put("gamemode", @tagName(user.gamemode.load(.monotonic)));

		{
			main.sync.threadContext.assertCorrectContext(.server);
			if (main.items.Inventory.server.getInventoryFromSource(.{.playerInventory = user.id})) |inv| {
				playerZon.put("playerInventory", ZonElement{.stringOwned = savePlayerInventory(main.stackAllocator, inv)});
			} else @panic("The player inventory wasn't found. Cannot save player data.");

			if (main.items.Inventory.server.getInventoryFromSource(.{.hand = user.id})) |inv| {
				playerZon.put("hand", ZonElement{.stringOwned = savePlayerInventory(main.stackAllocator, inv)});
			} else @panic("The player hand inventory wasn't found. Cannot save player data.");
		}

		if (user.spawnPos) |spawnPos| {
			playerZon.put("playerSpawnPos", spawnPos);
		}

		const playerPath = main.stackAllocator.print("saves/{s}/players", .{self.path});
		defer main.stackAllocator.free(playerPath);

		try files.cubyzDir().makePath(playerPath);

		try files.cubyzDir().writeZon(path, playerZon);
	}

	pub fn saveAllPlayers(self: *ServerWorld) !void {
		const userList = server.getUserList(main.stackAllocator);
		defer main.stackAllocator.free(userList);

		for (userList) |user| {
			try savePlayer(self, user);
		}
	}

	fn saveItemdrops(self: *ServerWorld) !void {
		var itemDropData = main.utils.BinaryWriter.init(main.stackAllocator);
		defer itemDropData.deinit();
		self.itemDropManager.storeToBytes(&itemDropData);
		const itemsPath = main.stackAllocator.print("saves/{s}/itemdrops.bin", .{self.path});
		defer main.stackAllocator.free(itemsPath);
		try files.cubyzDir().write(itemsPath, itemDropData.data.items);
	}

	fn getOrGenerateBlock(wx: i32, wy: i32, wz: i32) Block {
		const pos = chunk.ChunkPosition.initFromWorldPos(.{wx, wy, wz}, 1);
		const ch = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(pos);
		defer ch.decreaseRefCount();
		ch.mutex.lock();
		defer ch.mutex.unlock();
		const relPos = chunk.BlockPos.fromWorldCoords(wx, wy, wz);
		return ch.getBlock(relPos.x, relPos.y, relPos.z);
	}

	fn isValidSpawnLocation(self: *ServerWorld, wx: i32, wy: i32) bool {
		const map = terrain.SurfaceMap.getOrGenerateFragment(wx, wy, 1);
		if (!map.getBiome(wx, wy).isValidPlayerSpawn) return false;
		const height = map.getHeight(wx, wy);

		const groundBlock = getOrGenerateBlock(wx, wy, height - 1);
		if (!groundBlock.collide() or !groundBlock.onTouch().isNoop()) return false;
		inline for (.{height, height + 1}) |h| {
			const block = getOrGenerateBlock(wx, wy, h);
			if (block.collide() or !block.onTouch().isNoop()) return false;
		}

		self.spawn[2] = height + 1;
		return true;
	}

	pub fn dropWithCooldown(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32, pickupCooldown: i32) void {
		const vel: Vec3d = @floatCast(dir*@as(Vec3f, @splat(velocity)));
		const rot = main.random.nextFloatVector(3, &main.seed)*@as(Vec3f, @splat(2*std.math.pi));
		self.itemDropManager.add(pos, vel, rot, stack, server.updatesPerSec*900, pickupCooldown);
	}

	pub fn drop(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32) void {
		self.dropWithCooldown(stack, pos, dir, velocity, 0);
	}

	fn tick(self: *ServerWorld) void {
		ChunkManager.mutex.lock();
		var iter = ChunkManager.simulationChunkHashMap.valueIterator();
		var currentChunks: main.List(*SimulationChunk) = .initCapacity(main.stackAllocator, iter.len);
		defer currentChunks.deinit(main.stackAllocator);
		while (iter.next()) |simulationChunk| {
			simulationChunk.*.increaseRefCount();
			currentChunks.append(main.stackAllocator, simulationChunk.*);
		}
		ChunkManager.mutex.unlock();

		for (currentChunks.items) |simulationChunk| {
			defer simulationChunk.decreaseRefCount();
			simulationChunk.update(self.tickSpeed.load(.monotonic));
		}
	}

	pub fn update(self: *ServerWorld) void { // MARK: update()
		const newTime = main.timestamp();
		var deltaTime = @as(f32, @floatFromInt(self.lastUpdateTime.durationTo(newTime).toNanoseconds()))/1.0e9;
		self.lastUpdateTime = newTime;
		if (deltaTime > 0.3) {
			std.log.warn("Update time is getting too high. It's already at {} s!", .{deltaTime});
			deltaTime = 0.3;
		}

		while (self.milliTime.durationTo(newTime).toMilliseconds() > 100) {
			self.milliTime = self.milliTime.addDuration(.fromMilliseconds(100));
			if (self.doGameTimeCycle) self.gameTime +%= 1; // gameTime is measured in 100ms.
		}
		if (self.lastUnimportantDataSent.durationTo(newTime).toSeconds() > 2) {
			self.lastUnimportantDataSent = newTime;
			const userList = server.getUserList(main.stackAllocator);
			defer main.stackAllocator.free(userList);
			for (userList) |user| {
				main.network.protocols.generic_update.sendTime(user.conn, self);
			}
		}
		self.tick();
		// TODO: Entities

		// Item Entities
		self.itemDropManager.update(deltaTime);
		{ // Collect item entities:
			const userList = server.getUserList(main.stackAllocator);
			defer main.stackAllocator.free(userList);
			for (userList) |user| {
				self.itemDropManager.checkEntity(user);
			}
		}
		if (self.lastItemDropSaveTime.durationTo(newTime).toSeconds() > 5) {
			self.lastItemDropSaveTime = newTime;
			self.saveItemdrops() catch |err| {
				std.log.err("Error while saving item data: {s}", .{@errorName(err)});
			};
		}

		// Store chunks and regions.
		// Stores at least one chunk and one region per iteration.
		// All chunks and regions will be stored within the storage time.
		const insertionTime = newTime.subDuration(main.settings.storageTime);
		self.mutex.lock();
		defer self.mutex.unlock();
		while (self.chunkUpdateQueue.popFront()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.ch.save(self);
			updateRequest.ch.decreaseRefCount();
			if (updateRequest.milliTimeStamp -% insertionTime.toMilliseconds() >= 0) break;
		}
		while (self.regionUpdateQueue.popFront()) |updateRequest| {
			self.mutex.unlock();
			defer self.mutex.lock();
			updateRequest.region.store();
			updateRequest.region.decreaseRefCount();
			if (updateRequest.milliTimeStamp -% insertionTime.toMilliseconds() >= 0) break;
		}
	}

	pub fn queueChunk(self: *ServerWorld, pos: ChunkPosition, source: *User) void {
		self.chunkManager.queueChunk(pos, source);
	}

	pub fn queueLightMap(self: *ServerWorld, pos: terrain.SurfaceMap.MapFragmentPosition, source: *User) void {
		self.chunkManager.queueLightMap(pos, source);
	}

	pub fn getSimulationChunkAndIncreaseRefCount(_: *ServerWorld, x: i32, y: i32, z: i32) ?*SimulationChunk {
		if (ChunkManager.getSimulationChunkAndIncreaseRefCount(.{.wx = x & ~@as(i32, chunk.chunkMask), .wy = y & ~@as(i32, chunk.chunkMask), .wz = z & ~@as(i32, chunk.chunkMask), .voxelSize = 1})) |entityChunk| {
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
		const map = terrain.CaveBiomeMap.CaveBiomeMapView.init(main.stackAllocator, .{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1}, 1, 0);
		defer map.deinit();
		return map.getBiome(wx - map.pos.wx, wy - map.pos.wy, wz - map.pos.wz);
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
		if (block.blockEntity()) |blockEntity| {
			blockEntity.getServerToClientData(.{x, y, z}, &ch.super, blockEntityDataWriter);
		}
		return block;
	}

	/// Returns the actual block on failure
	pub fn cmpxchgBlock(self: *ServerWorld, wx: i32, wy: i32, wz: i32, oldBlock: ?Block, _newBlock: Block) ?Block {
		main.sync.threadContext.assertCorrectContext(.server);
		const baseChunk = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{.wx = wx & ~@as(i32, chunk.chunkMask), .wy = wy & ~@as(i32, chunk.chunkMask), .wz = wz & ~@as(i32, chunk.chunkMask), .voxelSize = 1});
		defer baseChunk.decreaseRefCount();
		const pos: chunk.BlockPos = .fromWorldCoords(wx, wy, wz);
		baseChunk.mutex.lock();
		const currentBlock = baseChunk.getBlock(pos.x, pos.y, pos.z);
		if (oldBlock != null) {
			if (oldBlock.? != currentBlock) {
				baseChunk.mutex.unlock();
				return currentBlock;
			}
		}
		baseChunk.mutex.unlock();

		var newBlock = _newBlock;
		for (chunk.Neighbor.iterable) |neighbor| {
			const neighborPos, const chunkLocation = pos.neighbor(neighbor);
			var ch = baseChunk;
			if (chunkLocation == .inNeighborChunk) {
				ch = ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{
					.wx = baseChunk.super.pos.wx +% pos.x +% neighbor.relX() & ~@as(i32, chunk.chunkMask),
					.wy = baseChunk.super.pos.wy +% pos.y +% neighbor.relY() & ~@as(i32, chunk.chunkMask),
					.wz = baseChunk.super.pos.wz +% pos.z +% neighbor.relZ() & ~@as(i32, chunk.chunkMask),
					.voxelSize = 1,
				});
			}
			defer if (ch != baseChunk) {
				ch.decreaseRefCount();
			};

			ch.mutex.lock();
			defer ch.mutex.unlock();

			var neighborBlock = ch.getBlock(neighborPos.x, neighborPos.y, neighborPos.z);
			if (neighborBlock.mode().dependsOnNeighbors and neighborBlock.mode().updateData(&neighborBlock, neighbor.reverse(), newBlock)) {
				ch.updateBlockAndSetChanged(neighborPos.x, neighborPos.y, neighborPos.z, neighborBlock);

				const userList = server.getUserList(main.stackAllocator);
				defer main.stackAllocator.free(userList);

				for (userList) |user| {
					main.network.protocols.block_update.send(user.conn, &.{.{.pos = .{wx +% neighbor.relX(), wy +% neighbor.relY(), wz +% neighbor.relZ()}, .newBlock = neighborBlock, .blockEntityData = &.{}}});
				}
			}
			if (newBlock.mode().dependsOnNeighbors) {
				_ = newBlock.mode().updateData(&newBlock, neighbor, neighborBlock);
			}
		}
		baseChunk.mutex.lock();
		defer baseChunk.mutex.unlock();

		if (currentBlock != _newBlock) {
			if (currentBlock.blockEntity()) |blockEntity| {
				blockEntity.updateServerData(.{wx, wy, wz}, &baseChunk.super, .remove) catch |err| {
					std.log.err("Got error {s} while trying to remove entity data in position {} for block {s}", .{@errorName(err), Vec3i{wx, wy, wz}, currentBlock.id()});
				};
			}
		}
		baseChunk.updateBlockAndSetChanged(pos.x, pos.y, pos.z, newBlock);

		const userList = server.getUserList(main.stackAllocator);
		defer main.stackAllocator.free(userList);

		for (userList) |user| {
			main.network.protocols.block_update.send(user.conn, &.{.{.pos = .{wx, wy, wz}, .newBlock = newBlock, .blockEntityData = &.{}}});
		}
		// onBreak event
		if (oldBlock) |block| {
			if (block.typ != newBlock.typ) {
				_ = block.onBreak().run(.{
					.block = block,
					.chunk = baseChunk,
					.blockPos = pos,
				});
			}
		}
		self.triggerNeighborBlockUpdates(wx, wy, wz);

		return null;
	}
	pub fn triggerNeighborBlockUpdates(self: *ServerWorld, wx: i32, wy: i32, wz: i32) void {
		for (chunk.Neighbor.iterable) |value| {
			const pos = Vec3i{
				wx + value.relX(),
				wy + value.relY(),
				wz + value.relZ(),
			};

			var ch = self.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse continue;
			defer ch.decreaseRefCount();

			ch.blockUpdateSystem.add(.{
				.x = @truncate(@as(u32, @bitCast(pos[0]))),
				.y = @truncate(@as(u32, @bitCast(pos[1]))),
				.z = @truncate(@as(u32, @bitCast(pos[2]))),
			});
		}
	}

	pub fn updateBlock(self: *ServerWorld, wx: i32, wy: i32, wz: i32, newBlock: Block) void {
		_ = self.cmpxchgBlock(wx, wy, wz, null, newBlock);
	}

	pub fn queueChunkUpdateAndDecreaseRefCount(self: *ServerWorld, ch: *ServerChunk) void {
		self.mutex.lock();
		self.chunkUpdateQueue.pushBack(.{.ch = ch, .milliTimeStamp = main.timestamp().toMilliseconds()});
		self.mutex.unlock();
	}

	pub fn queueRegionFileUpdateAndDecreaseRefCount(self: *ServerWorld, region: *storage.RegionFile) void {
		self.mutex.lock();
		self.regionUpdateQueue.pushBack(.{.region = region, .milliTimeStamp = main.timestamp().toMilliseconds()});
		self.mutex.unlock();
	}
};
