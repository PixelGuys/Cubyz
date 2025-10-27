const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const Array2D = main.utils.Array2D;
const Cache = main.utils.Cache;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const Biome = terrain.biomes.Biome;
const MapFragment = terrain.SurfaceMap.MapFragment;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const BiomeSample = struct {
	biome: *const Biome,
	height: f32,
	roughness: f32,
	hills: f32,
	mountains: f32,
	seed: u64,
};

const ClimateMapFragmentPosition = struct {
	wx: i32,
	wy: i32,

	pub fn equals(self: ClimateMapFragmentPosition, other: anytype) bool {
		if(@TypeOf(other) == ?*ClimateMapFragment) {
			if(other) |ch| {
				return self.wx == ch.pos.wx and self.wy == ch.pos.wy;
			}
			return false;
		} else @compileError("Unsupported");
	}

	pub fn hashCode(self: ClimateMapFragmentPosition) u32 {
		return @bitCast((self.wx >> ClimateMapFragment.mapShift)*%33 +% (self.wy >> ClimateMapFragment.mapShift));
	}
};

pub const ClimateMapFragment = struct {
	pub const mapShift = 8 + MapFragment.biomeShift;
	pub const mapSize = 1 << mapShift;
	pub const mapMask: i32 = mapSize - 1;

	pub const mapEntrysSize = mapSize >> MapFragment.biomeShift;

	pos: ClimateMapFragmentPosition,
	map: [mapEntrysSize][mapEntrysSize]BiomeSample = undefined,

	pub fn init(self: *ClimateMapFragment, wx: i32, wy: i32) void {
		self.* = .{
			.pos = .{.wx = wx, .wy = wy},
		};
	}

	fn privateDeinit(self: *ClimateMapFragment) void {
		memoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *ClimateMapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	pub fn hashCode(wx: i32, wy: i32) u32 {
		return @bitCast((wx >> mapShift)*%33 + (wy >> mapShift));
	}
};

/// Generates the climate(aka Biome) map, which is a rough representation of the world.
pub const ClimateMapGenerator = struct {
	init: *const fn(parameters: ZonElement) void,
	generateMapFragment: *const fn(fragment: *ClimateMapFragment, seed: u64) void,

	var generatorRegistry: std.StringHashMapUnmanaged(ClimateMapGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = ClimateMapGenerator{
			.init = &Generator.init,
			.generateMapFragment = &Generator.generateMapFragment,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getGeneratorById(id: []const u8) !ClimateMapGenerator {
		return generatorRegistry.get(id) orelse {
			std.log.err("Couldn't find climate map generator with id {s}", .{id});
			return error.UnknownClimateMapGenerator;
		};
	}
};

const cacheSize = 1 << 5; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // ~400 MiB
var cache: Cache(ClimateMapFragment, cacheSize, associativity, ClimateMapFragment.deferredDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

var memoryPool: main.heap.MemoryPool(ClimateMapFragment) = undefined;

pub fn globalInit() void {
	const list = @import("climategen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		ClimateMapGenerator.registerGenerator(@field(list, decl.name));
	}
	memoryPool = .init(main.globalAllocator);
}

pub fn globalDeinit() void {
	ClimateMapGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
	memoryPool.deinit();
}

fn cacheInit(pos: ClimateMapFragmentPosition) *ClimateMapFragment {
	const mapFragment = memoryPool.create();
	mapFragment.init(pos.wx, pos.wy);
	profile.climateGenerator.generateMapFragment(mapFragment, profile.seed);
	return mapFragment;
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

pub fn getOrGenerateFragment(wx: i32, wy: i32) *ClimateMapFragment {
	const compare = ClimateMapFragmentPosition{.wx = wx, .wy = wy};
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}

pub fn getBiomeMap(allocator: NeverFailingAllocator, wx: i32, wy: i32, width: u31, height: u31) Array2D(BiomeSample) {
	const map = Array2D(BiomeSample).init(allocator, width >> MapFragment.biomeShift, height >> MapFragment.biomeShift);
	const wxStart = wx & ~ClimateMapFragment.mapMask;
	const wzStart = wy & ~ClimateMapFragment.mapMask;
	const wxEnd = wx +% width & ~ClimateMapFragment.mapMask;
	const wzEnd = wy +% height & ~ClimateMapFragment.mapMask;
	var x = wxStart;
	while(wxEnd -% x >= 0) : (x +%= ClimateMapFragment.mapSize) {
		var y = wzStart;
		while(wzEnd -% y >= 0) : (y +%= ClimateMapFragment.mapSize) {
			const mapPiece = getOrGenerateFragment(x, y);
			// Offset of the indices in the result map:
			const xOffset = (x -% wx) >> MapFragment.biomeShift;
			const yOffset = (y -% wy) >> MapFragment.biomeShift;
			// Go through all indices in the mapPiece:
			for(&mapPiece.map, 0..) |*col, lx| {
				const resultX = @as(i32, @intCast(lx)) + xOffset;
				if(resultX < 0 or resultX >= width >> MapFragment.biomeShift) continue;
				for(col, 0..) |*spot, ly| {
					const resultY = @as(i32, @intCast(ly)) + yOffset;
					if(resultY < 0 or resultY >= height >> MapFragment.biomeShift) continue;
					map.set(@intCast(resultX), @intCast(resultY), spot.*);
				}
			}
		}
	}
	return map;
}
