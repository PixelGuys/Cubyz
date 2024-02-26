const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:terrain";

pub const priority = 1024; // Within Cubyz the first to be executed, but mods might want to come before that for whatever reason.

pub const generatorSeed = 0x65c7f9fdc0641f94;

var water: u16 = undefined;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
	water = main.blocks.getByID("cubyz:water");
}

pub fn deinit() void {

}

pub fn generate(worldSeed: u64, chunk: *main.chunk.Chunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	const voxelSizeShift = @ctz(chunk.pos.voxelSize);
	var x: u31 = 0;
	while(x < chunk.width) : (x += chunk.pos.voxelSize) {
		var y: u31 = 0;
		while(y < chunk.width) : (y += chunk.pos.voxelSize) {
			const heightData = caveMap.getHeightData(x, y);
			var makeSurfaceStructure = true;
			var z: i32 = chunk.width - chunk.pos.voxelSize;
			while(z >= 0) : (z -= chunk.pos.voxelSize) {
				const mask = @as(u64, 1) << @intCast(z >> voxelSizeShift);
				if(heightData & mask != 0) {
					const biome = biomeMap.getBiome(x, y, z);
					
					if(makeSurfaceStructure) {
						const surfaceBlock = caveMap.findTerrainChangeAbove(x, y, z) - chunk.pos.voxelSize;
						var seed: u64 = random.initSeed3D(worldSeed, .{chunk.pos.wx + x, chunk.pos.wy + y, chunk.pos.wz + z});
						// Add the biomes surface structure:
						z = @min(z + chunk.pos.voxelSize, biome.structure.addSubTerranian(chunk, surfaceBlock, caveMap.findTerrainChangeBelow(x, y, z), x, y, &seed));
						makeSurfaceStructure = false;
					} else {
						chunk.updateBlockInGeneration(x, y, z, .{.typ = biome.stoneBlockType, .data = 0}); // TODO: Natural standard.
					}
				} else {
					if(z + chunk.pos.wz < 0 and z + chunk.pos.wz >= @as(i32, @intFromFloat(biomeMap.getSurfaceHeight(x + chunk.pos.wx, y + chunk.pos.wy))) - (chunk.pos.voxelSize - 1)) {
						chunk.updateBlockInGeneration(x, y, z, .{.typ = water, .data = 0}); // TODO: Natural standard.
					} else {
						chunk.updateBlockInGeneration(x, y, z, .{.typ = 0, .data = 0});
					}
					makeSurfaceStructure = true;
				}
			}
		}
	}
}
