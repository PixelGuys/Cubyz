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

pub const id = "cubyz:fallen_tree";

pub const generationMode = .floor;

const FallenTree = @This();

woodBlock: u16,
topWoodBlock: u16,
height0: u32,
deltaHeight: u31,

pub fn loadModel(parameters: ZonElement) *FallenTree {
	const self = main.worldArena.create(FallenTree);
	self.* = .{
		.woodBlock = main.blocks.getTypeById(parameters.get([]const u8, "log", "cubyz:oak_log")),
		.topWoodBlock = main.blocks.getTypeById(parameters.get([]const u8, "top", "cubyz:oak_top")),
		.height0 = parameters.get(u32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
	};
	return self;
}

pub fn generateStump(self: *FallenTree, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk) void {
	if(chunk.liesInChunk(x, y, z))
		chunk.updateBlockIfDegradable(x, y, z, .{.typ = self.woodBlock, .data = 0});
}

pub fn generateFallen(self: *FallenTree, x: i32, y: i32, z: i32, length: u32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, seed: *u64) void {
	var d: ?u32 = null;

	const sh = caveMap.getHeightData(x, y);

	for(0..4) |_| {
		const dir: u32 = main.random.nextIntBounded(u32, seed, 4);

		var dx: i32 = 0;
		var dy: i32 = 0;

		if(dir == 0) {
			dx = 1;
		} else if(dir == 1) {
			dx = -1;
		} else if(dir == 2) {
			dy = 1;
		} else if(dir == 3) {
			dy = -1;
		}

		var works = true;
		for(0..length) |j| {
			const v: i32 = @intCast(j);
			if(caveMap.getHeightData(x + dx*(v + 2), y + dy*(v + 2)) != sh) {
				works = false;
				break;
			}
		}

		if(works) {
			d = dir;
			break;
		}
	}

	if(d == null)
		return;

	var dx: i32 = 0;
	var dy: i32 = 0;

	if(d.? == 0) {
		dx = 1;
	} else if(d.? == 1) {
		dx = -1;
	} else if(d.? == 2) {
		dy = 1;
	} else if(d.? == 3) {
		dy = -1;
	}

	for(0..length) |val| {
		const v: i32 = @intCast(val);
		if(chunk.liesInChunk(x + dx*(v + 2), y + dy*(v + 2), z)) {
			const typ = if(v == (length - 1)) self.topWoodBlock else self.woodBlock;
			chunk.updateBlockIfDegradable(x + dx*(v + 2), y + dy*(v + 2), z, .{.typ = typ, .data = @intCast(d.? + 2)});
		}
	}
}

pub fn generate(self: *FallenTree, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight);

	generateStump(self, x, y, z, chunk);

	generateFallen(self, x, y, z, height - 2, chunk, caveMap, seed);
}
