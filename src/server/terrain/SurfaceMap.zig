const std = @import("std");
const Atomic = std.atomic.Value;
const Allocator = std.mem.Allocator;

const main = @import("root");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;
const Vec3d = main.vec.Vec3d;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const Biome = terrain.biomes.Biome;

pub const MapFragmentPosition = struct {
	wx: i32,
	wz: i32,
	voxelSize: u31,
	voxelSizeShift: u5,

	pub fn init(wx: i32, wz: i32, voxelSize: u31) MapFragmentPosition {
		std.debug.assert(voxelSize-1 & voxelSize == 0); // voxelSize must be a power of 2.
		std.debug.assert(wx & voxelSize-1 == 0 and wz & voxelSize-1 == 0); // The coordinates are misaligned. They need to be aligned to the voxelSize grid.
		return MapFragmentPosition {
			.wx = wx,
			.wz = wz,
			.voxelSize = voxelSize,
			.voxelSizeShift = @ctz(voxelSize),
		};
	}

	pub fn equals(self: MapFragmentPosition, other: anytype) bool {
		if(other) |ch| {
			return self.wx == ch.pos.wx and self.wz == ch.pos.wz and self.voxelSize == ch.pos.voxelSize;
		}
		return false;
	}

	pub fn hashCode(self: MapFragmentPosition) u32 {
		return @bitCast((self.wx >> (MapFragment.mapShift + self.voxelSizeShift))*%33 +% (self.wz >> (MapFragment.mapShift + self.voxelSizeShift)) ^ self.voxelSize);
	}

	pub fn getMinDistanceSquared(self: MapFragmentPosition, playerPosition: Vec3d, comptime width: comptime_int) f64 {
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(width, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - playerPosition[0]);
		var dz = @abs(@as(f64, @floatFromInt(self.wz)) + halfWidth - playerPosition[2]);
		dx = @max(0, dx - halfWidth);
		dz = @max(0, dz - halfWidth);
		return dx*dx + dz*dz;
	}

	pub fn getPriority(self: MapFragmentPosition, playerPos: Vec3d, comptime width: comptime_int) f32 {
		return -@as(f32, @floatCast(self.getMinDistanceSquared(playerPos, width)))/@as(f32, @floatFromInt(self.voxelSize*self.voxelSize)) + 2*@as(f32, @floatFromInt(std.math.log2_int(u31, self.voxelSize)))*width*width;
	}
};

/// Generates and stores the height and Biome maps of the planet.
pub const MapFragment = struct {
	pub const biomeShift = 5;
	/// The average diameter of a biome.
	pub const biomeSize = 1 << biomeShift;
	pub const mapShift = 8;
	pub const mapSize = 1 << mapShift;
	pub const mapMask = mapSize - 1;

	heightMap: [mapSize][mapSize]f32 = undefined,
	biomeMap: [mapSize][mapSize]*const Biome = undefined,
	minHeight: f32 = std.math.floatMax(f32),
	maxHeight: f32 = 0,
	pos: MapFragmentPosition,
	
	refCount: Atomic(u16) = Atomic(u16).init(0),

	pub fn init(self: *MapFragment, wx: i32, wz: i32, voxelSize: u31) void {
		self.* = .{
			.pos = MapFragmentPosition.init(wx, wz, voxelSize),
		};
	}

	pub fn deinit(self: *MapFragment) void {
		mapFragmentDeinit(self);
	}

	pub fn getBiome(self: *MapFragment, wx: i32, wz: i32) *const Biome {
		const xIndex = wx>>self.pos.voxelSizeShift & mapMask;
		const zIndex = wz>>self.pos.voxelSizeShift & mapMask;
		return self.biomeMap[@intCast(xIndex)][@intCast(zIndex)];
	}

	pub fn getHeight(self: *MapFragment, wx: i32, wz: i32) f32 {
		const xIndex = wx>>self.pos.voxelSizeShift & mapMask;
		const zIndex = wz>>self.pos.voxelSizeShift & mapMask;
		return self.heightMap[@intCast(xIndex)][@intCast(zIndex)];
	}
};

/// Generates the detailed(block-level precision) height and biome maps from the climate map.
pub const MapGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generateMapFragment: *const fn(fragment: *MapFragment, seed: u64) Allocator.Error!void,

	var generatorRegistry: std.StringHashMapUnmanaged(MapGenerator) = .{};

	fn registerGenerator(comptime Generator: type) !void {
		const self = MapGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generateMapFragment = &Generator.generateMapFragment,
		};
		try generatorRegistry.put(main.globalAllocator, Generator.id, self);
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
var cache: Cache(MapFragment, cacheSize, associativity, mapFragmentDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

pub fn initGenerators() !void {
	const list = @import("mapgen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try MapGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	MapGenerator.generatorRegistry.clearAndFree(main.globalAllocator);
}

fn mapFragmentDeinit(mapFragment: *MapFragment) void {
	if(@atomicRmw(u16, &mapFragment.refCount.raw, .Sub, 1, .Monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: MapFragmentPosition) !*MapFragment {
	const mapFragment = try main.globalAllocator.create(MapFragment);
	mapFragment.init(pos.wx, pos.wz, pos.voxelSize);
	try profile.mapFragmentGenerator.generateMapFragment(mapFragment, profile.seed);
	_ = @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .Monotonic);
	return mapFragment;
}

pub fn init(_profile: TerrainGenerationProfile) !void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

/// Call deinit on the result.
pub fn getOrGenerateFragment(wx: i32, wz: i32, voxelSize: u31) !*MapFragment {
	const compare = MapFragmentPosition.init(
		wx & ~@as(i32, MapFragment.mapMask*voxelSize | voxelSize-1),
		wz & ~@as(i32, MapFragment.mapMask*voxelSize | voxelSize-1),
		voxelSize
	);
	const result = try cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.raw, .Add, 1, .Monotonic) != 0);
	return result;
}