const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

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
branched: bool,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: JsonElement) *SimpleTreeModel {
	const self = arenaAllocator.create(SimpleTreeModel);
	self.* = .{
		.typ = std.meta.stringToEnum(Type, parameters.get([]const u8, "type", "")) orelse .round,
		.leavesBlock = main.blocks.getByID(parameters.get([]const u8, "leaves", "cubyz:oak_leaves")),
		.woodBlock = main.blocks.getByID(parameters.get([]const u8, "log", "cubyz:oak_log")),
		.topWoodBlock = main.blocks.getByID(parameters.get([]const u8, "top", "cubyz:oak_top")),
		.height0 = parameters.get(i32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
		.branched = parameters.get(bool, "branched", true),
	};
	return self;
}

pub fn generateStem(self: *SimpleTreeModel, x: i32, y: i32, z: i32, height: i32, chunk: *main.chunk.ServerChunk, seed: *u64) void {
	if(chunk.super.pos.voxelSize <= 2) {
		var pz: i32 = chunk.startIndex(z);
		while(pz < z + height) : (pz += chunk.super.pos.voxelSize) {
			if(chunk.liesInChunk(x, y, pz)) {
				chunk.updateBlockIfDegradable(x, y, pz, if(pz == z + height-1) .{.typ = self.topWoodBlock, .data = 0} else .{.typ = self.woodBlock, .data = 0}); // TODO: Natural standard.

				if (self.branched)
				{
					const chance = @sqrt(@as(f32, @floatFromInt(pz - z)) / @as(f32, @floatFromInt(height * 2)));
					if (main.random.nextFloat(seed) < chance) {
						const d = main.random.nextIntBounded(u32, seed, 4);
						generateBranch(self, x, y, pz, d, chunk, seed);
					}
				}
			}
		}
	}
}

pub fn generateBranch(self: *SimpleTreeModel, x: i32, y: i32, z: i32, d: u32, chunk: *main.chunk.ServerChunk, seed: *u64) void {
	_ = seed;

	if (d == 0 and chunk.liesInChunk(x + 1, y, z)) {
		chunk.updateBlockIfDegradable(x + 1, y, z, .{.typ = self.topWoodBlock, .data = 2});
	} else if (d == 1 and chunk.liesInChunk(x - 1, y, z)) {
		chunk.updateBlockIfDegradable(x - 1, y, z, .{.typ = self.topWoodBlock, .data = 3});
	} else if (d == 2 and chunk.liesInChunk(x, y + 1, z)) {
		chunk.updateBlockIfDegradable(x, y + 1, z, .{.typ = self.topWoodBlock, .data = 4});
	} else if (d == 3 and chunk.liesInChunk(x, y - 1, z)) {
		chunk.updateBlockIfDegradable(x, y - 1, z, .{.typ = self.topWoodBlock, .data = 5});
	}
}

pub fn generate(self: *SimpleTreeModel, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) void {
	var height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight);

	if(z + height >= caveMap.findTerrainChangeAbove(x, y, z)) // Space is too small.Allocator
		return;

	if(z > chunk.super.width) return;
	
	if(chunk.super.pos.voxelSize >= 16) {
		// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
		if(chunk.liesInChunk(x, y, z)) {
			chunk.updateBlockIfDegradable(x, y, z, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard
		}
		if(chunk.liesInChunk(x, y, z + chunk.super.pos.voxelSize)) {
			chunk.updateBlockIfDegradable(x, y, z + chunk.super.pos.voxelSize, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard
		}
	}

	switch(self.typ) {
		.pyramid => {
			self.generateStem(x, y, z, height, chunk, seed);
			// Position of the first block of leaves
			height = 3*height >> 1;
			var pz = chunk.startIndex(z + @divTrunc(height, 3));
			while(pz < z + height) : (pz += chunk.super.pos.voxelSize) {
				const j = @divFloor(height - (pz - z), 2);
				var px = chunk.startIndex(x + 1 - j);
				while(px < x + j) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y + 1 - j);
					while(py < y + j) : (py += chunk.super.pos.voxelSize) {
						if(chunk.liesInChunk(px, py, pz))
							if (chunk.getBlock(px, py, pz).typ == 0)
								chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
					}
				}
			}
		},
		.round => {
			self.generateStem(x, y, z, height, chunk, seed);

			const leafRadius = 1 + @divFloor(height, 2);
			const floatLeafRadius = @as(f32, @floatFromInt(leafRadius)) - random.nextFloat(seed);
			const radiusSqr: i32 = @intFromFloat(floatLeafRadius*floatLeafRadius);
			const randomRadiusSqr: i32 = @intFromFloat((floatLeafRadius - 0.25)*(floatLeafRadius - 0.25));
			const center = z + height;
			var pz = chunk.startIndex(center - leafRadius);
			while(pz < center + leafRadius) : (pz += chunk.super.pos.voxelSize) {
				var px = chunk.startIndex(x - leafRadius);
				while(px < x + leafRadius) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y - leafRadius);
					while(py < y + leafRadius) : (py += chunk.super.pos.voxelSize) {
						const distSqr = (pz - center)*(pz - center) + (px - x)*(px - x) + (py - y)*(py - y);
						if(chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							if (chunk.getBlock(px, py, pz).typ == 0)
								chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
						}
					}
				}
			}
		},
		.bush => {
			const oldHeight = height;
			height = @min(2, height); // Make sure the stem of the bush stays small.

			self.generateStem(x, y, z, height, chunk, seed);

			const leafRadius = 1 + @divFloor(oldHeight, 2);
			const floatLeafRadius = @as(f32, @floatFromInt(leafRadius)) - random.nextFloat(seed);
			const radiusSqr: i32 = @intFromFloat(floatLeafRadius*floatLeafRadius);
			const randomRadiusSqr: i32 = @intFromFloat((floatLeafRadius - 0.25)*(floatLeafRadius - 0.25));
			const center = z + height;
			var pz = chunk.startIndex(center - leafRadius);
			while(pz < center + leafRadius) : (pz += chunk.super.pos.voxelSize) {
				var px = chunk.startIndex(x - leafRadius);
				while(px < x + leafRadius) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y - leafRadius);
					while(py < y + leafRadius) : (py += chunk.super.pos.voxelSize) {
						const distSqr = (pz - center)*(pz - center) + (px - x)*(px - x) + (py - y)*(py - y);
						if(chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							if (chunk.getBlock(px, py, pz).typ == 0)
								chunk.updateBlockIfDegradable(px, py, pz, .{.typ = self.leavesBlock, .data = 0}); // TODO: Natural standard.
						}
					}
				}
			}
		}
	}
}