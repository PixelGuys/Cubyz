const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Cache = main.utils.Cache;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const JsonElement = main.JsonElement;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const MapFragment = terrain.SurfaceMap.MapFragment;
const Biome = terrain.biomes.Biome;
const SurfaceMap = terrain.SurfaceMap;

/// Cave biome data from a big chunk of the world.
pub const CaveBiomeMapFragment = struct {
	pub const caveBiomeShift = 7;
	pub const caveBiomeSize = 1 << caveBiomeShift;
	pub const caveBiomeMask = caveBiomeSize - 1;
	pub const caveBiomeMapShift = 11;
	pub const caveBiomeMapSize = 1 << caveBiomeMapShift;
	pub const caveBiomeMapMask = caveBiomeMapSize - 1;

	pos: main.chunk.ChunkPosition,
	biomeMap: [1 << 3*(caveBiomeMapShift - caveBiomeShift)]*const Biome = undefined,
	refCount: std.atomic.Atomic(u16) = std.atomic.Atomic(u16).init(0),

	pub fn init(self: *CaveBiomeMapFragment, wx: i32, wy: i32, wz: i32) !void {
		self.* = .{
			.pos = main.chunk.ChunkPosition {
				.wx = wx, .wy = wy, .wz = wz,
				.voxelSize = caveBiomeSize
			},
		};
	}

	pub fn getIndex(_relX: u31, _relY: u31, _relZ: u31) usize {
		var relX: usize = _relX;
		var relY: usize = _relY;
		var relZ: usize = _relZ;
		std.debug.assert(relX < caveBiomeMapSize);
		std.debug.assert(relY < caveBiomeMapSize);
		std.debug.assert(relZ < caveBiomeMapSize);
		relX >>= caveBiomeShift;
		relY >>= caveBiomeShift;
		relZ >>= caveBiomeShift;
		return relX << 2*(caveBiomeMapShift - caveBiomeShift) | relY << caveBiomeMapShift-caveBiomeShift | relZ;
	}
};

/// A generator for the cave biome map.
pub const CaveBiomeGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generate: *const fn(map: *CaveBiomeMapFragment, seed: u64) Allocator.Error!void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(CaveBiomeGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) !void {
		var self = CaveBiomeGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		try generatorRegistry.put(main.globalAllocator, Generator.id, self);
	}

	pub fn getAndInitGenerators(allocator: std.mem.Allocator, settings: JsonElement) ![]CaveBiomeGenerator {
		const list = try allocator.alloc(CaveBiomeGenerator, generatorRegistry.size);
		var iterator = generatorRegistry.iterator();
		var i: usize = 0;
		while(iterator.next()) |generator| {
			list[i] = generator.value_ptr.*;
			list[i].init(settings.getChild(generator.key_ptr.*));
			i += 1;
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: CaveBiomeGenerator, rhs: CaveBiomeGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.sort(CaveBiomeGenerator, list, {}, lessThan);
		return list;
	}
};

/// Doesn't allow getting the biome at one point and instead is only useful for interpolating values between biomes.
pub const InterpolatableCaveBiomeMapView = struct {
	fragments: [8]*CaveBiomeMapFragment,
	surfaceFragments: [4]*MapFragment,
	pos: ChunkPosition,
	width: i32,

	pub fn init(pos: ChunkPosition, width: i32) !InterpolatableCaveBiomeMapView {
		return InterpolatableCaveBiomeMapView {
			.fragments = [_]*CaveBiomeMapFragment {
				try getOrGenerateFragment(pos.wx - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz - CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz + CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz - CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz + CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz - CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy - CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz + CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz - CaveBiomeMapFragment.caveBiomeMapSize/2),
				try getOrGenerateFragment(pos.wx + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy + CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz + CaveBiomeMapFragment.caveBiomeMapSize/2),
			},
			.surfaceFragments = [_]*MapFragment {
				try SurfaceMap.getOrGenerateFragment(pos.wx - 32, pos.wz - 32, pos.voxelSize),
				try SurfaceMap.getOrGenerateFragment(pos.wx - 32, pos.wz + width + 32, pos.voxelSize),
				try SurfaceMap.getOrGenerateFragment(pos.wx + width + 32, pos.wz - 32, pos.voxelSize),
				try SurfaceMap.getOrGenerateFragment(pos.wx + width + 32, pos.wz + width + 32, pos.voxelSize),
			},
			.pos = pos,
			.width = width,
		};
	}

	pub fn deinit(self: InterpolatableCaveBiomeMapView) void {
		for(self.fragments) |mapFragment| {
			mapFragmentDeinit(mapFragment);
		}
		for(self.surfaceFragments) |mapFragment| {
			mapFragment.deinit();
		}
	}

	pub noinline fn interpolateValue(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32) f32 {
		// find the closest gridpoint:
		const gridPointX = wx & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		const gridPointY = wy & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		const gridPointZ = wz & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		const interpX = 1 - @intToFloat(f32, wx - gridPointX)/CaveBiomeMapFragment.caveBiomeSize;
		const interpY = 1 - @intToFloat(f32, wy - gridPointY)/CaveBiomeMapFragment.caveBiomeSize;
		const interpZ = 1 - @intToFloat(f32, wz - gridPointZ)/CaveBiomeMapFragment.caveBiomeSize;
		var val: f32 = 0;
		// Doing cubic interpolation.
		// Theoretically there is a way to interpolate on my weird bcc grid, which could be done with the 4 nearest grid points, but I can't figure out how to select the correct ones.
		// TODO: Figure out the better interpolation.
		comptime var dx: u8 = 0;
		inline while(dx <= 1) : (dx += 1) {
			comptime var dy: u8 = 0;
			inline while(dy <= 1) : (dy += 1) {
				comptime var dz: u8 = 0;
				inline while(dz <= 1) : (dz += 1) {
					const biome = self._getBiome(
						gridPointX + dx*CaveBiomeMapFragment.caveBiomeSize,
						gridPointY + dy*CaveBiomeMapFragment.caveBiomeSize,
						gridPointZ + dz*CaveBiomeMapFragment.caveBiomeSize,
					);
					val += biome.caves*@fabs(interpX - @intToFloat(f32, dx))*@fabs(interpY - @intToFloat(f32, dy))*@fabs(interpZ - @intToFloat(f32, dz));
				}
			}
		}
		return val;
	}

	fn checkSurfaceBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32) ?*const Biome {
		var index: u8 = 0;
		if(wx - self.surfaceFragments[0].pos.wx >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 2;
		}
		if(wz - self.surfaceFragments[0].pos.wz >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 1;
		}
		const height = @floatToInt(i32, self.surfaceFragments[index].getHeight(wx, wz));
		if(wy < height - 32 or wy > height + 128) return null;
		return self.surfaceFragments[index].getBiome(wx, wz);
	}

	fn _getBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32) *const Biome {
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 4;
		}
		if(wy - self.fragments[0].pos.wy >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 2;
		}
		if(wz - self.fragments[0].pos.wz >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 1;
		}
		const relX = @intCast(u31, wx - self.fragments[index].pos.wx);
		const relY = @intCast(u31, wy - self.fragments[index].pos.wy);
		const relZ = @intCast(u31, wz - self.fragments[index].pos.wz);
		const indexInArray = CaveBiomeMapFragment.getIndex(relX, relY, relZ);
		return self.fragments[index].biomeMap[indexInArray];
	}

	/// Useful when the rough biome location is enough, for example for music.
	pub fn getRoughBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, nullSeed: ?*u64, _checkSurfaceBiome: bool) *const Biome {
		if(_checkSurfaceBiome) {
			if(self.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
				return surfaceBiome;
			}
		}
		var gridPointX = wx & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		var gridPointY = wy & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		var gridPointZ = wz & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		const distanceX = wx - gridPointX;
		const distanceY = wy - gridPointY;
		const distanceZ = wz - gridPointZ;
		const totalDistance = (std.math.absInt(distanceX) catch unreachable) + (std.math.absInt(distanceY) catch unreachable) + (std.math.absInt(distanceZ) catch unreachable);
		if(totalDistance > CaveBiomeMapFragment.caveBiomeSize*3/4) {
			// Or with 1 to prevent errors if the value is 0.
			gridPointX += std.math.sign(distanceX | 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			gridPointY += std.math.sign(distanceY | 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			gridPointZ += std.math.sign(distanceZ | 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			// Go to a random gridpoint:
			var seed = main.random.initSeed3D(main.server.world.?.seed, .{gridPointX, gridPointY, gridPointZ});
			if(main.random.nextInt(u1, &seed) != 0) {
				gridPointX += CaveBiomeMapFragment.caveBiomeSize/2;
			}
			if(main.random.nextInt(u1, &seed) != 0) {
				gridPointY += CaveBiomeMapFragment.caveBiomeSize/2;
			}
			if(main.random.nextInt(u1, &seed) != 0) {
				gridPointZ += CaveBiomeMapFragment.caveBiomeSize/2;
			}
		}

		if(nullSeed) |seed| {
			// A good old "I don't know what I'm doing" hash:
			seed.* = @bitCast(u64, @as(i64, gridPointX) << 48 ^ @as(i64, gridPointY) << 23 ^ @as(i64, gridPointZ) << 11 ^ @as(i64, gridPointX) >> 5 ^ @as(i64, gridPointY) << 3 ^ @as(i64, gridPointZ)) ^ main.server.world.?.seed;
		}

		return self._getBiome(gridPointX, gridPointY, gridPointZ);
	}
};

pub const CaveBiomeMapView = struct {
	const Cached3DFractalNoise = terrain.noise.Cached3DFractalNoise;

	super: InterpolatableCaveBiomeMapView,
	noiseX: ?Cached3DFractalNoise = null,
	noiseY: ?Cached3DFractalNoise = null,
	noiseZ: ?Cached3DFractalNoise = null,

	pub fn init(chunk: *Chunk) !CaveBiomeMapView {
		var self = CaveBiomeMapView {
			.super = try InterpolatableCaveBiomeMapView.init(chunk.pos, chunk.width),
		};
		if(chunk.pos.voxelSize < 8) {
			// TODO: Reduce line length.
			self.noiseX = try Cached3DFractalNoise.init((chunk.pos.wx - 32) & ~@as(i32, 63), (chunk.pos.wy - 32) & ~@as(i32, 63), (chunk.pos.wz - 32) & ~@as(i32, 63), chunk.pos.voxelSize*4, chunk.width + 128, main.server.world.?.seed ^ 0x764923684396, 64);
			self.noiseY = try Cached3DFractalNoise.init((chunk.pos.wx - 32) & ~@as(i32, 63), (chunk.pos.wy - 32) & ~@as(i32, 63), (chunk.pos.wz - 32) & ~@as(i32, 63), chunk.pos.voxelSize*4, chunk.width + 128, main.server.world.?.seed ^ 0x6547835649265429, 64);
			self.noiseZ = try Cached3DFractalNoise.init((chunk.pos.wx - 32) & ~@as(i32, 63), (chunk.pos.wy - 32) & ~@as(i32, 63), (chunk.pos.wz - 32) & ~@as(i32, 63), chunk.pos.voxelSize*4, chunk.width + 128, main.server.world.?.seed ^ 0x56789365396783, 64);
		}
		return self;
	}

	pub fn deinit(self: CaveBiomeMapView) void {
		self.super.deinit();
		if(self.noiseX) |noiseX| {
			noiseX.deinit();
		}
		if(self.noiseY) |noiseY| {
			noiseY.deinit();
		}
		if(self.noiseZ) |noiseZ| {
			noiseZ.deinit();
		}
	}

	pub fn getSurfaceHeight(self: CaveBiomeMapView, wx: i32, wz: i32) f32 {
		var index: u8 = 0;
		if(wx - self.super.surfaceFragments[0].pos.wx >= MapFragment.mapSize*self.super.pos.voxelSize) {
			index += 2;
		}
		if(wz - self.super.surfaceFragments[0].pos.wz >= MapFragment.mapSize*self.super.pos.voxelSize) {
			index += 1;
		}
		return self.super.surfaceFragments[index].getHeight(wx, wz);
	}

	pub fn getBiome(self: CaveBiomeMapView, relX: i32, relY: i32, relZ: i32) *const Biome {
		return self.getBiomeAndSeed(relX, relY, relZ, null);
	}

	/// Also returns a seed that is unique for the corresponding biome position.
	pub fn getBiomeAndSeed(self: CaveBiomeMapView, relX: i32, relY: i32, relZ: i32, seed: ?*u64) *const Biome {
		std.debug.assert(relX >= -32 and relX < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relY >= -32 and relY < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relZ >= -32 and relZ < self.super.width + 32); // coordinate out of bounds
		var wx = relX + self.super.pos.wx;
		var wy = relY + self.super.pos.wy;
		var wz = relZ + self.super.pos.wz;
		if(self.super.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
			return surfaceBiome;
		}
		if(self.noiseX) |noiseX| if(self.noiseY) |noiseY| if(self.noiseZ) |noiseZ| {
			//                                                  ↓ intentionally cycled the noises to get different seeds.
			const valueX = noiseX.getValue(wx, wy, wz)*0.5 + noiseY.getRandomValue(wx, wy, wz)*8;
			const valueY = noiseY.getValue(wx, wy, wz)*0.5 + noiseZ.getRandomValue(wx, wy, wz)*8;
			const valueZ = noiseZ.getValue(wx, wy, wz)*0.5 + noiseX.getRandomValue(wx, wy, wz)*8;
			wx += @floatToInt(i32, valueX);
			wy += @floatToInt(i32, valueY);
			wz += @floatToInt(i32, valueZ);
		};

		return self.super.getRoughBiome(wx, wy, wz, seed, false);
	}
};

const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: Cache(CaveBiomeMapFragment, cacheSize, associativity, mapFragmentDeinit) = .{};

var profile: TerrainGenerationProfile = undefined;

pub fn initGenerators() !void {
	const list = @import("cavebiomegen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try CaveBiomeGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	CaveBiomeGenerator.generatorRegistry.clearAndFree(main.globalAllocator);
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

fn mapFragmentDeinit(mapFragment: *CaveBiomeMapFragment) void {
	if(@atomicRmw(u16, &mapFragment.refCount.value, .Sub, 1, .Monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: ChunkPosition) !*CaveBiomeMapFragment {
	const mapFragment = try main.globalAllocator.create(CaveBiomeMapFragment);
	try mapFragment.init(pos.wx, pos.wy, pos.wz);
	for(profile.caveBiomeGenerators) |generator| {
		try generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	_= @atomicRmw(u16, &mapFragment.refCount.value, .Add, 1, .Monotonic);
	return mapFragment;
}

fn getOrGenerateFragment(_wx: i32, _wy: i32, _wz: i32) !*CaveBiomeMapFragment {
	const wx = _wx & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wy = _wy & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wz = _wz & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const compare = ChunkPosition {
		.wx = wx, .wy = wy, .wz = wz,
		.voxelSize = CaveBiomeMapFragment.caveBiomeSize,
	};
	const result = try cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.value, .Add, 1, .Monotonic) != 0);
	return result;
}