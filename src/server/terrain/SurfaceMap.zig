const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const ZonElement = main.ZonElement;
const Vec3d = main.vec.Vec3d;
const BinaryWriter = main.utils.BinaryWriter;
const BinaryReader = main.utils.BinaryReader;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const Biome = terrain.biomes.Biome;

pub const MapFragmentPosition = struct {
	wx: i32,
	wy: i32,
	voxelSize: u31,
	voxelSizeShift: u5,

	pub fn init(wx: i32, wy: i32, voxelSize: u31) MapFragmentPosition {
		std.debug.assert(voxelSize - 1 & voxelSize == 0); // voxelSize must be a power of 2.
		std.debug.assert(wx & voxelSize - 1 == 0 and wy & voxelSize - 1 == 0); // The coordinates are misaligned. They need to be aligned to the voxelSize grid.
		return MapFragmentPosition{
			.wx = wx,
			.wy = wy,
			.voxelSize = voxelSize,
			.voxelSizeShift = @ctz(voxelSize),
		};
	}

	pub fn equals(self: MapFragmentPosition, other: anytype) bool {
		if(other) |ch| {
			return self.wx == ch.pos.wx and self.wy == ch.pos.wy and self.voxelSize == ch.pos.voxelSize;
		}
		return false;
	}

	pub fn hashCode(self: MapFragmentPosition) u32 {
		return @bitCast((self.wx >> (MapFragment.mapShift + self.voxelSizeShift))*%33 +% (self.wy >> (MapFragment.mapShift + self.voxelSizeShift)) ^ self.voxelSize);
	}

	pub fn getMinDistanceSquared(self: MapFragmentPosition, playerPosition: Vec3d, comptime width: comptime_int) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(width, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0]);
		var dy = @abs(@as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1]);
		dx = @max(0, dx - halfWidth);
		dy = @max(0, dy - halfWidth);
		return dx*dx + dy*dy;
	}

	pub fn getPriority(self: MapFragmentPosition, playerPos: Vec3d, comptime width: comptime_int) f32 {
		return -@as(f32, @floatCast(self.getMinDistanceSquared(playerPos, width)))/@as(f32, @floatFromInt(self.voxelSize*self.voxelSize)) + 2*@as(f32, @floatFromInt(std.math.log2_int(u31, self.voxelSize)))*width*width;
	}
};

/// Generates and stores the height and Biome maps of the planet.
pub const MapFragment = struct { // MARK: MapFragment
	pub const biomeShift = 5;
	/// The average diameter of a biome.
	pub const biomeSize = 1 << biomeShift;
	pub const mapShift = 8;
	pub const mapSize = 1 << mapShift;
	pub const mapMask = mapSize - 1;

	heightMap: [mapSize][mapSize]i32 = undefined,
	biomeMap: [mapSize][mapSize]*const Biome = undefined,
	minHeight: i32 = std.math.maxInt(i32),
	maxHeight: i32 = 0,
	pos: MapFragmentPosition,

	wasStored: Atomic(bool) = .init(false),

	pub fn init(self: *MapFragment, wx: i32, wy: i32, voxelSize: u31) void {
		self.* = .{
			.pos = MapFragmentPosition.init(wx, wy, voxelSize),
		};
	}

	fn privateDeinit(self: *MapFragment) void {
		memoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *MapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	pub fn getBiome(self: *MapFragment, wx: i32, wy: i32) *const Biome {
		const xIndex = wx >> self.pos.voxelSizeShift & mapMask;
		const yIndex = wy >> self.pos.voxelSizeShift & mapMask;
		return self.biomeMap[@intCast(xIndex)][@intCast(yIndex)];
	}

	pub fn getHeight(self: *MapFragment, wx: i32, wy: i32) i32 {
		const xIndex = wx >> self.pos.voxelSizeShift & mapMask;
		const yIndex = wy >> self.pos.voxelSizeShift & mapMask;
		return self.heightMap[@intCast(xIndex)][@intCast(yIndex)];
	}

	const StorageHeader = struct {
		const minSupportedVersion: u8 = 0;
		const activeVersion: u8 = 1;
		version: u8 = activeVersion,
		neighborInfo: NeighborInfo,
	};
	const NeighborInfo = packed struct(u8) {
		@"-o": bool = false,
		@"+o": bool = false,
		@"o-": bool = false,
		@"o+": bool = false,
		@"--": bool = false,
		@"-+": bool = false,
		@"+-": bool = false,
		@"++": bool = false,
	};

	pub fn load(self: *MapFragment, biomePalette: *main.assets.Palette, originalHeightMap: ?*[mapSize][mapSize]i32) !NeighborInfo {
		const saveFolder: []const u8 = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps", .{main.server.world.?.path}) catch unreachable;
		defer main.stackAllocator.free(saveFolder);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}.surface", .{saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy}) catch unreachable;
		defer main.stackAllocator.free(path);

		const fullData = try main.files.cubyzDir().read(main.stackAllocator, path);
		defer main.stackAllocator.free(fullData);

		var fullReader = BinaryReader.init(fullData);

		const header: StorageHeader = .{
			.version = try fullReader.readInt(u8),
			.neighborInfo = @bitCast(try fullReader.readInt(u8)),
		};
		switch(header.version) {
			0 => { // TODO: Remove after next breaking change
				const rawData: []u8 = main.stackAllocator.alloc(u8, mapSize*mapSize*(@sizeOf(u32) + 2*@sizeOf(f32)));
				defer main.stackAllocator.free(rawData);
				if(try main.utils.Compression.inflateTo(rawData, fullReader.remaining) != rawData.len) return error.CorruptedFile;
				const biomeData = rawData[0 .. mapSize*mapSize*@sizeOf(u32)];
				const heightData = rawData[mapSize*mapSize*@sizeOf(u32) ..][0 .. mapSize*mapSize*@sizeOf(f32)];
				const originalHeightData = rawData[mapSize*mapSize*(@sizeOf(u32) + @sizeOf(f32)) ..][0 .. mapSize*mapSize*@sizeOf(f32)];
				for(0..mapSize) |x| {
					for(0..mapSize) |y| {
						self.biomeMap[x][y] = main.server.terrain.biomes.getById(biomePalette.palette.items[std.mem.readInt(u32, biomeData[4*(x*mapSize + y) ..][0..4], .big)]);
						self.heightMap[x][y] = @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, heightData[4*(x*mapSize + y) ..][0..4], .big))));
						if(originalHeightMap) |map| map[x][y] = @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, originalHeightData[4*(x*mapSize + y) ..][0..4], .big))));
					}
				}
			},
			1 => {
				const biomeDataSize = mapSize*mapSize*@sizeOf(u32);
				const heightDataSize = mapSize*mapSize*@sizeOf(i32);
				const originalHeightDataSize = mapSize*mapSize*@sizeOf(i32);

				const rawData: []u8 = main.stackAllocator.alloc(u8, biomeDataSize + heightDataSize + originalHeightDataSize);
				defer main.stackAllocator.free(rawData);
				if(try main.utils.Compression.inflateTo(rawData, fullReader.remaining) != rawData.len) return error.CorruptedFile;

				var reader = BinaryReader.init(rawData);

				for(0..mapSize) |x| for(0..mapSize) |y| {
					self.biomeMap[x][y] = main.server.terrain.biomes.getById(biomePalette.palette.items[try reader.readInt(u32)]);
				};
				for(0..mapSize) |x| for(0..mapSize) |y| {
					self.heightMap[x][y] = try reader.readInt(i32);
				};
				if(originalHeightMap) |map| for(0..mapSize) |x| for(0..mapSize) |y| {
					map[x][y] = try reader.readInt(i32);
				};
			},
			else => return error.OutdatedFileVersion,
		}
		self.wasStored.store(true, .monotonic);
		return header.neighborInfo;
	}

	pub fn save(self: *MapFragment, originalData: ?*[mapSize][mapSize]i32, neighborInfo: NeighborInfo) void {
		const biomeDataSize = mapSize*mapSize*@sizeOf(u32);
		const heightDataSize = mapSize*mapSize*@sizeOf(i32);
		const originalHeightDataSize = mapSize*mapSize*@sizeOf(i32);

		var writer = BinaryWriter.initCapacity(main.stackAllocator, biomeDataSize + heightDataSize + originalHeightDataSize);
		defer writer.deinit();

		for(0..mapSize) |x| for(0..mapSize) |y| writer.writeInt(u32, self.biomeMap[x][y].paletteId);
		for(0..mapSize) |x| for(0..mapSize) |y| writer.writeInt(i32, self.heightMap[x][y]);
		for(0..mapSize) |x| for(0..mapSize) |y| writer.writeInt(i32, (if(originalData) |map| map else &self.heightMap)[x][y]);

		const compressedData = main.utils.Compression.deflate(main.stackAllocator, writer.data.items, .fast);
		defer main.stackAllocator.free(compressedData);

		var outputWriter = BinaryWriter.initCapacity(main.stackAllocator, @sizeOf(StorageHeader) + compressedData.len);
		defer outputWriter.deinit();

		const header: StorageHeader = .{
			.neighborInfo = neighborInfo,
		};
		outputWriter.writeInt(u8, header.version);
		outputWriter.writeInt(u8, @bitCast(header.neighborInfo));
		outputWriter.writeSlice(compressedData);

		const saveFolder: []const u8 = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps", .{main.server.world.?.path}) catch unreachable;
		defer main.stackAllocator.free(saveFolder);

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}/{}.surface", .{saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy}) catch unreachable;
		defer main.stackAllocator.free(path);
		const folder = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{}/{}", .{saveFolder, self.pos.voxelSize, self.pos.wx}) catch unreachable;
		defer main.stackAllocator.free(folder);

		main.files.cubyzDir().makePath(folder) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};

		main.files.cubyzDir().write(path, outputWriter.data.items) catch |err| {
			std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
		};
	}
};

/// Generates the detailed(block-level precision) height and biome maps from the climate map.
pub const MapGenerator = struct {
	init: *const fn(parameters: ZonElement) void,
	generateMapFragment: *const fn(fragment: *MapFragment, seed: u64) void,

	var generatorRegistry: std.StringHashMapUnmanaged(MapGenerator) = .{};

	fn registerGenerator(comptime Generator: type) void {
		const self = MapGenerator{
			.init = &Generator.init,
			.generateMapFragment = &Generator.generateMapFragment,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getGeneratorById(id: []const u8) !MapGenerator {
		return generatorRegistry.get(id) orelse {
			std.log.err("Couldn't find map generator with id {s}", .{id});
			return error.UnknownMapGenerator;
		};
	}
};

const cacheSize = 1 << 6; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // ~400MiB MiB Cache size
var cache: Cache(MapFragment, cacheSize, associativity, MapFragment.deferredDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

var memoryPool: main.heap.MemoryPool(MapFragment) = undefined;

pub fn globalInit() void {
	const list = @import("mapgen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		MapGenerator.registerGenerator(@field(list, decl.name));
	}
	memoryPool = .init(main.globalAllocator);
}

pub fn globalDeinit() void {
	MapGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
	memoryPool.deinit();
}

fn cacheInit(pos: MapFragmentPosition) *MapFragment {
	const mapFragment = memoryPool.create();
	mapFragment.init(pos.wx, pos.wy, pos.voxelSize);
	_ = mapFragment.load(main.server.world.?.biomePalette, null) catch {
		profile.mapFragmentGenerator.generateMapFragment(mapFragment, profile.seed);
	};
	return mapFragment;
}

pub fn regenerateLOD(worldName: []const u8) !void { // MARK: regenerateLOD()
	std.log.info("Regenerating map LODs...", .{});
	// Delete old LODs:
	for(1..main.settings.highestSupportedLod + 1) |i| {
		const lod = @as(u32, 1) << @intCast(i);
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps/{}", .{worldName, lod}) catch unreachable;
		defer main.stackAllocator.free(path);
		main.files.cubyzDir().deleteTree(path) catch |err| {
			if(err != error.FileNotFound) {
				std.log.err("Error while deleting directory {s}: {s}", .{path, @errorName(err)});
			}
		};
	}
	// Find all the stored maps:
	var mapPositions = main.List(MapFragmentPosition).init(main.stackAllocator);
	defer mapPositions.deinit();
	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/maps/1", .{worldName}) catch unreachable;
	defer main.stackAllocator.free(path);
	{
		var dirX = try main.files.cubyzDir().openIterableDir(path);
		defer dirX.close();
		var iterX = dirX.iterate();
		while(try iterX.next()) |entryX| {
			if(entryX.kind != .directory) continue;
			const wx = std.fmt.parseInt(i32, entryX.name, 0) catch continue;
			var dirY = try dirX.openIterableDir(entryX.name);
			defer dirY.close();
			var iterY = dirY.iterate();
			while(try iterY.next()) |entryY| {
				if(entryY.kind != .file) continue;
				const nameY = entryY.name[0 .. std.mem.indexOfScalar(u8, entryY.name, '.') orelse entryY.name.len];
				const wy = std.fmt.parseInt(i32, nameY, 0) catch continue;
				mapPositions.append(.{.wx = wx, .wy = wy, .voxelSize = 1, .voxelSizeShift = 0});
			}
		}
	}
	// Load all the stored maps and update their next LODs.
	const interpolationDistance = 64;
	for(mapPositions.items) |pos| {
		main.heap.GarbageCollection.syncPoint();
		var neighborInfo: MapFragment.NeighborInfo = undefined;
		inline for(comptime std.meta.fieldNames(MapFragment.NeighborInfo)) |name| {
			var neighborPos = pos;
			if(name[0] == '+') neighborPos.wx +%= MapFragment.mapSize;
			if(name[0] == '-') neighborPos.wx -%= MapFragment.mapSize;
			if(name[1] == '+') neighborPos.wy +%= MapFragment.mapSize;
			if(name[1] == '-') neighborPos.wy -%= MapFragment.mapSize;
			var isPresent: bool = false;
			for(mapPositions.items) |otherPos| {
				if(neighborPos.wx == otherPos.wx and neighborPos.wy == otherPos.wy) {
					isPresent = true;
					break;
				}
			}
			@field(neighborInfo, name) = isPresent;
		}
		const mapFragment = main.stackAllocator.create(MapFragment);
		defer main.stackAllocator.destroy(mapFragment);
		mapFragment.init(pos.wx, pos.wy, pos.voxelSize);
		var xNoise: [MapFragment.mapSize]f32 = undefined;
		var yNoise: [MapFragment.mapSize]f32 = undefined;
		terrain.noise.FractalNoise1D.generateSparseFractalTerrain(pos.wx, 32, main.server.world.?.seed, &xNoise);
		terrain.noise.FractalNoise1D.generateSparseFractalTerrain(pos.wy, 32, main.server.world.?.seed ^ 0x785298638131, &yNoise);
		var originalHeightMap: [MapFragment.mapSize][MapFragment.mapSize]i32 = undefined;
		const oldNeighborInfo = mapFragment.load(main.server.world.?.biomePalette, &originalHeightMap) catch |err| {
			std.log.err("Error loading map at position {}: {s}", .{pos, @errorName(err)});
			continue;
		};
		if(@as(u8, @bitCast(neighborInfo)) != @as(u8, @bitCast(oldNeighborInfo))) {
			// Now we do the fun stuff
			// Basically we want to only keep the interpolated map in the direction of the changes.
			// Edges:
			if(neighborInfo.@"+o" != oldNeighborInfo.@"+o" or neighborInfo.@"-o" != oldNeighborInfo.@"-o" or neighborInfo.@"o+" != oldNeighborInfo.@"o+" or neighborInfo.@"o-" != oldNeighborInfo.@"o-") {
				for(0..interpolationDistance) |a| { // edges
					for(interpolationDistance..MapFragment.mapSize - interpolationDistance) |b| {
						if(neighborInfo.@"+o" and !oldNeighborInfo.@"+o") {
							const x = MapFragment.mapSize - 1 - a;
							const y = b;
							originalHeightMap[x][y] = mapFragment.heightMap[x][y];
						}
						if(neighborInfo.@"-o" and !oldNeighborInfo.@"-o") {
							const x = a;
							const y = b;
							originalHeightMap[x][y] = mapFragment.heightMap[x][y];
						}
						if(neighborInfo.@"o+" and !oldNeighborInfo.@"o+") {
							const x = b;
							const y = MapFragment.mapSize - 1 - a;
							originalHeightMap[x][y] = mapFragment.heightMap[x][y];
						}
						if(neighborInfo.@"o-" and !oldNeighborInfo.@"o-") {
							const x = b;
							const y = a;
							originalHeightMap[x][y] = mapFragment.heightMap[x][y];
						}
					}
				}
			}
			// Corners:
			{
				for(0..interpolationDistance) |a| { // corners:
					for(0..interpolationDistance) |b| {
						const weirdSquareInterpolation = struct {
							fn interp(x: f32, y: f32) f32 {
								// Basically we want to interpolate the values such that two sides of the square have value zero, while the opposing two sides have value 1.
								// Change coordinate system:
								if(x == y) return 0.5;
								const sqrt2 = @sqrt(0.5);
								const k = sqrt2*x + sqrt2*y - sqrt2;
								const l = -sqrt2*x + sqrt2*y;
								const maxMagnitude = sqrt2 - @abs(k);
								return l/maxMagnitude*0.5 + 0.5;
								// if x = y:
							}
						}.interp;
						var factorA = @as(f32, @floatFromInt(a))/interpolationDistance;
						factorA = (3 - 2*factorA)*factorA*factorA;
						var factorB = @as(f32, @floatFromInt(b))/interpolationDistance;
						factorB = (3 - 2*factorB)*factorB*factorB;
						if(neighborInfo.@"+o" or neighborInfo.@"o+") {
							var factor: f32 = 1;
							if(neighborInfo.@"+o" and neighborInfo.@"o+" == oldNeighborInfo.@"o+" and !oldNeighborInfo.@"+o") factor = weirdSquareInterpolation(1 - factorB, 1 - factorA);
							if(neighborInfo.@"o+" and neighborInfo.@"+o" == oldNeighborInfo.@"+o" and !oldNeighborInfo.@"o+") factor = weirdSquareInterpolation(1 - factorA, 1 - factorB);
							if(neighborInfo.@"+o" == oldNeighborInfo.@"+o" and neighborInfo.@"o+" == oldNeighborInfo.@"o+") factor = 0;
							if(neighborInfo.@"+o" and neighborInfo.@"o+" and neighborInfo.@"++") factor = 1;
							const x = MapFragment.mapSize - 1 - a;
							const y = MapFragment.mapSize - 1 - b;
							originalHeightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(originalHeightMap[x][y]))*(1 - factor));
						}
						if(neighborInfo.@"+o" or neighborInfo.@"o-") {
							var factor: f32 = 1;
							if(neighborInfo.@"+o" and neighborInfo.@"o-" == oldNeighborInfo.@"o-" and !oldNeighborInfo.@"+o") factor = weirdSquareInterpolation(1 - factorB, 1 - factorA);
							if(neighborInfo.@"o-" and neighborInfo.@"+o" == oldNeighborInfo.@"+o" and !oldNeighborInfo.@"o-") factor = weirdSquareInterpolation(1 - factorA, 1 - factorB);
							if(neighborInfo.@"+o" == oldNeighborInfo.@"+o" and neighborInfo.@"o-" == oldNeighborInfo.@"o-") factor = 0;
							if(neighborInfo.@"+o" and neighborInfo.@"o-" and neighborInfo.@"+-") factor = 1;
							const x = MapFragment.mapSize - 1 - a;
							const y = b;
							originalHeightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(originalHeightMap[x][y]))*(1 - factor));
						}
						if(neighborInfo.@"-o" or neighborInfo.@"o+") {
							var factor: f32 = 1;
							if(neighborInfo.@"-o" and neighborInfo.@"o+" == oldNeighborInfo.@"o+" and !oldNeighborInfo.@"-o") factor = weirdSquareInterpolation(1 - factorB, 1 - factorA);
							if(neighborInfo.@"o+" and neighborInfo.@"-o" == oldNeighborInfo.@"-o" and !oldNeighborInfo.@"o+") factor = weirdSquareInterpolation(1 - factorA, 1 - factorB);
							if(neighborInfo.@"-o" == oldNeighborInfo.@"-o" and neighborInfo.@"o+" == oldNeighborInfo.@"o+") factor = 0;
							if(neighborInfo.@"-o" and neighborInfo.@"o+" and neighborInfo.@"-+") factor = 1;
							const x = a;
							const y = MapFragment.mapSize - 1 - b;
							originalHeightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(originalHeightMap[x][y]))*(1 - factor));
						}
						if(neighborInfo.@"-o" or neighborInfo.@"o-") {
							var factor: f32 = 1;
							if(neighborInfo.@"-o" and neighborInfo.@"o-" == oldNeighborInfo.@"o-" and !oldNeighborInfo.@"-o") factor = weirdSquareInterpolation(1 - factorB, 1 - factorA);
							if(neighborInfo.@"o-" and neighborInfo.@"-o" == oldNeighborInfo.@"-o" and !oldNeighborInfo.@"o-") factor = weirdSquareInterpolation(1 - factorA, 1 - factorB);
							if(neighborInfo.@"-o" == oldNeighborInfo.@"-o" and neighborInfo.@"o-" == oldNeighborInfo.@"o-") factor = 0;
							if(neighborInfo.@"-o" and neighborInfo.@"o-" and neighborInfo.@"--") factor = 1;
							const x = a;
							const y = b;
							originalHeightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(originalHeightMap[x][y]))*(1 - factor));
						}
					}
				}
			}
		}
		{ // Interpolate the terraing height:
			const InterpolationPolynomial = struct {
				// Basically we want an interpolation function with the following properties:
				// f(0) = 0
				// f(1) = 1
				// f'(0) = 0
				// f'(1) = 0
				// f(noise) = 0.5
				// This must be a polynomial of degree 4 with a factor x²
				// f(x) = ax⁴ + bx³ + cx²
				// f'(x) = 4ax³ + 3x² + 2cx
				// f(1) = a + b + c = 1 → c = 1 - a - b
				// f'(1) = 4a + 3b + 2c = 0 → 4a + 3b + 2 - 2a - 2b = 0 → 2a + b + 2 = 0 → b = -2a - 2
				// f(noise) = a noise⁴ + b noise³ + c noise² = 0.5 → a noise⁴ + (-2a - 2) noise³ + (3 + a) noise² = 0.5 → a (noise⁴ - 2noise³ + noise²) = 2noise³ - 3 noise² + 0.5
				// → a = (2noise³ - 3 noise² + 0.5)/(noise⁴ - 2noise³ + noise²)
				// → a = (2noise - 3 + 0.5/noise²)/(noise² - 2noise + 1)
				// → a = (2noise - 3 + 0.5/noise²)/(noise - 1)²
				a: f32,
				b: f32,
				c: f32,
				fn get(noise: f32) @This() {
					const noise2 = noise*noise;
					const noise3 = noise2*noise;
					const noise4 = noise2*noise2;
					const a = (2*noise3 - 3*noise2 + 0.5)/(noise4 - 2*noise3 + noise2);
					const b = -2*a - 2;
					const c = 1 - a - b;
					return .{.a = a, .b = b, .c = c};
				}
				fn eval(self: @This(), x: f32) f32 {
					return @max(0, @min(0.99999, ((self.a*x + self.b)*x + self.c)*x*x));
				}
			};
			const generatedMap = main.stackAllocator.create(MapFragment);
			defer main.stackAllocator.destroy(generatedMap);
			generatedMap.init(pos.wx, pos.wy, pos.voxelSize);
			profile.mapFragmentGenerator.generateMapFragment(generatedMap, profile.seed);

			@memcpy(&mapFragment.heightMap, &originalHeightMap);
			for(0..MapFragment.mapSize) |b| {
				const polynomialX = InterpolationPolynomial.get(yNoise[b]*0.5 + 0.25);
				const polynomialY = InterpolationPolynomial.get(xNoise[b]*0.5 + 0.25);
				for(0..interpolationDistance) |a| { // edges
					const factorX = polynomialX.eval(@as(f32, @floatFromInt(a))/interpolationDistance);
					const factorY = polynomialY.eval(@as(f32, @floatFromInt(a))/interpolationDistance);
					if(!neighborInfo.@"+o") {
						const x = MapFragment.mapSize - 1 - a;
						const y = b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factorX + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factorX));
						if(factorX < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"-o") {
						const x = a;
						const y = b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factorX + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factorX));
						if(factorX < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"o+") {
						const x = b;
						const y = MapFragment.mapSize - 1 - a;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factorY + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factorY));
						if(factorY < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"o-") {
						const x = b;
						const y = a;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factorY + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factorY));
						if(factorY < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
				}
			}
			for(0..interpolationDistance) |a| { // corners:
				const polynomialY1 = InterpolationPolynomial.get(xNoise[a]*0.5 + 0.25);
				const polynomialY2 = InterpolationPolynomial.get(xNoise[MapFragment.mapSize - 1 - a]*0.5 + 0.25);
				for(0..interpolationDistance) |b| {
					const polynomialX1 = InterpolationPolynomial.get(yNoise[b]*0.5 + 0.25);
					const polynomialX2 = InterpolationPolynomial.get(yNoise[MapFragment.mapSize - 1 - b]*0.5 + 0.25);
					const factorX1 = polynomialX1.eval(@as(f32, @floatFromInt(a))/interpolationDistance);
					const factorX2 = polynomialX2.eval(@as(f32, @floatFromInt(a))/interpolationDistance);
					const factorY1 = polynomialY1.eval(@as(f32, @floatFromInt(b))/interpolationDistance);
					const factorY2 = polynomialY2.eval(@as(f32, @floatFromInt(b))/interpolationDistance);
					if(!neighborInfo.@"++" and neighborInfo.@"+o" and neighborInfo.@"o+") {
						const factor = 1 - (1 - factorX2)*(1 - factorY2);
						const x = MapFragment.mapSize - 1 - a;
						const y = MapFragment.mapSize - 1 - b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factor));
						if(factor < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"+-" and neighborInfo.@"+o" and neighborInfo.@"o-") {
						const factor = 1 - (1 - factorX1)*(1 - factorY2);
						const x = MapFragment.mapSize - 1 - a;
						const y = b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factor));
						if(factor < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"-+" and neighborInfo.@"-o" and neighborInfo.@"o+") {
						const factor = 1 - (1 - factorX2)*(1 - factorY1);
						const x = a;
						const y = MapFragment.mapSize - 1 - b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factor));
						if(factor < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
					if(!neighborInfo.@"--" and neighborInfo.@"-o" and neighborInfo.@"o-") {
						const factor = 1 - (1 - factorX1)*(1 - factorY1);
						const x = a;
						const y = b;
						mapFragment.heightMap[x][y] = @intFromFloat(0.5 + @as(f32, @floatFromInt(mapFragment.heightMap[x][y]))*factor + @as(f32, @floatFromInt(generatedMap.heightMap[x][y]))*(1 - factor));
						if(factor < 0.25) {
							mapFragment.biomeMap[x][y] = generatedMap.biomeMap[x][y];
						}
					}
				}
			}
		}
		mapFragment.save(&originalHeightMap, neighborInfo); // Store the interpolated map
		// Generate LODs
		var cur = mapFragment;
		while(cur.pos.voxelSizeShift < main.settings.highestSupportedLod) {
			var nextPos = cur.pos;
			nextPos.voxelSize *= 2;
			nextPos.voxelSizeShift += 1;
			const nextMask = ~@as(i32, nextPos.voxelSize*MapFragment.mapSize - 1);
			nextPos.wx &= nextMask;
			nextPos.wy &= nextMask;
			const next = getOrGenerateFragment(nextPos.wx, nextPos.wy, nextPos.voxelSize);
			const offSetX: usize = @intCast((cur.pos.wx -% nextPos.wx) >> nextPos.voxelSizeShift);
			const offSetY: usize = @intCast((cur.pos.wy -% nextPos.wy) >> nextPos.voxelSizeShift);
			for(0..MapFragment.mapSize/2) |x| {
				for(0..MapFragment.mapSize/2) |y| {
					var biomes: [4]?*const Biome = @splat(null);
					var biomeCounts: [4]u8 = @splat(0);
					var height: i32 = 0;
					for(0..2) |dx| {
						for(0..2) |dy| {
							const curX = x*2 + dx;
							const curY = y*2 + dy;
							height += cur.heightMap[curX][curY];
							const biome = cur.biomeMap[curX][curY];
							for(0..4) |i| {
								if(biomes[i] == biome) {
									biomeCounts[i] += 1;
									break;
								} else if(biomes[i] == null) {
									biomes[i] = biome;
									biomeCounts[i] += 1;
									break;
								}
							}
						}
					}
					var bestBiome: *const Biome = biomes[0].?;
					var bestBiomeCount: u8 = biomeCounts[0];
					for(1..4) |i| {
						if(biomeCounts[i] > bestBiomeCount) {
							bestBiomeCount = biomeCounts[i];
							bestBiome = biomes[i].?;
						}
					}
					const nextX = offSetX + x;
					const nextY = offSetY + y;
					next.heightMap[nextX][nextY] = @divFloor(height, 4);
					next.biomeMap[nextX][nextY] = bestBiome;
				}
			}
			next.save(null, .{});
			next.wasStored.store(true, .monotonic);
			cur = next;
		}
	}
	std.log.info("Finished regenerating map LODs...", .{});
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

/// Call deinit on the result.
pub fn getOrGenerateFragment(wx: i32, wy: i32, voxelSize: u31) *MapFragment {
	const compare = MapFragmentPosition.init(
		wx & ~@as(i32, MapFragment.mapMask*voxelSize | voxelSize - 1),
		wy & ~@as(i32, MapFragment.mapMask*voxelSize | voxelSize - 1),
		voxelSize,
	);
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}
