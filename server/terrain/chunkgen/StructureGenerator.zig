const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const noise = terrain.noise;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:vegetation";

pub const priority = 131072;

pub const generatorSeed = 0x2026b65487da9226;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generate(_: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	const structureMap = terrain.StructureMap.getOrGenerateFragment(chunk.super.pos.wx, chunk.super.pos.wy, chunk.super.pos.wz, chunk.super.pos.voxelSize);
	structureMap.generateStructuresInChunk(chunk, caveMap, biomeMap);
}
