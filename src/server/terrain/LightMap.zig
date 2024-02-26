const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;

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
	
	refCount: Atomic(u16) = Atomic(u16).init(0),

	pub fn init(self: *LightMapFragment, wx: i32, wy: i32, voxelSize: u31) void {
		self.* = .{
			.pos = MapFragmentPosition.init(wx, wy, voxelSize),
		};
	}

	pub fn decreaseRefCount(self: *LightMapFragment) void {
		if(@atomicRmw(u16, &self.refCount.raw, .Sub, 1, .Monotonic) == 1) {
			main.globalAllocator.destroy(self);
		}
	}

	pub fn getHeight(self: *LightMapFragment, wx: i32, wy: i32) i32 {
		const xIndex = wx>>self.pos.voxelSizeShift & mapMask;
		const yIndex = wy>>self.pos.voxelSizeShift & mapMask;
		return self.startHeight[@as(usize, @intCast(xIndex)) << mapShift | @as(usize, @intCast(yIndex))];
	}
};


const cacheSize = 1 << 6; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // ~100MiB MiB Cache size
var cache: Cache(LightMapFragment, cacheSize, associativity, LightMapFragment.decreaseRefCount) = .{};

fn cacheInit(pos: MapFragmentPosition) *LightMapFragment {
	const mapFragment = main.globalAllocator.create(LightMapFragment);
	mapFragment.init(pos.wx, pos.wy, pos.voxelSize);
	const surfaceMap = terrain.SurfaceMap.getOrGenerateFragment(pos.wx, pos.wy, pos.voxelSize);
	defer surfaceMap.deinit();
	comptime std.debug.assert(LightMapFragment.mapSize == terrain.SurfaceMap.MapFragment.mapSize);
	for(0..LightMapFragment.mapSize) |x| {
		for(0..LightMapFragment.mapSize) |y| {
			const baseHeight: i16 = std.math.lossyCast(i16, surfaceMap.heightMap[x][y]);
			mapFragment.startHeight[x << LightMapFragment.mapShift | y] = @max(0, baseHeight +| 16); // Simple heuristic. TODO: Update this value once chunks get generated in the region.
		}
	}
	_ = @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .Monotonic);
	return mapFragment;
}

pub fn deinit() void {
	cache.clear();
}

/// Call decreaseRefCount on the result.
pub fn getOrGenerateFragment(wx: i32, wy: i32, voxelSize: u31) *LightMapFragment {
	const compare = MapFragmentPosition.init(
		wx & ~@as(i32, LightMapFragment.mapMask*voxelSize | voxelSize-1),
		wy & ~@as(i32, LightMapFragment.mapMask*voxelSize | voxelSize-1),
		voxelSize
	);
	const result = cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.raw, .Add, 1, .Monotonic) != 0);
	return result;
}