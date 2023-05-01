const std = @import("std");
const Atomic = std.atomic.Atomic;
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const Biome = terrain.biomes.Biome;
const MapFragment = terrain.SurfaceMap.MapFragment;

pub const BiomePoint = struct {
	biome: *const Biome,
	x: i32,
	z: i32,
	height: f32,
	seed: u64,

	pub fn distSquare(self: BiomePoint, x: f32, z: f32) f32 {
		const deltaX = @intToFloat(f32, self.x) - x;
		const deltaZ = @intToFloat(f32, self.z) - z;
		return deltaX*deltaX + deltaZ*deltaZ;
	}

	pub fn maxNorm(self: BiomePoint, x: f32, z: f32) f32 {
		const deltaX = @intToFloat(f32, self.x) - x;
		const deltaZ = @intToFloat(f32, self.z) - z;
		return @max(@fabs(deltaX), @fabs(deltaZ));
	}

	pub fn getFittingReplacement(self: BiomePoint, height: i32) *const Biome {
		// Check if the existing Biome fits and if not choose a fitting replacement:
		var biome = self.biome;
		if(height < biome.minHeight) {
			var seed: u64 = self.seed ^ 654295489239294;
			main.random.scrambleSeed(&seed);
			while(height < biome.minHeight) {
				if(biome.lowerReplacements.len == 0) break;
				biome = biome.lowerReplacements[main.random.nextIntBounded(u32, &seed, @intCast(u32, biome.lowerReplacements.len))];
			}
		} else if(height > biome.maxHeight) {
			var seed: u64 = self.seed ^ 56473865395165948;
			main.random.scrambleSeed(&seed);
			while(height > biome.maxHeight) {
				if(biome.upperReplacements.len == 0) break;
				biome = biome.upperReplacements[main.random.nextIntBounded(u32, &seed, @intCast(u32, biome.upperReplacements.len))];
			}
		}
		return biome;
	}
};

const ClimateMapFragmentPosition = struct {
	wx: i32,
	wz: i32,

	pub fn equals(self: ClimateMapFragmentPosition, other: anytype) bool {
		if(@TypeOf(other) == ?*ClimateMapFragment) {
			if(other) |ch| {
				return self.wx == ch.pos.wx and self.wz == ch.pos.wz;
			}
			return false;
		} else @compileError("Unsupported");
	}

	pub fn hashCode(self: ClimateMapFragmentPosition) u32 {
		return @bitCast(u32, (self.wx >> ClimateMapFragment.mapShift)*%33 +% (self.wz >> ClimateMapFragment.mapShift));
	}
};

pub const ClimateMapFragment = struct {
	pub const mapShift = 8 + MapFragment.biomeShift;
	pub const mapSize = 1 << mapShift;
	pub const mapMask: i32 = mapSize - 1;

	pos: ClimateMapFragmentPosition,
	map: [mapSize >> MapFragment.biomeShift][mapSize >> MapFragment.biomeShift]BiomePoint = undefined,
	
	refCount: Atomic(u16) = Atomic(u16).init(0),

	pub fn init(self: *ClimateMapFragment, wx: i32, wz: i32) void {
		self.* = .{
			.pos = .{.wx = wx, .wz = wz,},
		};
	}

	pub fn hashCodeSelf(self: *ClimateMapFragment) u32 {
		return hashCode(self.wx, self.wz);
	}

	pub fn hashCode(wx: i32, wz: i32) u32 {
		return @bitCast(u32, (wx >> mapShift)*%33 + (wz >> mapShift));
	}
};

/// Generates the climate(aka Biome) map, which is a rough representation of the world.
pub const ClimateMapGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generateMapFragment: *const fn(fragment: *ClimateMapFragment, seed: u64) Allocator.Error!void,

	var generatorRegistry: std.StringHashMapUnmanaged(ClimateMapGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) !void {
		var self = ClimateMapGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generateMapFragment = &Generator.generateMapFragment,
		};
		try generatorRegistry.put(main.globalAllocator, Generator.id, self);
	}

	pub fn getGeneratorById(id: []const u8) !ClimateMapGenerator {
		return generatorRegistry.get(id) orelse {
			std.log.err("Couldn't find climate map generator with id {s}", .{id});
			return error.UnknownClimateMapGenerator;
		};
	}
};


const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 4;
var cache: Cache(ClimateMapFragment, cacheSize, associativity, mapFragmentDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

pub fn initGenerators() !void {
	const list = @import("climategen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try ClimateMapGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	ClimateMapGenerator.generatorRegistry.clearAndFree(main.globalAllocator);
}

fn mapFragmentDeinit(mapFragment: *ClimateMapFragment) void {
	if(@atomicRmw(u16, &mapFragment.refCount.value, .Sub, 1, .Monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: ClimateMapFragmentPosition) !*ClimateMapFragment {
	const mapFragment = try main.globalAllocator.create(ClimateMapFragment);
	mapFragment.init(pos.wx, pos.wz);
	try profile.climateGenerator.generateMapFragment(mapFragment, profile.seed);
	_ = @atomicRmw(u16, &mapFragment.refCount.value, .Add, 1, .Monotonic);
	return mapFragment;
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

/// Call deinit on the result.
fn getOrGenerateFragment(wx: i32, wz: i32) Allocator.Error!*ClimateMapFragment {
	const compare = ClimateMapFragmentPosition{.wx = wx, .wz = wz};
	const result = try cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.value, .Add, 1, .Monotonic) != 0);
	return result;
}

pub fn getBiomeMap(allocator: Allocator, wx: i32, wz: i32, width: u31, height: u31) Allocator.Error!Array2D(BiomePoint) {
	const map = try Array2D(BiomePoint).init(allocator, width >> MapFragment.biomeShift, height >> MapFragment.biomeShift);
	const wxStart = wx & ~ClimateMapFragment.mapMask;
	const wzStart = wz & ~ClimateMapFragment.mapMask;
	const wxEnd = wx+width & ~ClimateMapFragment.mapMask;
	const wzEnd = wz+height & ~ClimateMapFragment.mapMask;
	var x = wxStart;
	while(x <= wxEnd) : (x += ClimateMapFragment.mapSize) {
		var z = wzStart;
		while(z <= wzEnd) : (z += ClimateMapFragment.mapSize) {
			const mapPiece = try getOrGenerateFragment(x, z);
			// Offset of the indices in the result map:
			const xOffset = (x - wx) >> MapFragment.biomeShift;
			const zOffset = (z - wz) >> MapFragment.biomeShift;
			// Go through all indices in the mapPiece:
			for(&mapPiece.map, 0..) |*col, lx| {
				const resultX = @intCast(i32, lx) + xOffset;
				if(resultX < 0 or resultX >= width >> MapFragment.biomeShift) continue;
				for(col, 0..) |*spot, lz| {
					const resultZ = @intCast(i32, lz) + zOffset;
					if(resultZ < 0 or resultZ >= height >> MapFragment.biomeShift) continue;
					map.set(@intCast(usize, resultX), @intCast(usize, resultZ), spot.*);
				}
			}
		}
	}
	return map;
}