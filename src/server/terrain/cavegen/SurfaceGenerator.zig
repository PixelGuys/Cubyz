const std = @import("std");
const Allocator = std.mem.Allocator;
const sign = std.math.sign;

const main = @import("root");
const Array2D = main.utils.Array2D;
const RandomList = main.utils.RandomList;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const FractalNoise = terrain.noise.FractalNoise;
const RandomlyWeightedFractalNoise = terrain.noise.RandomlyWeightedFractalNoise;
const PerlinNoise = terrain.noise.PerlinNoise;
const Cached3DFractalNoise = terrain.noise.Cached3DFractalNoise;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:surface";

pub const priority = 1024;

pub const generatorSeed = 0x7658930674389;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) Allocator.Error!void {
	_ = worldSeed;
	var x0: u31 = 0;
	while(x0 < CaveMapFragment.width*map.pos.voxelSize) : (x0 += MapFragment.mapSize*map.pos.voxelSize) {
		var z0: u31 = 0;
		while(z0 < CaveMapFragment.width*map.pos.voxelSize) : (z0 += MapFragment.mapSize*map.pos.voxelSize) {
			if(x0 != 0 or z0 != 0) {
				std.log.err("TODO: Remove this print when it's printed. Otherwise remove the extra for loops. They are likely obsolete, but just to be sure it should be kept for a while.", .{});
			}
			const mapFragment = try SurfaceMap.getOrGenerateFragment(map.pos.wx + x0, map.pos.wz + z0, map.pos.voxelSize);
			defer mapFragment.deinit();
			var x: u31 = 0;
			while(x < @min(CaveMapFragment.width*map.pos.voxelSize, MapFragment.mapSize*map.pos.voxelSize)) : (x += map.pos.voxelSize) {
				var z: u31 = 0;
				while(z < @min(CaveMapFragment.width*map.pos.voxelSize, MapFragment.mapSize*map.pos.voxelSize)) : (z += map.pos.voxelSize) {
					map.addRange(x0 + x, z0 + z, 0, @as(i32, @intFromFloat(mapFragment.getHeight(map.pos.wx + x + x0, map.pos.wz + z + z0))) - map.pos.wy);
				}
			}
		}
	}
}
