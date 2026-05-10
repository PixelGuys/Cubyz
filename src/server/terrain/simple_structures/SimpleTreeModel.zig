const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.structures.SimpleStructureModel.GenerationMode;
const Neighbor = main.chunk.Neighbor;
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
const RotationModeType = enum {
	unknown,
	log,
	branch,
	direction,
};

typ: Type,
leavesBlock: Block,
woodBlock: Block,
woodRotationModeType: RotationModeType = .unknown,
topWoodBlock: Block,
topRotationModeType: RotationModeType = .unknown,
height0: i32,
deltaHeight: u31,
leafRadius: f32,
deltaLeafRadius: f32,
leafElongation: f32,
deltaLeafElongation: f32,
branched: bool,

pub fn loadModel(parameters: ZonElement) ?*SimpleTreeModel {
	const self = main.worldArena.create(SimpleTreeModel);
	const woodBlock = main.blocks.parseBlock(parameters.get(?[]const u8, "log", null) orelse {
		std.log.err("Missing required 'log' field for cubyz:simple_tree rotation", .{});
		return null;
	});
	self.* = .{
		.typ = std.meta.stringToEnum(Type, parameters.get([]const u8, "type", "")) orelse blk: {
			if (parameters.get(?[]const u8, "type", null)) |typ| std.log.err("Unknown tree type \"{s}\"", .{typ});
			break :blk .round;
		},
		.leavesBlock = main.blocks.parseBlock(parameters.get(?[]const u8, "leaves", null) orelse {
			std.log.err("Missing required 'leaves' field for cubyz:simple_tree rotation", .{});
			return null;
		}),
		.woodBlock = woodBlock,
		.topWoodBlock = blk: {
			break :blk main.blocks.parseBlock(parameters.get(?[]const u8, "top", null) orelse break :blk woodBlock);
		},
		.height0 = parameters.get(i32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
		.leafRadius = parameters.get(f32, "leafRadius", (1 + parameters.get(f32, "height", 6))/2),
		.deltaLeafRadius = parameters.get(f32, "leafRadius_variation", parameters.get(f32, "height_variation", 3)/2),
		.leafElongation = parameters.get(f32, "leafElongation", 1),
		.deltaLeafElongation = parameters.get(f32, "deltaLeafElongation", 0),
		.branched = parameters.get(bool, "branched", true),
	};
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:branch")) self.woodRotationModeType = .branch;
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:log")) self.woodRotationModeType = .log;
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:direction")) self.woodRotationModeType = .direction;
	if (self.topWoodBlock.mode() == main.rotation.getByID("cubyz:branch")) self.topRotationModeType = .branch;
	if (self.topWoodBlock.mode() == main.rotation.getByID("cubyz:log")) self.topRotationModeType = .log;
	if (self.topWoodBlock.mode() == main.rotation.getByID("cubyz:direction")) self.topRotationModeType = .direction;
	return self;
}

fn initalOrientation(block: main.blocks.Block, orientation: Neighbor, mode: RotationModeType) main.blocks.Block {
	switch (mode) {
		.log, .branch => {
			return .{.typ = block.typ, .data = orientation.reverse().bitMask()};
		},
		.direction => {
			return .{.typ = block.typ, .data = @intFromEnum(orientation)};
		},
		.unknown => return block,
	}
}

fn addNeighbor(block: main.blocks.Block, neighborDir: Neighbor, mode: RotationModeType) main.blocks.Block {
	switch (mode) {
		.log, .branch => {
			return .{.typ = block.typ, .data = block.data | neighborDir.bitMask()};
		},
		.direction, .unknown => return block,
	}
}

pub fn generateStem(self: *SimpleTreeModel, x: i32, y: i32, z: i32, height: i32, chunk: *main.chunk.ServerChunk, seed: *u64) void {
	if (chunk.super.pos.voxelSize <= 2) {
		var pz: i32 = chunk.startIndex(z);
		while (pz < z + height) : (pz += chunk.super.pos.voxelSize) {
			if (chunk.liesInChunk(x, y, pz)) {
				var block = if (pz == z + height - 1) self.topWoodBlock else self.woodBlock;
				const rotationModeType = if (pz == z + height - 1) self.topRotationModeType else self.woodRotationModeType;
				block = initalOrientation(block, .dirUp, rotationModeType);
				if (pz != z + height - 1) block = addNeighbor(block, .dirUp, rotationModeType);

				if (self.branched) {
					const chance = @sqrt(@as(f32, @floatFromInt(pz - z))/@as(f32, @floatFromInt(height*2)));
					if (main.random.nextFloat(seed) < chance) {
						const dir: Neighbor = @enumFromInt(main.random.nextIntBounded(u32, seed, 4) + 2);
						generateBranch(self, x, y, pz, dir, chunk);
						block = addNeighbor(block, dir, rotationModeType);
					}
				}

				chunk.updateBlockIfDegradable(x, y, pz, block);
			}
		}
	}
}

pub fn generateBranch(self: *SimpleTreeModel, x: i32, y: i32, z: i32, dir: Neighbor, chunk: *main.chunk.ServerChunk) void {
	const block = initalOrientation(self.topWoodBlock, dir, self.topRotationModeType);
	const x2 = x + dir.relX();
	const y2 = y + dir.relY();

	if (chunk.liesInChunk(x2, y2, z)) {
		chunk.updateBlockIfDegradable(x2, y2, z, block);
	}
}

pub fn generate(self: *SimpleTreeModel, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const factor = random.nextFloat(seed);
	var height = self.height0 + @as(i32, @trunc(factor*@as(f32, @floatFromInt(self.deltaHeight))));
	const leafRadius = self.leafRadius + factor*self.deltaLeafRadius;
	const leafElongation: f32 = self.leafElongation + random.nextFloatSigned(seed)*self.deltaLeafElongation;

	if (z + height >= caveMap.findTerrainChangeAbove(x, y, z)) // Space is too small.Allocator
		return;

	if (z > chunk.super.width) return;

	if (chunk.super.pos.voxelSize >= 16) {
		// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
		if (chunk.liesInChunk(x, y, z)) {
			chunk.updateBlockIfDegradable(x, y, z, self.leavesBlock);
		}
		if (chunk.liesInChunk(x, y, z + chunk.super.pos.voxelSize)) {
			chunk.updateBlockIfDegradable(x, y, z + chunk.super.pos.voxelSize, self.leavesBlock);
		}
	}

	switch (self.typ) {
		.pyramid => {
			self.generateStem(x, y, z, height, chunk, seed);
			// Position of the first block of leaves
			height = 3*height >> 1;
			var pz = chunk.startIndex(z + @divTrunc(height, 3));
			while (pz < z + height) : (pz += chunk.super.pos.voxelSize) {
				const j = @divFloor(height - (pz - z), 2);
				var px = chunk.startIndex(x + 1 - j);
				while (px < x + j) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y + 1 - j);
					while (py < y + j) : (py += chunk.super.pos.voxelSize) {
						if (chunk.liesInChunk(px, py, pz))
							chunk.updateBlockIfDegradable(px, py, pz, self.leavesBlock);
					}
				}
			}
		},
		.round => {
			self.generateStem(x, y, z, height, chunk, seed);

			const ceilZRadius: i32 = @ceil(leafRadius*leafElongation);
			const ceilRadius: i32 = @ceil(leafRadius);
			const radiusSqr: f32 = leafRadius*leafRadius;
			const randomRadiusSqr: f32 = (leafRadius - 0.25)*(leafRadius - 0.25);
			const invLeafElongationSqr = 1.0/(leafElongation*leafElongation);
			const center = z + height;
			var pz = chunk.startIndex(center - ceilZRadius);
			while (pz < center + ceilZRadius) : (pz += chunk.super.pos.voxelSize) {
				var px = chunk.startIndex(x - ceilRadius);
				while (px < x + ceilRadius) : (px += chunk.super.pos.voxelSize) {
					var py = chunk.startIndex(y - ceilRadius);
					while (py < y + ceilRadius) : (py += chunk.super.pos.voxelSize) {
						const distSqr = @as(f32, @floatFromInt((pz - center)*(pz - center)))*invLeafElongationSqr + @as(f32, @floatFromInt((px - x)*(px - x) + (py - y)*(py - y)));
						if (chunk.liesInChunk(px, py, pz) and distSqr < radiusSqr and (distSqr < randomRadiusSqr or random.nextInt(u1, seed) != 0)) { // TODO: Use another seed to make this more reliable!
							chunk.updateBlockIfDegradable(px, py, pz, self.leavesBlock);
						}
					}
				}
			}
		},
	}
}
