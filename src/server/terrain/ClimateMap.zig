const std = @import("std");
const Atomic = std.atomic.Value;
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const Biome = terrain.biomes.Biome;
const MapFragment = terrain.SurfaceMap.MapFragment;

pub const BiomeSample = struct {
	biome: *const Biome,
	height: f32,
	roughness: f32,
	hills: f32,
	mountains: f32,
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
		return @bitCast((self.wx >> ClimateMapFragment.mapShift)*%33 +% (self.wz >> ClimateMapFragment.mapShift));
	}
};

pub const ClimateMapFragment = struct {
	pub const mapShift = 8 + MapFragment.biomeShift;
	pub const mapSize = 1 << mapShift;
	pub const mapMask: i32 = mapSize - 1;

	pos: ClimateMapFragmentPosition,
	map: [mapSize >> MapFragment.biomeShift][mapSize >> MapFragment.biomeShift]BiomeSample = undefined,
	
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
		return @bitCast((wx >> mapShift)*%33 + (wz >> mapShift));
	}
};

/// Generates the climate(aka Biome) map, which is a rough representation of the world.
pub const ClimateMapGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generateMapFragment: *const fn(fragment: *ClimateMapFragment, seed: u64) Allocator.Error!void,

	var generatorRegistry: std.StringHashMapUnmanaged(ClimateMapGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) !void {
		const self = ClimateMapGenerator {
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
	if(@atomicRmw(u16, &mapFragment.refCount.raw, .Sub, 1, .Monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: ClimateMapFragmentPosition) !*ClimateMapFragment {
	const mapFragment = try main.globalAllocator.create(ClimateMapFragment);
	mapFragment.init(pos.wx, pos.wz);
	try profile.climateGenerator.generateMapFragment(mapFragment, profile.seed);
	_ = @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .Monotonic);
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
	std.debug.assert(@atomicRmw(u16, &result.refCount.raw, .Add, 1, .Monotonic) != 0);
	return result;
}

pub fn getBiomeMap(allocator: Allocator, wx: i32, wz: i32, width: u31, height: u31) Allocator.Error!Array2D(BiomeSample) {
	const map = try Array2D(BiomeSample).init(allocator, width >> MapFragment.biomeShift, height >> MapFragment.biomeShift);
	const wxStart = wx & ~ClimateMapFragment.mapMask;
	const wzStart = wz & ~ClimateMapFragment.mapMask;
	const wxEnd = wx+width & ~ClimateMapFragment.mapMask;
	const wzEnd = wz+height & ~ClimateMapFragment.mapMask;
	var x = wxStart;
	while(x <= wxEnd) : (x += ClimateMapFragment.mapSize) {
		var z = wzStart;
		while(z <= wzEnd) : (z += ClimateMapFragment.mapSize) {
			const mapPiece = try getOrGenerateFragment(x, z);
			defer mapFragmentDeinit(mapPiece);
			// Offset of the indices in the result map:
			const xOffset = (x - wx) >> MapFragment.biomeShift;
			const zOffset = (z - wz) >> MapFragment.biomeShift;
			// Go through all indices in the mapPiece:
			for(&mapPiece.map, 0..) |*col, lx| {
				const resultX = @as(i32, @intCast(lx)) + xOffset;
				if(resultX < 0 or resultX >= width >> MapFragment.biomeShift) continue;
				for(col, 0..) |*spot, lz| {
					const resultZ = @as(i32, @intCast(lz)) + zOffset;
					if(resultZ < 0 or resultZ >= height >> MapFragment.biomeShift) continue;
					map.set(@intCast(resultX), @intCast(resultZ), spot.*);
				}
			}
		}
	}
	return map;
}