const std = @import("std");

const main = @import("root");
const Block = main.blocks.Block;
const Cache = main.utils.Cache;
const chunk = main.chunk;
const ChunkPosition = chunk.ChunkPosition;
const Chunk = chunk.Chunk;
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

const ChunkManager = struct {
	world: *ServerWorld,
	terrainGenerationProfile: server.terrain.TerrainGenerationProfile,

	// There will be at most 1 GiB of chunks in here. TODO: Allow configuring this in the server settings.
	const reducedChunkCacheMask = 2047;
	var chunkCache: Cache(Chunk, reducedChunkCacheMask+1, 4, chunkDeinitFunctionForCache) = .{};

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
		
		pub fn schedule(pos: ChunkPosition, source: ?*User) void {
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

		pub fn isStillNeeded(self: *ChunkLoadTask) bool {
			// TODO:
			if(self.source) |source| {
				_ = source;
				// TODO: This requires not garbage-collecting the source User.
//				boolean isConnected = false;
//				for(User user : Server.users) {
//					if(source == user) {
//						isConnected = true;
//						break;
//					}
//				}
//				if(!isConnected) {
//					return false;
//				}
			}
			if(std.time.milliTimestamp() - self.creationTime > 10000) { // Only remove stuff after 10 seconds to account for trouble when for example teleporting.
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
		
		pub fn schedule(pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
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

		pub fn isStillNeeded(self: *LightMapLoadTask) bool {
			_ = self; // TODO: Do these tasks need to be culled?
			return true;
		}

		pub fn run(self: *LightMapLoadTask) void {
			defer self.clean();
			const map = terrain.LightMap.getOrGenerateFragment(self.pos.wx, self.pos.wz, self.pos.voxelSize);
			defer map.decreaseRefCount();
			if(self.source) |source| {
				main.network.Protocols.lightMapTransmission.sendLightMap(source.conn, map);
			} else {
				server.mutex.lock();
				defer server.mutex.unlock();
				for(server.users.items) |user| {
					main.network.Protocols.lightMapTransmission.sendLightMap(user.conn, map);
				}
			}
		}

		pub fn clean(self: *LightMapLoadTask) void {
			main.globalAllocator.destroy(self);
		}
	};

	pub fn init(world: *ServerWorld, settings: JsonElement) !ChunkManager {
		const self = ChunkManager {
			.world = world,
			.terrainGenerationProfile = try server.terrain.TerrainGenerationProfile.init(settings, world.seed),
		};
		server.terrain.init(self.terrainGenerationProfile);
		return self;
	}

	pub fn deinit(self: ChunkManager) void {
		// TODO:
//		for(Cache<MapFragment> cache : mapCache) {
//			cache.clear();
//		}
//		for(int i = 0; i < 5; i++) { // Saving one chunk may create and update a new lower resolution chunk.
//		
//			for(ReducedChunk[] array : reducedChunkCache.cache) {
//				array = Arrays.copyOf(array, array.length); // Make a copy to prevent issues if the cache gets resorted during cleanup.
//				for(ReducedChunk chunk : array) {
//					if (chunk != null)
//						chunk.clean();
//				}
//			}
//		}
//		ThreadPool.clear();
//		ChunkIO.clean();
		chunkCache.clear();
		server.terrain.deinit();
		main.assets.unloadAssets();
		self.terrainGenerationProfile.deinit();
	}

	pub fn queueLightMap(self: ChunkManager, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		_ = self;
		LightMapLoadTask.schedule(pos, source);
	}

	pub fn queueChunk(self: ChunkManager, pos: ChunkPosition, source: ?*User) void {
		_ = self;
		ChunkLoadTask.schedule(pos, source);
	}

	pub fn generateChunk(pos: ChunkPosition, source: ?*User) void {
		const ch = getOrGenerateChunk(pos);
		if(source) |_source| {
			main.network.Protocols.chunkTransmission.sendChunk(_source.conn, ch);
		} else { // TODO: This feature was temporarily removed to keep compatibility with the zig version.
			server.mutex.lock();
			defer server.mutex.unlock();
			for(server.users.items) |user| {
				main.network.Protocols.chunkTransmission.sendChunk(user.conn, ch);
			}
		}
	}

	fn chunkInitFunctionForCache(pos: ChunkPosition) *Chunk {
		const ch = Chunk.init(pos);
		ch.generated = true;
//	TODO:	if(!ChunkIO.loadChunkFromFile(world, this)) {
		const caveMap = terrain.CaveMap.CaveMapView.init(ch);
		defer caveMap.deinit();
		const biomeMap = terrain.CaveBiomeMap.CaveBiomeMapView.init(ch);
		defer biomeMap.deinit();
		for(server.world.?.chunkManager.terrainGenerationProfile.generators) |generator| {
			generator.generate(server.world.?.seed ^ generator.generatorSeed, ch, caveMap, biomeMap);
		}
		return ch;
	}

	fn chunkDeinitFunctionForCache(ch: *Chunk) void {
		ch.deinit();
		// TODO: Store chunk.
	}
	/// Generates a normal chunk at a given location, or if possible gets it from the cache.
	pub fn getOrGenerateChunk(pos: ChunkPosition) *Chunk {
		return chunkCache.findOrCreate(pos, chunkInitFunctionForCache);
	}

	pub fn getChunkFromCache(pos: ChunkPosition) ?*Chunk {
		return chunkCache.find(pos);
	}

//	public void forceSave() {
//		for(int i = 0; i < 5; i++) { // Saving one chunk may create and update a new lower resolution chunk.
//			reducedChunkCache.foreach(Chunk::save);
//		}
//	}
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
		const worldData: JsonElement = try self.dir.readToJson(main.globalAllocator, "world.dat");
		defer worldData.free(main.globalAllocator);
		if(worldData.get(u32, "version", 0) != worldDataVersion) {
			std.log.err("Cannot read world file version {}. Expected version {}.", .{worldData.get(u32, "version", 0), worldDataVersion});
			return error.OldWorld;
		}
		return worldData.get(u64, "seed", 0);
	}

	pub fn loadWorldData(self: WorldIO) !void {
		const worldData: JsonElement = try self.dir.readToJson(main.globalAllocator, "world.dat");
		defer worldData.free(main.globalAllocator);

		const entityJson = worldData.getChild("entities");
		_ = entityJson;

//			Entity[] entities = new Entity[entityJson.array.size()];
//			for(int i = 0; i < entities.length; i++) {
//				// TODO: Only load entities that are in loaded chunks.
//				entities[i] = EntityIO.loadEntity((JsonObject)entityJson.array.get(i), world);
//			}
//			world.setEntities(entities);
		self.world.doGameTimeCycle = worldData.get(bool, "doGameTimeCycle", true);
		self.world.gameTime = worldData.get(i64, "gameTime", 0);
		const spawnData = worldData.getChild("spawn");
		self.world.spawn[0] = spawnData.get(i32, "x", 0);
		self.world.spawn[1] = spawnData.get(i32, "y", 0);
		self.world.spawn[2] = spawnData.get(i32, "z", 0);
	}

	pub fn saveWorldData(self: WorldIO) !void {
		const worldData: JsonElement = JsonElement.initObject(main.globalAllocator);
		defer worldData.free(main.globalAllocator);
		worldData.put("version", worldDataVersion);
		worldData.put("seed", self.world.seed);
		worldData.put("doGameTimeCycle", self.world.doGameTimeCycle);
		worldData.put("gameTime", self.world.gameTime);
		// TODO:
//			worldData.put("entityCount", world.getEntities().length);
		const spawnData = JsonElement.initObject(main.globalAllocator);
		spawnData.put("x", self.world.spawn[0]);
		spawnData.put("y", self.world.spawn[1]);
		spawnData.put("z", self.world.spawn[2]);
		worldData.put("spawn", spawnData);
		// TODO:
//			JsonArray entityData = new JsonArray();
//			worldData.put("entities", entityData);
//			// TODO: Store entities per chunk.
//			for (Entity ent : world.getEntities()) {
//				if (ent != null && ent.getType().getClass() != PlayerEntity.class) {
//					entityData.add(ent.save());
//				}
//			}
		try self.dir.writeJson("world.dat", worldData);
	}
};

pub const ServerWorld = struct {
	pub const dayCycle: u31 = 12000; // Length of one in-game day in units of 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	pub const earthGravity: f32 = 9.81;

	itemDropManager: ItemDropManager = undefined,
	blockPalette: *main.assets.BlockPalette = undefined,
	chunkManager: ChunkManager = undefined,
//	TODO: protected HashMap<HashMapKey3D, MetaChunk> metaChunks = new HashMap<HashMapKey3D, MetaChunk>();
//	TODO: protected NormalChunk[] chunks = new NormalChunk[0];

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
	// TODO:
//	protected ArrayList<Entity> entities = new ArrayList<>();

	pub fn init(name: []const u8, nullGeneratorSettings: ?JsonElement) !*ServerWorld {
		const self = main.globalAllocator.create(ServerWorld);
		errdefer main.globalAllocator.destroy(self);
		self.* = ServerWorld {
			.lastUpdateTime = std.time.milliTimestamp(),
			.milliTime = std.time.milliTimestamp(),
			.lastUnimportantDataSent = std.time.milliTimestamp(),
			.seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp()))),
			.name = name,
		};
		self.itemDropManager.init(main.globalAllocator, self, self.gravity);
		errdefer self.itemDropManager.deinit();

		var loadArena = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
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
		self.blockPalette = try main.assets.BlockPalette.init(main.globalAllocator, blockPaletteJson.getChild("blocks")); // TODO: Figure out why this is inconsistent with the save call.
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

//		TODO: // Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
//		ModLoader.postWorldGen(registries);
//
		self.chunkManager = try ChunkManager.init(self, generatorSettings);
		errdefer self.chunkManager.deinit();
		try self.generate();
		self.itemDropManager.loadFrom(try files.readToJson(arenaAllocator, try std.fmt.bufPrint(&buf, "saves/{s}/items.json", .{name})));
		return self;
	}

	pub fn deinit(self: *ServerWorld) void {
		self.chunkManager.deinit();
		self.itemDropManager.deinit();
		self.blockPalette.deinit();
		self.wio.deinit();
		main.globalAllocator.destroy(self);
	}

	fn generate(self: *ServerWorld) !void {
		try self.wio.loadWorldData(); // load data here in order for entities to also be loaded.

		if(!self.generated) {
			var seed: u64 = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
			std.log.info("Finding position..", .{});
			for(0..1000) |_| {
				self.spawn[0] = main.random.nextIntBounded(u31, &seed, 65536);
				self.spawn[2] = main.random.nextIntBounded(u31, &seed, 65536);
				std.log.info("Trying ({}, {})", .{self.spawn[0], self.spawn[2]});
				if(self.isValidSpawnLocation(self.spawn[0], self.spawn[2])) break;
			}
			const map = terrain.SurfaceMap.getOrGenerateFragment(self.spawn[0], self.spawn[2], 1);
			defer map.deinit();
			self.spawn[1] = @intFromFloat(map.getHeight(self.spawn[0], self.spawn[2]) + 1);
		}
		self.generated = true;
		try self.wio.saveWorldData();
	}


	pub fn findPlayer(self: *ServerWorld, user: *User) void {
		var buf: [1024]u8 = undefined;
		const playerData = files.readToJson(main.globalAllocator, std.fmt.bufPrint(&buf, "saves/{s}/player/{s}.json", .{self.name, user.name}) catch "") catch .JsonNull; // TODO: Utils.escapeFolderName(user.name)
		defer playerData.free(main.globalAllocator);
		const player = &user.player;
		if(playerData == .JsonNull) {
			// Generate a new player:
			player.pos = @floatFromInt(self.spawn);
		} else {
			player.loadFrom(playerData);
		}
		// TODO: addEntity(player);
	}

//	private void savePlayers() {
//		for(User user : Server.users) {
//			try {
//				File file = new File("saves/" + name + "/players/" + Utils.escapeFolderName(user.name) + ".json");
//				file.getParentFile().mkdirs();
//				PrintWriter writer = new PrintWriter(new FileOutputStream("saves/" + name + "/players/" + Utils.escapeFolderName(user.name) + ".json"), false, StandardCharsets.UTF_8);
//				user.player.save().writeObjectToStream(writer);
//				writer.close();
//			} catch(FileNotFoundException e) {
//				Logger.error(e);
//			}
//		}
//	}
	pub fn forceSave(self: *ServerWorld) !void {
		// TODO:
//		for(MetaChunk chunk : metaChunks.values().toArray(new MetaChunk[0])) {
//			if (chunk != null) chunk.save();
//		}
		try self.wio.saveWorldData();
		// TODO:
//		savePlayers();
//		chunkManager.forceSave();
//		ChunkIO.save();
		const itemDropJson = self.itemDropManager.store(main.globalAllocator);
		defer itemDropJson.free(main.globalAllocator);
		var buf: [32768]u8 = undefined;
		try files.writeJson(try std.fmt.bufPrint(&buf, "saves/{s}/items.json", .{self.name}), itemDropJson);
	}
// TODO:
//	public void addEntity(Entity ent) {
//		entities.add(ent);
//	}
//
//	public void removeEntity(Entity ent) {
//		entities.remove(ent);
//	}
//
//	public void setEntities(Entity[] arr) {
//		entities = new ArrayList<>(arr.length);
//		for (Entity e : arr) {
//			entities.add(e);
//		}
//	}

	fn isValidSpawnLocation(_: *ServerWorld, wx: i32, wz: i32) bool {
		const map = terrain.SurfaceMap.getOrGenerateFragment(wx, wz, 1);
		defer map.deinit();
		return map.getBiome(wx, wz).isValidPlayerSpawn;
	}

	pub fn dropWithCooldown(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32, pickupCooldown: u32) void {
		const vel = vec.floatCast(f64, dir*@as(Vec3d, @splat(velocity)));
		self.itemDropManager.add(pos, vel, stack, server.updatesPerSec*900, pickupCooldown);
	}

	pub fn drop(self: *ServerWorld, stack: ItemStack, pos: Vec3d, dir: Vec3f, velocity: f32) void {
		self.dropWithCooldown(stack, pos, dir, velocity, 0);
	}

// TODO:
//	@Override
//	public void updateBlock(int x, int y, int z, int newBlock) {
//		NormalChunk ch = getChunk(x, y, z);
//		if (ch != null) {
//			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
//			if(old == newBlock) return;
//			ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
//			// Send the block update to all players:
//			for(User user : Server.users) {
//				Protocols.BLOCK_UPDATE.send(user, x, y, z, newBlock);
//			}
//			if((old & Blocks.TYPE_MASK) == (newBlock & Blocks.TYPE_MASK)) return;
//			for(BlockDrop drop : Blocks.blockDrops(old)) {
//				int amount = (int)(drop.amount);
//				float randomPart = drop.amount - amount;
//				if (Math.random() < randomPart) amount++;
//				if (amount > 0) {
//					itemEntityManager.add(x, y, z, 0, 0, 0, new ItemStack(drop.item, amount), 30*900);
//				}
//			}
//		}
//	}

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
			for(server.users.items) |user| {
				main.network.Protocols.genericUpdate.sendTimeAndBiome(user.conn, self);
			}
		}
		// TODO:
//		// Entities
//		for (int i = 0; i < entities.size(); i++) {
//			Entity en = entities.get(i);
//			en.update(deltaTime);
//			// Check item entities:
//			if (en.getInventory() != null) {
//				itemEntityManager.checkEntity(en);
//			}
//		}

		// Item Entities
		self.itemDropManager.update(deltaTime);
		// TODO:
//		// Block Entities
//		for(MetaChunk chunk : metaChunks.values()) {
//			chunk.updateBlockEntities();
//		}
//
//		// Liquids
//		if (gameTime % 3 == 0) {
//			//Profiler.startProfiling();
//			for(MetaChunk chunk : metaChunks.values()) {
//				chunk.liquidUpdate();
//			}
//			//Profiler.printProfileTime("liquid-update");
//		}
//
//		seek();
	}

// TODO:
//	@Override
	pub fn queueChunks(self: *ServerWorld, positions: []ChunkPosition, source: ?*User) void {
		for(positions) |pos| {
			self.queueChunk(pos, source);
		}
	}

	pub fn queueChunk(self: *ServerWorld, pos: ChunkPosition, source: ?*User) void {
		self.chunkManager.queueChunk(pos, source);
	}

	pub fn queueLightMap(self: *ServerWorld, pos: terrain.SurfaceMap.MapFragmentPosition, source: ?*User) void {
		self.chunkManager.queueLightMap(pos, source);
	}

	pub fn seek() void {
		// TODO: Remove this MetaChunk stuff. It wasn't really useful and made everything needlessly complicated.
//		// Care about the metaChunks:
//		HashMap<HashMapKey3D, MetaChunk> oldMetaChunks = new HashMap<>(metaChunks);
//		HashMap<HashMapKey3D, MetaChunk> newMetaChunks = new HashMap<>();
//		for(User user : Server.users) {
//			ArrayList<NormalChunk> chunkList = new ArrayList<>();
//			int metaRenderDistance = (int)Math.ceil(Settings.entityDistance/(float)(MetaChunk.metaChunkSize*Chunk.chunkSize));
//			int x0 = (int)user.player.getPosition().x >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//			int y0 = (int)user.player.getPosition().y >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//			int z0 = (int)user.player.getPosition().z >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//			for(int metaX = x0 - metaRenderDistance; metaX <= x0 + metaRenderDistance + 1; metaX++) {
//				for(int metaY = y0 - metaRenderDistance; metaY <= y0 + metaRenderDistance + 1; metaY++) {
//					for(int metaZ = z0 - metaRenderDistance; metaZ <= z0 + metaRenderDistance + 1; metaZ++) {
//						HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
//						if(newMetaChunks.containsKey(key)) continue; // It was already updated from another players perspective.
//						// Check if it already exists:
//						MetaChunk metaChunk = oldMetaChunks.get(key);
//						oldMetaChunks.remove(key);
//						if (metaChunk == null) {
//							metaChunk = new MetaChunk(metaX *(MetaChunk.metaChunkSize*Chunk.chunkSize), metaY*(MetaChunk.metaChunkSize*Chunk.chunkSize), metaZ *(MetaChunk.metaChunkSize*Chunk.chunkSize), this);
//						}
//						newMetaChunks.put(key, metaChunk);
//						metaChunk.update(Settings.entityDistance, chunkList);
//					}
//				}
//			}
//			oldMetaChunks.forEach((key, chunk) -> {
//				chunk.clean();
//			});
//			chunks = chunkList.toArray(new NormalChunk[0]);
//			metaChunks = newMetaChunks;
//		}
	}
//
//	public MetaChunk getMetaChunk(int wx, int wy, int wz) {
//		// Test if the metachunk exists:
//		int metaX = wx >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//		int metaY = wy >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//		int metaZ = wz >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
//		HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
//		return metaChunks.get(key);
//	}

	pub fn getChunk(self: *ServerWorld, x: i32, y: i32, z: i32) ?*Chunk {
		_ = self;
		_ = x;
		_ = y;
		_ = z;
		// TODO:
//		MetaChunk meta = getMetaChunk(wx, wy, wz);
//		if (meta != null) {
//			return meta.getChunk(wx, wy, wz);
//		}
		return null;
	}
// TODO:
//	public BlockEntity getBlockEntity(int x, int y, int z) {
//		/*BlockInstance bi = getBlockInstance(x, y, z);
//		Chunk ck = _getNoGenerateChunk(bi.getX() >> NormalChunk.chunkShift, bi.getZ() >> NormalChunk.chunkShift);
//		return ck.blockEntities().get(bi);*/
//		return null; // TODO: Work on BlockEntities!
//	}
//	public NormalChunk[] getChunks() {
//		return chunks;
//	}
//
//	public Entity[] getEntities() {
//		return entities.toArray(new Entity[0]);
//	}
//
//	public int getHeight(int wx, int wz) {
//		return (int)chunkManager.getOrGenerateMapFragment(wx, wz, 1).getHeight(wx, wz);
//	}
//	@Override
//	public void cleanup() {
//		// Be sure to dereference and finalize the maximum of things
//		try {
//			for(MetaChunk chunk : metaChunks.values()) {
//				if (chunk != null) chunk.clean();
//			}
//			chunkManager.forceSave();
//			ChunkIO.save();
//
//			chunkManager.cleanup();
//
//			ChunkIO.clean();
//			
//			wio.saveWorldData();
//			savePlayers();
//			JsonParser.storeToFile(itemEntityManager.store(), "saves/" + name + "/items.json");
//			metaChunks = null;
//		} catch (Exception e) {
//			Logger.error(e);
//		}
//	}
//	@Override
//	public CurrentWorldRegistries getCurrentRegistries() {
//		return registries;
//	}

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

};
