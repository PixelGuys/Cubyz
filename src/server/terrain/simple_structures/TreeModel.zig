const std = @import("std");

const main = @import("root");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const Block = main.blocks.Block;
const parseBlock = main.blocks.parseBlock;
const Neighbor = main.chunk.Neighbor;
const TorchData = main.rotation.RotationModes.Torch.TorchData;
const List = main.List;

pub const id = "cubyz:tree";

const TreeModel = @This();

pub const generationMode = .floor;

/// Tree layout
///      *
///     *|*     ] crown peak, made out of branch
///   *-||*     ] crown2 \
///  *--||-**   | crown1 stem - generates long leafed branches
///  **-||--*   ] crown0 /
///  *--||      ] leafed branches stem - generates short leafed branches
///   --||      ] leafless branches stem - generates short leafless branches
///     ||'     ] branchless stem - can generate mushrooms


const Blocks = struct {
	leaves: Block,
	wood: Block,
	top: Block,
	branch: Block,
	mushroom: Block,
};

const BranchlessStem = struct {
	height: f32,
	heightDelta: f32,
	mushroomChance: f32,

	pub fn getEffectiveHeight(self: *@This(), factor: f32) i32 {
		return @intFromFloat(@round(self.height + (factor - 0.5) * self.heightDelta));
	}
	pub fn generate(self: *@This(), position: Vec3i, chunk: *main.chunk.ServerChunk, factors: Factors, blocks: Blocks) Vec3i {
		const effectiveHeight = self.getEffectiveHeight(factors.branchless);
		if(effectiveHeight < 0) return position;

		var currentPosition: Vec3i = .{position[0], position[1], position[2]};

		for(0..@intCast(effectiveHeight)) |offset| {
			for(Neighbor.horizontal) |direction| {
				if(random.nextFloat(factors.seed) < self.mushroomChance) {
					const center = (offset == 0) and (random.nextFloat(factors.seed) < 0.5);
					placeBlockWithData(chunk, currentPosition + direction.relPos(), blocks.mushroom, directionToMushroomData(direction, center));
				}
			}
			placeBlock(chunk, currentPosition, blocks.wood);
			currentPosition[2] += 1;
		}
		return currentPosition;
	}
};

fn placeBlock(chunk: *main.chunk.ServerChunk, position: Vec3i, block: Block) void {
	if(chunk.liesInChunk(position[0], position[1], position[2])) {
		chunk.updateBlockIfDegradable(position[0], position[1], position[2], block);
	}
}

fn placeBlockWithData(chunk: *main.chunk.ServerChunk, position: Vec3i, block: Block, data: u16) void {
	if(chunk.liesInChunk(position[0], position[1], position[2]) and chunk.getBlock(position[0], position[1], position[2]).typ == 0) {
		const blockWithData = Block{.typ = block.typ, .data = data};
		chunk.updateBlockIfDegradable(position[0], position[1], position[2], blockWithData);
	}
}

fn directionToMushroomData(direction: Neighbor, center: bool) u16 {
	if(center) {
		return @as(u5, @bitCast(TorchData{.center = true, .negX = false, .posX = false, .negY = false, .posY = false}));
	}
	switch(direction) {
		Neighbor.dirPosX => return @as(u5, @bitCast(TorchData{.center = false, .negX = true, .posX = false, .negY = false, .posY = false})),
		Neighbor.dirNegX => return @as(u5, @bitCast(TorchData{.center = false, .negX = false, .posX = true, .negY = false, .posY = false})),
		Neighbor.dirPosY => return @as(u5, @bitCast(TorchData{.center = false, .negX = false, .posX = false, .negY = true, .posY = false})),
		Neighbor.dirNegY => return @as(u5, @bitCast(TorchData{.center = false, .negX = false, .posX = false, .negY = false, .posY = true})),
		else => unreachable,
	}
}

const BranchedStem = struct {
	height: f32,
	heightDelta: f32,
	branchChance: f32,
	branchRandomChance: f32,
	branchLength: f32,
	branchLengthDelta: f32,
	maxBranchCount: u32,
	leavesChance: f32,
	leavesBlobChance: f32,

	pub fn getEffectiveHeight(self: *@This(), factor: f32) i32 {
		return @intFromFloat(@round(self.height + (factor - 0.5) * self.heightDelta));
	}
	pub fn generate(self: *@This(), position: Vec3i, chunk: *main.chunk.ServerChunk, factors: Factors, blocks: Blocks) Vec3i {
		const effectiveHeight = self.getEffectiveHeight(factors.branchless);
		if(effectiveHeight < 0) return position;

		var currentPosition: Vec3i = .{position[0], position[1], position[2]};
		var branchGenerator = BranchGenerator{
			.blocks = blocks,
			.factors = factors,
			.chunk = chunk,
			.randomChance = self.branchRandomChance,
			.leavesChance = self.leavesChance,
			.leavesBlobChance = self.leavesBlobChance};

		var branchCount: u32 = 0;

		for(0..@intCast(effectiveHeight)) |i| {
			if(i % 2 == 0) {
				if(branchCount < self.maxBranchCount) {
					branchCount += @intFromBool(self.branch(&branchGenerator, Neighbor.dirPosX, currentPosition, factors));
				}
				if(branchCount < self.maxBranchCount) {
					branchCount += @intFromBool(self.branch(&branchGenerator, Neighbor.dirNegX, currentPosition, factors));
				}
				if(branchCount < self.maxBranchCount) {
					branchCount += @intFromBool(self.branch(&branchGenerator, Neighbor.dirPosY, currentPosition, factors));
				}
				if(branchCount < self.maxBranchCount) {
					branchCount += @intFromBool(self.branch(&branchGenerator, Neighbor.dirNegY, currentPosition, factors));
				}
			}
			placeBlock(chunk, currentPosition, blocks.wood);
			currentPosition[2] += 1;
		}
		return currentPosition;
	}
	fn branch(self: *@This(), branchGenerator: *BranchGenerator, direction: Neighbor, position: Vec3i, factors: Factors) bool {
		if(random.nextFloat(factors.seed) > self.branchChance) return false;

		const branchLength: i32 = @intFromFloat(@round(self.branchLength + (random.nextFloat(factors.seed) - 0.5) * self.branchLengthDelta));
		return branchGenerator.generate(direction, position + direction.relPos(), branchLength);
	}
};



const BranchGenerator = struct {
	blocks: Blocks,
	factors: Factors,
	chunk: *main.chunk.ServerChunk,
	randomChance: f32,
	leavesChance: f32,
	leavesBlobChance: f32,

	const Segment = enum {
		lrJunction,
		lfJunction,
		rfJunction,
		lrfJunction,
		forward,
		left,
		right,
	};
	const customSeries: [6][]const Segment = .{
		&.{.forward, .rfJunction, .forward, .lrfJunction},
		&.{.forward, .lrfJunction, .forward, .lfJunction},
		&.{.forward, .lfJunction, .rfJunction},
		&.{.forward, .forward, .lfJunction, .right},
		&.{.lfJunction, .forward, .left, .forward},
		&.{.rfJunction, .lfJunction, .forward, .lrfJunction},
	};

	pub fn generate(self: *@This(), direction: Neighbor, position: Vec3i, length: i32) bool {
		const seriesIndex = random.nextInt(u32, self.factors.seed) % 6;
		return _generate(self, direction, position, length, @This().customSeries[seriesIndex], 0);
	}

	fn _generate(self: *@This(), direction: Neighbor, position: Vec3i, length: i32, series: []const Segment, index: usize) bool {
		if(length < 1) return false;
		if(length == 1) return self.junction(direction, false, false, false, position, length, series, index);

		const newIndex = (index + 1) % series.len;
		const segment = series[index];

		return switch(segment) {
			.lrJunction => self.junction(direction, true, true, false, position, length, series, newIndex),
			.lfJunction => self.junction(direction, true, false, true, position, length, series, newIndex),
			.rfJunction => self.junction(direction, false, true, true, position, length, series, newIndex),
			.lrfJunction => self.junction(direction, true, true, true, position, length, series, newIndex),
			.forward => self.junction(direction, false, false, true, position, length, series, newIndex),
			.left => self.junction(direction, true, false, false, position, length, series, newIndex),
			.right => self.junction(direction, false, true, false, position, length, series, newIndex),
		};
	}

	fn junction(self: *@This(), direction: Neighbor, doLeft: bool, doRight: bool, doForward: bool, position: Vec3i, length: i32, series: []const Segment, index: usize) bool {
		if(length < 1) return false;
		std.debug.assert(!(length == 1 and (doLeft or doRight or doForward)));

		var isLeftSuccess = false;
		var isRightSuccess = false;
		var isForwardSuccess = false;
		var isTopSuccess = false;

		const left: Neighbor = direction.left();
		const right: Neighbor = direction.right();
		const forward: Neighbor = direction;
		const up = Neighbor.dirUp;
		const down = Neighbor.dirDown;
		const back = direction.reverse();

		if(doLeft) {
			isLeftSuccess = self._generate(left, position + left.relPos(), length - 1, series, index);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.factors.seed) < self.leavesChance) {
				isLeftSuccess = self.place(position + left.relPos(), self.blocks.leaves, 0);
			}
		}
		if(doRight){
			isRightSuccess = self._generate(right, position + right.relPos(), length - 1, series, index);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.factors.seed) < self.leavesChance) {
				isRightSuccess = self.place(position + right.relPos(), self.blocks.leaves, 0);
			}
		}
		if(doForward) {
			isForwardSuccess = self._generate(direction, position + direction.relPos(), length - 1, series, index);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.factors.seed) < self.leavesChance) {
				isForwardSuccess = self.place(position + forward.relPos(), self.blocks.leaves, 0);
			}
		}
		isTopSuccess = self.place(position + up.relPos(), self.blocks.leaves, 0);

		if(self.leavesChance > 0 and random.nextFloat(self.factors.seed) < self.leavesBlobChance) {
			_ = self.place(position + forward.relPos() + left.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + forward.relPos() + right.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + forward.relPos() + up.relPos(), self.blocks.leaves, 0);

			_ = self.place(position + left.relPos() + down.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + left.relPos() + up.relPos(), self.blocks.leaves, 0);

			_ = self.place(position + right.relPos() + down.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + right.relPos() + up.relPos(), self.blocks.leaves, 0);

			_ = self.place(position + back.relPos() + left.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + back.relPos() + right.relPos(), self.blocks.leaves, 0);
			_ = self.place(position + back.relPos() + up.relPos(), self.blocks.leaves, 0);
		}

		var blockData: u16 = 0;
		blockData |= direction.reverse().bitMask();

		if(isLeftSuccess) blockData |= left.bitMask();
		if(isRightSuccess) blockData |= right.bitMask();
		if(isForwardSuccess) blockData |= forward.bitMask();
		if(isTopSuccess) blockData |= up.bitMask();

		return self.place(position, self.blocks.branch, blockData);
	}

	fn place(self: *@This(), position: Vec3i, block: Block, data: u16) bool {
		if(self.chunk.liesInChunk(position[0], position[1], position[2])) {
			const blockWithData = Block{.typ = block.typ, .data = data};
			return self.chunk.updateBlockIfAir(position[0], position[1], position[2], blockWithData);
		}
		return true;
	}
};

const CrownPeak = struct {
	height: f32,
	heightDelta: f32,

	pub fn getEffectiveHeight(self: *@This(), factor: f32) i32 {
		return @intFromFloat(@round(self.height + (factor - 0.5) * self.heightDelta));
	}
	pub fn generate(self: *@This(), position: Vec3i, chunk: *main.chunk.ServerChunk, factors: Factors, blocks: Blocks) Vec3i {
		const effectiveHeight = self.getEffectiveHeight(factors.branchless);
		if(effectiveHeight < 0) return position;

		var currentPosition: Vec3i = .{position[0], position[1], position[2]};

		for(0..@intCast(effectiveHeight)) |_| {
			placeBlock(chunk, currentPosition, blocks.top);
			placeBlock(chunk, currentPosition + Neighbor.dirPosX.relPos(), blocks.leaves);
			placeBlock(chunk, currentPosition + Neighbor.dirNegX.relPos(), blocks.leaves);
			placeBlock(chunk, currentPosition + Neighbor.dirPosY.relPos(), blocks.leaves);
			placeBlock(chunk, currentPosition + Neighbor.dirNegY.relPos(), blocks.leaves);
			currentPosition[2] += 1;
		}
		placeBlock(chunk, currentPosition, blocks.leaves);
		return currentPosition;
	}
};

const Factors = struct {
	seed: *u64,
	branchless: f32,
	leaflessBranches: f32,
	leafedBranches: f32,
	crown: f32,
	crownPeak: f32,

	pub fn init(seed: *u64) Factors {
		return .{
			.seed = seed,
			.branchless = random.nextFloat(seed),
			.leaflessBranches = random.nextFloat(seed),
			.leafedBranches = random.nextFloat(seed),
			.crown = random.nextFloat(seed),
			.crownPeak = random.nextFloat(seed),
		};
	}
};

blocks: Blocks,
branchless: BranchlessStem,
leaflessBranches: BranchedStem,
leafedBranches: BranchedStem,
crown0: BranchedStem,
crown1: BranchedStem,
crown2: BranchedStem,
crownPeak: CrownPeak,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *TreeModel {
	const self = arenaAllocator.create(TreeModel);
	const blockParameters = parameters.getChild("blocks");
	const branchlessParameters = parameters.getChild("branchlessStem");
	const leaflessBranchesParameters = parameters.getChild("leaflessBranchedStem");
	const leafedBranchesParameters = parameters.getChild("leafedBranchedStem");
	const crown0Parameters = parameters.getChild("crown0Stem");
	const crown1Parameters = parameters.getChild("crown1Stem");
	const crown2Parameters = parameters.getChild("crown1Stem");

	self.* = .{
		.blocks = .{
			.leaves = parseBlock(blockParameters.get([]const u8, "leaves", "cubyz:oak_leaves")),
			.wood = parseBlock(blockParameters.get([]const u8, "wood", "cubyz:oak_log")),
			.top = parseBlock(blockParameters.get([]const u8, "top", "cubyz:oak_top")),
			.branch = parseBlock(blockParameters.get([]const u8, "branch", "cubyz:oak_branch")),
			.mushroom = parseBlock(blockParameters.get([]const u8, "mushroom", "cubyz:bolete")),
		},
		.branchless = .{
			.height = branchlessParameters.get(f32, "height", 2),
			.heightDelta = branchlessParameters.get(f32, "heightDelta", 1),
			.mushroomChance = branchlessParameters.get(f32, "mushroomChance", 0.1),
		},
		.leaflessBranches = .{
			.height = leaflessBranchesParameters.get(f32, "height", 3),
			.heightDelta = leaflessBranchesParameters.get(f32, "heightDelta", 1),
			.branchChance = leaflessBranchesParameters.get(f32, "branchChance", 0.25),
			.branchRandomChance = leaflessBranchesParameters.get(f32, "branchRandomChance", 0.5),
			.branchLength = leaflessBranchesParameters.get(f32, "branchLength", 1.0),
			.branchLengthDelta = leaflessBranchesParameters.get(f32, "branchLengthDelta", 0.0),
			.maxBranchCount = leaflessBranchesParameters.get(u32, "maxBranchCount", 1),
			.leavesChance = leaflessBranchesParameters.get(f32, "leavesChance", 0.1),
			.leavesBlobChance = leaflessBranchesParameters.get(f32, "leavesBlobChance", 0.0),
		},
		.leafedBranches = .{
			.height = leafedBranchesParameters.get(f32, "height", 3),
			.heightDelta = leafedBranchesParameters.get(f32, "heightDelta", 1),
			.branchChance = leafedBranchesParameters.get(f32, "branchChance", 0.25),
			.branchRandomChance = leafedBranchesParameters.get(f32, "branchRandomChance", 0.33),
			.branchLength = leafedBranchesParameters.get(f32, "branchLength", 3.0),
			.branchLengthDelta = leafedBranchesParameters.get(f32, "branchLengthDelta", 1),
			.maxBranchCount = leafedBranchesParameters.get(u32, "maxBranchCount", 2),
			.leavesChance = leafedBranchesParameters.get(f32, "leavesChance", 0.5),
			.leavesBlobChance = leafedBranchesParameters.get(f32, "leavesBlobChance", 0.0),
		},
		.crown0 = .{
			.height = crown0Parameters.get(f32, "height", 5.0),
			.heightDelta = crown0Parameters.get(f32, "heightDelta", 1.0),
			.branchChance = crown0Parameters.get(f32, "branchChance", 0.66),
			.branchRandomChance = crown0Parameters.get(f32, "branchRandomChance", 0.33),
			.branchLength = crown0Parameters.get(f32, "branchLength", 4.0),
			.branchLengthDelta = crown0Parameters.get(f32, "branchLengthDelta", 1.0),
			.maxBranchCount = crown0Parameters.get(u32, "maxBranchCount", 15),
			.leavesChance = crown0Parameters.get(f32, "leavesChance", 0.9),
			.leavesBlobChance = crown0Parameters.get(f32, "leavesBlobChance", 0.7),
		},
		.crown1 = .{
			.height = crown1Parameters.get(f32, "height", 5.0),
			.heightDelta = crown1Parameters.get(f32, "heightDelta", 1.0),
			.branchChance = crown1Parameters.get(f32, "branchChance", 0.5),
			.branchRandomChance = crown1Parameters.get(f32, "branchRandomChance", 0.33),
			.branchLength = crown1Parameters.get(f32, "branchLength", 5.0),
			.branchLengthDelta = crown1Parameters.get(f32, "branchLengthDelta", 1.0),
			.maxBranchCount = crown1Parameters.get(u32, "maxBranchCount", 10),
			.leavesChance = crown1Parameters.get(f32, "leavesChance", 0.9),
			.leavesBlobChance = crown1Parameters.get(f32, "leavesBlobChance", 0.5),
		},
		.crown2 = .{
			.height = crown2Parameters.get(f32, "height", 3.0),
			.heightDelta = crown2Parameters.get(f32, "heightDelta", 1.0),
			.branchChance = crown2Parameters.get(f32, "branchChance", 0.5),
			.branchRandomChance = crown2Parameters.get(f32, "branchRandomChance", 0.33),
			.branchLength = crown2Parameters.get(f32, "branchLength", 3.0),
			.branchLengthDelta = crown2Parameters.get(f32, "branchLengthDelta", 1.0),
			.maxBranchCount = crown2Parameters.get(u32, "maxBranchCount", 10),
			.leavesChance = crown2Parameters.get(f32, "leavesChance", 0.9),
			.leavesBlobChance = crown2Parameters.get(f32, "leavesBlobChance", 0.5),
		},
		.crownPeak = .{
			.height = parameters.get(f32, "crownPeakHeight", 1.0),
			.heightDelta = parameters.get(f32, "crownPeakHeightDelta", 0.0),
		}
	};
	return self;
}

pub fn getEffectiveHeight(self: *@This(), factors: Factors) i32 {
	return self.branchless.getEffectiveHeight(factors.branchless) +
		self.leaflessBranches.getEffectiveHeight(factors.leaflessBranches) +
		self.leafedBranches.getEffectiveHeight(factors.leafedBranches) +
		self.crown0.getEffectiveHeight(factors.crown) +
		self.crown1.getEffectiveHeight(factors.crown) +
		self.crown2.getEffectiveHeight(factors.crown) +
		self.crownPeak.getEffectiveHeight(factors.crownPeak);
}

pub fn generate(self: *@This(), x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, _: bool) void {
	const factors = Factors.init(seed);
	const effectiveHeight = self.getEffectiveHeight(factors);

	if(z + effectiveHeight >= caveMap.findTerrainChangeAbove(x, y, z)) // Space is too small.
		return;

	if(z > chunk.super.width) return;

	if(chunk.super.pos.voxelSize >= 16) {
		// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
		if(chunk.liesInChunk(x, y, z)) {
			chunk.updateBlockIfDegradable(x, y, z, self.blocks.leaves);
		}
		if(chunk.liesInChunk(x, y, z + chunk.super.pos.voxelSize)) {
			chunk.updateBlockIfDegradable(x, y, z + chunk.super.pos.voxelSize, self.blocks.leaves);
		}
	}
	if(chunk.super.pos.voxelSize >= 2) {
		return;
	}
	var position = Vec3i{x, y, z};
	position = self.branchless.generate(position, chunk, factors, self.blocks);
	position = self.leaflessBranches.generate(position, chunk, factors, self.blocks);
	position = self.leafedBranches.generate(position, chunk, factors, self.blocks);
	position = self.crown0.generate(position, chunk, factors, self.blocks);
	position = self.crown1.generate(position, chunk, factors, self.blocks);
	position = self.crown2.generate(position, chunk, factors, self.blocks);
	position = self.crownPeak.generate(position, chunk, factors, self.blocks);
}