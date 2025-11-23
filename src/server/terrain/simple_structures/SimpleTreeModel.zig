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

pub const id = "cubyz:simple_tree";

const SimpleTreeModel = @This();

pub const generationMode = .floor;

const Type = enum {
	pyramid,
	round,
};

typ: Type,
leavesBlock: main.blocks.Block,
woodBlock: main.blocks.Block,
topWoodBlock: main.blocks.Block,
height0: i32,
deltaHeight: u31,
leafRadius: f32,
deltaLeafRadius: f32,
leafElongation: f32,
deltaLeafElongation: f32,
branched: bool,

pub fn loadModel(parameters: ZonElement) ?*SimpleTreeModel {
	const self = main.worldArena.create(SimpleTreeModel);
	self.* = .{
		.typ = std.meta.stringToEnum(Type, parameters.get([]const u8, "type", "")) orelse blk: {
			if(parameters.get(?[]const u8, "type", null)) |typ| std.log.err("Unknown tree type \"{s}\"", .{typ});
			break :blk .round;
		},
		.leavesBlock = main.blocks.parseBlock(parameters.get([]const u8, "leaves", "cubyz:leaves/oak")),
		.woodBlock = main.blocks.parseBlock(parameters.get([]const u8, "log", "cubyz:oak_log")),
		.topWoodBlock = main.blocks.parseBlock(parameters.get([]const u8, "top", "cubyz:oak_top")),
		.height0 = parameters.get(i32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
		.leafRadius = parameters.get(f32, "leafRadius", (1 + parameters.get(f32, "height", 6))/2),
		.deltaLeafRadius = parameters.get(f32, "leafRadius_variation", parameters.get(f32, "height_variation", 3)/2),
		.leafElongation = parameters.get(f32, "leafElongation", 1),
		.deltaLeafElongation = parameters.get(f32, "deltaLeafElongation", 0),
		.branched = parameters.get(bool, "branched", true),
	};
	return self;
}

pub fn generateStem(self: *SimpleTreeModel, x: i32, y: i32, z: i32, height: i32, chunk: *main.chunk.ServerChunk, seed: *u64) void {
	if(chunk.super.pos.voxelSize <= 2) {
		var pz: i32 = chunk.startIndex(z);
		while(pz < z + height) : (pz += chunk.super.pos.voxelSize) {
			if(chunk.liesInChunk(x, y, pz)) {
				chunk.updateBlockIfDegradable(x, y, pz, if(pz == z + height - 1) self.topWoodBlock else self.woodBlock);

				if(self.branched) {
					const chance = @sqrt(@as(f32, @floatFromInt(pz - z))/@as(f32, @floatFromInt(height*2)));
					if(main.random.nextFloat(seed) < chance) {
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

	if(d == 0 and chunk.liesInChunk(x + 1, y, z)) {
		chunk.updateBlockIfDegradable(x + 1, y, z, .{.typ = self.topWoodBlock.typ, .data = 2});
	} else if(d == 1 and chunk.liesInChunk(x - 1, y, z)) {
		chunk.updateBlockIfDegradable(x - 1, y, z, .{.typ = self.topWoodBlock.typ, .data = 3});
	} else if(d == 2 and chunk.liesInChunk(x, y + 1, z)) {
		chunk.updateBlockIfDegradable(x, y + 1, z, .{.typ = self.topWoodBlock.typ, .data = 4});
	} else if(d == 3 and chunk.liesInChunk(x, y - 1, z)) {
		chunk.updateBlockIfDegradable(x, y - 1, z, .{.typ = self.topWoodBlock.typ, .data = 5});
	}
}

pub fn generate(self: *SimpleTreeModel, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const factor = random.nextFloat(seed);
	var height = self.height0 + @as(i32, @intFromFloat(factor*@as(f32, @floatFromInt(self.deltaHeight))));
	const leafRadius = self.leafRadius + factor*self.deltaLeafRadius;
	const leafElongation: f32 = self.leafElongation + random.nextFloatSigned(seed)*self.deltaLeafElongation;

	if(z + height >= caveMap.findTerrainChangeAbove(x, y, z)) // Space is too small.Allocator
		return;

	if(z > chunk.super.width) return;

	if(chunk.super.pos.voxelSize >= 16) {
		// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
		if(chunk.liesInChunk(x, y, z)) {
			chunk.updateBlockIfDegradable(x, y, z, self.leavesBlock);
		}
		if(chunk.liesInChunk(x, y, z + chunk.super.pos.voxelSize)) {
			chunk.updateBlockIfDegradable(x, y, z + chunk.super.pos.voxelSize, self.leavesBlock);
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
							chunk.updateBlockIfDegradable(px, py, pz, self.leavesBlock);
					}
				}
			}
		},
		.round => {
			self.generateStem(x, y, z, height, chunk, seed);

			const ceilZRadius: i32 = @intFromFloat(@ceil(leafRadius*leafElongation));
			const ceilRadius: i32 = @intFromFloat(@ceil(leafRadius));
			const radiusSqr: f32 = leafRadius*leafRadius;
			const randomRadiusSqr: f32 = (leafRadius - 0.25)*(leafRadius - 0.25);
			const invLeafElongationSqr = 1.0/(leafElongation*leafElongation);
			const center = z + height;
			var pz = chunk.startIndex(center - ceilZRadius);
			while(pz < center + ceilZRadius) : (pz += chunk.super.pos.voxelSize) {
				var px = chunk.startIndex(x - ceilRadius);
				while(px < x + ceilRadius) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y - ceilRadius);
					while(py < y + ceilRadius) : (py += chunk.super.pos.voxelSize) {
						const distSqr = @as(f32, @floatFromInt((pz - center)*(pz - center)))*invLeafElongationSqr + @as(f32, @floatFromInt((px - x)*(px - x) + (py - y)*(py - y)));
						if(chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							chunk.updateBlockIfDegradable(px, py, pz, self.leavesBlock);
						}
					}
				}
			}
		},
	}
}
