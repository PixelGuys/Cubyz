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

pub const id = "cubyz:simple_tree";

const SimpleTreeModel = @This();

const Type = enum {
	pyramid,
	round,
	bush,
};

typ: Type,
leavesBlock: u16,
woodBlock: u16,
topWoodBlock: u16,
height0: i32,
deltaHeight: u31,

pub fn loadModel(arenaAllocator: Allocator, parameters: JsonElement) Allocator.Error!*SimpleTreeModel {
	const self = try arenaAllocator.create(SimpleTreeModel);
	self.* = .{
		.typ = std.meta.stringToEnum(Type, parameters.get([]const u8, "type", "")) orelse .round,
		.leavesBlock = main.blocks.getByID(parameters.get([]const u8, "leaves", "cubyz:oak_leaves")),
		.woodBlock = main.blocks.getByID(parameters.get([]const u8, "log", "cubyz:oak_log")),
		.topWoodBlock = main.blocks.getByID(parameters.get([]const u8, "top", "cubyz:oak_top")),
		.height0 = parameters.get(i32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
	};
	return self;
}

pub fn generateStem(self: *SimpleTreeModel, x: i32, y: i32, z: i32, height: i32, chunk: *main.chunk.Chunk) void {
	if(chunk.pos.voxelSize <= 2) {
		var py: i32 = chunk.startIndex(y);
		while(py < y + height) : (py += chunk.pos.voxelSize) {
			if(chunk.liesInChunk(x, py, z)) {
				chunk.updateBlockIfDegradable(x, py, z, if(py == y + height-1) .{.typ = self.topWoodBlock, .data = 0} else .{.typ = self.woodBlock, .data = 0}); // TODO: Natural standard.
			}
		}
	}
}

pub fn generate(self: *SimpleTreeModel, x: i32, y: i32, z: i32, chunk: *main.chunk.Chunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) Allocator.Error!void {
	var height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight);

	if(y + height >= caveMap.findTerrainChangeAbove(x, z, y)) // Space is too small.Allocator
		return;

	if(y > chunk.width) return;
	
	if(chunk.pos.voxelSize >= 16) {
		// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
		if(chunk.liesInChunk(x, y, z)) {
			chunk.updateBlockIfDegradable(x, y, z, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard
		}
		if(chunk.liesInChunk(x, y + chunk.pos.voxelSize, z)) {
			chunk.updateBlockIfDegradable(x, y + chunk.pos.voxelSize, z, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard
		}
	}

	switch(self.typ) {
		.pyramid => {
			self.generateStem(x, y, z, height, chunk);
			// Position of the first block of leaves
			height = 3*height >> 1;
			var py = chunk.startIndex(y + @divTrunc(height, 3));
			while(py < y + height) : (py += chunk.pos.voxelSize) {
				const j = @divFloor(height - (py - y), 2);
				var px = chunk.startIndex(x + 1 - j);
				while(px < x + j) : (px += chunk.pos.voxelSize) {
					var pz = chunk.startIndex(z + 1 - j);
					while(pz < z + j) : (pz += chunk.pos.voxelSize) {
						if(chunk.liesInChunk(px, py, pz))
							chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
					}
				}
			}
		},
		.round => {
			self.generateStem(x, y, z, height, chunk);

			const leafRadius = 1 + @divFloor(height, 2);
			const floatLeafRadius = @as(f32, @floatFromInt(leafRadius)) - random.nextFloat(seed);
			const radiusSqr: i32 = @intFromFloat(floatLeafRadius*floatLeafRadius);
			const randomRadiusSqr: i32 = @intFromFloat((floatLeafRadius - 0.25)*(floatLeafRadius - 0.25));
			const center = y + height;
			var py = chunk.startIndex(center - leafRadius);
			while(py < center + leafRadius) : (py += chunk.pos.voxelSize) {
				var px = chunk.startIndex(x - leafRadius);
				while(px < x + leafRadius) : (px += chunk.pos.voxelSize) {
					var pz = chunk.startIndex(z - leafRadius);
					while(pz < z + leafRadius) : (pz += chunk.pos.voxelSize) {
						const distSqr = (py - center)*(py - center) + (px - x)*(px - x) + (pz - z)*(pz - z);
						if(chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
						}
					}
				}
			}
		},
		.bush => {
			const oldHeight = height;
			height = @min(2, height); // Make sure the stem of the bush stays small.

			self.generateStem(x, y, z, height, chunk);

			const leafRadius = 1 + @divFloor(oldHeight, 2);
			const floatLeafRadius = @as(f32, @floatFromInt(leafRadius)) - random.nextFloat(seed);
			const radiusSqr: i32 = @intFromFloat(floatLeafRadius*floatLeafRadius);
			const randomRadiusSqr: i32 = @intFromFloat((floatLeafRadius - 0.25)*(floatLeafRadius - 0.25));
			const center = y + height;
			var py = chunk.startIndex(center - leafRadius);
			while(py < center + leafRadius) : (py += chunk.pos.voxelSize) {
				var px = chunk.startIndex(x - leafRadius);
				while(px < x + leafRadius) : (px += chunk.pos.voxelSize) {
					var pz = chunk.startIndex(z - leafRadius);
					while(pz < z + leafRadius) : (pz += chunk.pos.voxelSize) {
						const distSqr = (py - center)*(py - center) + (px - x)*(px - x) + (pz - z)*(pz - z);
						if(chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
						}
					}
				}
			}
		}
	}
}