const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const RandomList = main.utils.RandomList;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:simple_vegetation";

const SimpleVegetation = @This();

blockType: u16,
height0: u31,
deltaHeight: u31,

pub fn loadModel(arenaAllocator: Allocator, parameters: JsonElement) Allocator.Error!*SimpleVegetation {
	const self = try arenaAllocator.create(SimpleVegetation);
	self.* = .{
		.blockType = main.blocks.getByID(parameters.get([]const u8, "block", "")),
		.height0 = parameters.get(u31, "height", 1),
		.deltaHeight = parameters.get(u31, "height_variation", 0),
	};
	return self;
}

pub fn generate(self: *SimpleVegetation, x: i32, y: i32, z: i32, chunk: *main.chunk.Chunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) Allocator.Error!void {
	if(chunk.pos.voxelSize > 2 and (x & chunk.pos.voxelSize-1 != 0 or z & chunk.pos.voxelSize-1 != 0)) return;
	if(chunk.liesInChunk(x, y, z)) {
		const height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight+1);
		if(y + height >= caveMap.findTerrainChangeAbove(x, z, y)) return; // Space is too small.
		var py: i32 = chunk.startIndex(y);
		while(py < y + height) : (py += chunk.pos.voxelSize) {
			if(chunk.liesInChunk(x, py, z)) {
				chunk.updateBlockIfDegradable(x, py, z, .{.typ = self.blockType, .data = 0}); // TODO: Natural standard.
			}
		}
	}
}