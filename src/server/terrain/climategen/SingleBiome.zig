const std = @import("std");

const build_options = @import("build_options");

const main = @import("main");
const Array2D = main.utils.Array2D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const ClimateMapFragment = terrain.ClimateMap.ClimateMapFragment;
const BiomeSample = terrain.ClimateMap.BiomeSample;
const Biome = terrain.biomes.Biome;
const TreeNode = terrain.biomes.TreeNode;
const vec = main.vec;
const Vec2i = vec.Vec2i;
const Vec2f = vec.Vec2f;

const NeverFailingAllocator = main.heap.NeverFailingAllocator;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:single_biome";

var biome: *const Biome = undefined;

pub fn init(parameters: ZonElement) void {
	biome = terrain.biomes.getById(parameters.get([]const u8, "biome", "missing parameter 'biome'"));
}

pub fn generateMapFragment(map: *ClimateMapFragment, worldSeed: u64) void {
	var x: u31 = 0;
	while(x < map.map.len) : (x += 1) {
		var y: u31 = 0;
		while(y < map.map[0].len) : (y += 1) {
			const wx = map.pos.wx +% x*ClimateMapFragment.mapSize/ClimateMapFragment.mapEntrysSize;
			const wy = map.pos.wy +% y*ClimateMapFragment.mapSize/ClimateMapFragment.mapEntrysSize;
			const noiseValue = terrain.noise.ValueNoise.samplePoint2D(@as(f32, @floatFromInt(wx))/biome.radius/2, @as(f32, @floatFromInt(wy))/biome.radius/2, worldSeed);
			map.map[x][y] = .{
				.biome = biome,
				.height = @as(f32, @floatFromInt(biome.minHeight)) + @as(f32, @floatFromInt(biome.maxHeight - biome.minHeight))*noiseValue,
				.roughness = biome.roughness,
				.hills = biome.hills,
				.mountains = biome.mountains,
				.seed = worldSeed ^ 53298562891,
			};
		}
	}
}
