const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
pub const MapFragmentPosition = terrain.SurfaceMap.MapFragmentPosition;
const Biome = terrain.biomes.Biome;

/// Generates and stores the light start position for each block column.
pub const LightMapFragment = struct {
	pub const mapShift = 8;
	pub const mapSize = 1 << mapShift;
	pub const mapMask = mapSize - 1;

	startHeight: [mapSize*mapSize]i16 = undefined,
	pos: MapFragmentPosition,

	pub fn init(self: *LightMapFragment, wx: i32, wy: i32, voxelSize: u31) void {
		self.* = .{
			.pos = MapFragmentPosition.init(wx, wy, voxelSize),
		};
	}

	fn privateDeinit(self: *const LightMapFragment) void {
		main.globalAllocator.destroy(self);
	}

	pub fn deferredDeinit(self: *LightMapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	pub fn getHeight(self: *LightMapFragment, wx: i32, wy: i32) i32 {
		const xIndex = wx >> self.pos.voxelSizeShift & mapMask;
		const yIndex = wy >> self.pos.voxelSizeShift & mapMask;
		return self.startHeight[@as(usize, @intCast(xIndex)) << mapShift | @as(usize, @intCast(yIndex))];
	}
};

const cacheSize = 1 << 6; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // 64MiB MiB Cache size
var cache: Cache(LightMapFragment, cacheSize, associativity, LightMapFragment.deferredDeinit) = .{};

fn cacheInit(pos: MapFragmentPosition) *LightMapFragment {
	const mapFragment = main.globalAllocator.create(LightMapFragment);
	mapFragment.init(pos.wx, pos.wy, pos.voxelSize);
	const surfaceMap = terrain.SurfaceMap.getOrGenerateFragment(pos.wx, pos.wy, pos.voxelSize);
	comptime std.debug.assert(LightMapFragment.mapSize == terrain.SurfaceMap.MapFragment.mapSize);
	for(0..LightMapFragment.mapSize) |x| {
		for(0..LightMapFragment.mapSize) |y| {
			const baseHeight: i16 = std.math.lossyCast(i16, surfaceMap.heightMap[x][y]);
			mapFragment.startHeight[x << LightMapFragment.mapShift | y] = @max(0, baseHeight +| 16); // Simple heuristic. TODO: Update this value once chunks get generated in the region.
		}
	}
	return mapFragment;
}

pub fn deinit() void {
	cache.clear();
}

pub fn getOrGenerateFragment(wx: i32, wy: i32, voxelSize: u31) *LightMapFragment {
	const compare = MapFragmentPosition.init(
		wx & ~@as(i32, LightMapFragment.mapMask*voxelSize | voxelSize - 1),
		wy & ~@as(i32, LightMapFragment.mapMask*voxelSize | voxelSize - 1),
		voxelSize,
	);
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}
