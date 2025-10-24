const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.biomes.SimpleStructureModel.GenerationMode;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const id = "cubyz:simple_vegetation";

pub const generationMode = .floor;

const SimpleVegetation = @This();

block: main.blocks.Block,
height0: u31,
deltaHeight: u31,

pub fn loadModel(parameters: ZonElement) *SimpleVegetation {
	const self = main.worldArena.create(SimpleVegetation);
	self.* = .{
		.block = main.blocks.parseBlock(parameters.get([]const u8, "block", "")),
		.height0 = parameters.get(u31, "height", 1),
		.deltaHeight = parameters.get(u31, "height_variation", 0),
	};
	return self;
}

pub fn generate(self: *SimpleVegetation, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, _: CaveBiomeMapView, seed: *u64, isCeiling: bool) void {
	if(chunk.super.pos.voxelSize > 2 and (x & chunk.super.pos.voxelSize - 1 != 0 or y & chunk.super.pos.voxelSize - 1 != 0)) return;
	const height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight + 1);
	if(z + height >= caveMap.findTerrainChangeAbove(x, y, z)) return; // Space is too small.
	var pz: i32 = chunk.startIndex(z);
	if(isCeiling) {
		while(pz >= z - height) : (pz -= chunk.super.pos.voxelSize) {
			if(chunk.liesInChunk(x, y, pz)) {
				chunk.updateBlockIfDegradable(x, y, pz, self.block);
			}
		}
	} else {
		while(pz < z + height) : (pz += chunk.super.pos.voxelSize) {
			if(chunk.liesInChunk(x, y, pz)) {
				chunk.updateBlockIfDegradable(x, y, pz, self.block);
			}
		}
	}
}
