const std = @import("std");

const main = @import("root");
// const main = @import("../../../main.zig");
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
const ServerChunk = main.chunk.ServerChunk;

pub const id = "cubyz:tree";

const TreeModel = @This();

pub const generationMode = .floor;


const BranchSpawnMode = enum {
	random,
	alternating,
	alternating_spaced,
	alternating_random,
	screw_right,
	screw_left,
	screw_random,
	flipped,

	fn fromString(string: []const u8) @This() {
		return std.meta.stringToEnum(@This(), string) orelse {
			std.log.err("Couldn't find branch spawn mode {s}. Replacing it with random", .{string});
			return .random;
		};
	}
};

const Stem = struct {
	height: usize,
	branchChance: f32,
	branchSpacing: u32,
	branchSpawnMode: BranchSpawnMode,
	branchMaxCount: u32,
	branchMaxCountPerLevel: u32,
	branchPeak: bool,
	branchSegmentSeriesVariants: ZonElement,
	leavesChance: f32,
	leavesBlobChance: f32,
	leavesBlobRadius: f32,
	leavesBlobRadiusDelta: f32,
	mushroomChance: f32,
	stemThickness: usize,
	blocks: Blocks,

	pub fn generate(self: @This(), state: *TreeState) void {
		if(self.height == 0) return;
		if(self.stemThickness == 0) return;

		var branchGenerator = BranchGenerator{
			.state = state,
			.blocks = self.blocks,
			.leavesChance = self.leavesChance,
			.leavesBlobChance = self.leavesBlobChance,
			.leavesBlobRadius = self.leavesBlobRadius,
			.leavesBlobRadiusDelta = self.leavesBlobRadiusDelta};

		var branchCount: u32 = 0;
		var branchCountThisLevel: u32 = 0;

		const horizontal = [_]Neighbor{.dirPosX, .dirNegX, .dirPosY, .dirNegY};

		const screwIsRight = switch(self.branchSpawnMode) {
			.screw_right => true,
			.screw_left => false,
			.screw_random => random.nextFloat(state.seed) < 0.5,
			else => false,
		};

		for(0..self.height) |_| {
			for(horizontal) |direction| {
				if(self.mushroomChance <= 0 and self.branchSpawnMode != .random) break;

				if(self.mushroomChance > 0 and random.nextFloat(state.seed) < self.mushroomChance) {
					self.placeMushroom(state, state.position + direction.relPos(), direction, false);
					continue;
				}
				switch(self.branchSpawnMode) {
					.random => {
						if(branchCountThisLevel >= self.branchMaxCountPerLevel) continue;
						if(self.branchChance <= 0) continue;
						if(branchCount >= self.branchMaxCount) continue;
						if(random.nextFloat(state.seed) > self.branchChance) continue;

						const isSuccess: u32 = @intFromBool(self.placeBranch(state, &branchGenerator, direction, state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
						continue;
					},
					else => {},
				}
			}
			switch(self.branchSpawnMode){
				.alternating => {
					_ = self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position);
					_ = self.placeBranch(state, &branchGenerator, state.spawnAxis.reverse(), state.position);
					state.spawnAxis = state.spawnAxis.right();
				},
				.alternating_spaced => {
					if(state.alternateBranchSpacing >= self.branchSpacing) {
						_ = self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position);
						_ = self.placeBranch(state, &branchGenerator, state.spawnAxis.reverse(), state.position);
						state.spawnAxis = state.spawnAxis.right();
						state.alternateBranchSpacing = 0;
					} else {
						state.alternateBranchSpacing += 1;
					}
				},
				.alternating_random => blk: {
					if(branchCountThisLevel >= self.branchMaxCountPerLevel) break :blk;
					if(self.branchChance <= 0) break :blk;
					if(branchCount >= self.branchMaxCount) break :blk;

					if(random.nextFloat(state.seed) < self.branchChance) {
						const isSuccess = @intFromBool(self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
					}
					if(random.nextFloat(state.seed) < self.branchChance) {
						const isSuccess = @intFromBool(self.placeBranch(state, &branchGenerator, state.spawnAxis.reverse(), state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
					}

					state.spawnAxis = state.spawnAxis.right();
				},
				.screw_right, .screw_left, .screw_random => {
					_ = self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position);
					if(screwIsRight) {
						state.spawnAxis = state.spawnAxis.right();
					} else {
						state.spawnAxis = state.spawnAxis.left();
					}
				},
				.flipped => {
					_ = self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position);
					state.spawnAxis = state.spawnAxis.reverse();
				},
				else => {},
			}
			for(0..self.stemThickness) |x| {
				for(0..self.stemThickness) |y| {
					const centerOffset = @as(i32, @intCast(self.stemThickness/2));
					self.placeBlock(
						state,
						.{state.position[0] + @as(i32, @intCast(x)) - centerOffset,
							state.position[1] + @as(i32, @intCast(y)) - centerOffset,
							state.position[2]},
						self.blocks.wood);
				}
			}

			state.position[2] += 1;
			state.height += 1;
			branchCountThisLevel = 0;
		}
		if(self.branchPeak) {
			_ = self.placeBranch(state, &branchGenerator, Neighbor.dirUp, .{state.position[0], state.position[1], state.position[2] - 1});
		}
	}
	fn placeBlock(_: @This(), state: *TreeState, position: Vec3i, block: Block) void {
		if(!state.chunk.liesInChunk(position[0], position[1], position[2])) return;
		state.chunk.updateBlock(position[0], position[1], position[2], block);
	}
	fn placeBranch(self: @This(), state: *TreeState, branchGenerator: *BranchGenerator, direction: Neighbor, position: Vec3i) bool {
		if(self.branchSegmentSeriesVariants.isNull()) return false;
		if(self.branchSegmentSeriesVariants.array.items.len == 0) return false;

		const branchVariantIndex = random.nextInt(usize, state.seed) % self.branchSegmentSeriesVariants.array.items.len;
		const branchSeries = self.branchSegmentSeriesVariants.getChildAtIndex(branchVariantIndex);

		return branchGenerator.generate(direction, position + direction.relPos(), branchSeries);
	}
	fn placeMushroom(self: @This(), state: *TreeState, position: Vec3i, direction: Neighbor, center: bool) void {
		if(!state.chunk.liesInChunk(position[0], position[1], position[2])) return;

		const blockData = self.directionToMushroomData(direction, center);
		const blockWithData = Block{.typ = self.blocks.mushroom.typ, .data = blockData};

		_ = state.chunk.updateBlockIfAir(position[0], position[1], position[2], blockWithData);
	}
	fn directionToMushroomData(_: @This(), direction: Neighbor, center: bool) u16 {
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
};

const Blocks = struct {
	leaves: Block,
	wood: Block,
	branch: Block,
	mushroom: Block,
};

const TreeState = struct {
	seed: *u64,
	chunk: *ServerChunk,
	position: Vec3i,
	height: usize,
	spawnAxis: Neighbor,
	alternateBranchSpacing: u32,
};

const BranchGenerator = struct {
	state: *TreeState,
	blocks: Blocks,
	leavesChance: f32,
	leavesBlobChance: f32,
	leavesBlobRadius: f32,
	leavesBlobRadiusDelta: f32,

	pub fn generate(self: *@This(), direction: Neighbor, position: Vec3i, series: ZonElement) bool {
		const horizontalDirection = if(direction == Neighbor.dirUp) Neighbor.dirPosX else direction;
		return junction(self, horizontalDirection, direction, position, series);
	}
	fn junction(self: *@This(), horizontalDirection: Neighbor, direction: Neighbor, position: Vec3i, series: ZonElement) bool {
		var leftSeries = series.getChild("left");
		var rightSeries = series.getChild("right");
		var forwardSeries = series.getChild("forward");
		var backwardSeries = series.getChild("backward");
		var upSeries = series.getChild("up");

		var isLeftSuccess = false;
		var isRightSuccess = false;
		var isForwardSuccess = false;
		var isUpSuccess = false;
		var isBackwardSuccess = false;

		const left: Neighbor = horizontalDirection.left();
		const right: Neighbor = horizontalDirection.right();
		const forward: Neighbor = horizontalDirection;
		const backward = horizontalDirection.reverse();
		const up = Neighbor.dirUp;

		if(!leftSeries.isNull()) {
			isLeftSuccess = self.junction(left, left, position + left.relPos(), leftSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isLeftSuccess = self.place(position + left.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!rightSeries.isNull()){
			isRightSuccess = self.junction(right, right, position + right.relPos(), rightSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isRightSuccess = self.place(position + right.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!forwardSeries.isNull()) {
			isForwardSuccess = self.junction(forward, forward, position + forward.relPos(), forwardSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isForwardSuccess = self.place(position + forward.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!backwardSeries.isNull()) {
			isBackwardSuccess = self.junction(backward, backward, position + backward.relPos(), backwardSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isBackwardSuccess = self.place(position + backward.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!upSeries.isNull()) {
			isUpSuccess = self.junction(forward, up, position + up.relPos(), upSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isUpSuccess = self.place(position + up.relPos(), self.blocks.leaves, 0);
			}
		}

		var blockData: u16 = 0;
		blockData |= direction.reverse().bitMask();

		if(isLeftSuccess) blockData |= left.bitMask();
		if(isRightSuccess) blockData |= right.bitMask();
		if(isForwardSuccess) blockData |= forward.bitMask();
		if(isBackwardSuccess) blockData |= backward.bitMask();
		if(isUpSuccess) blockData |= up.bitMask();

		const isSuccess = self.placeBranch(position, self.blocks.branch, blockData);

		if(isSuccess) {
			if(leftSeries.isNull() and rightSeries.isNull() and forwardSeries.isNull() and self.leavesBlobChance > 0 and random.nextFloat(self.state.seed) < self.leavesBlobChance) {
				const radius = self.leavesBlobRadius + (random.nextFloat(self.state.seed) - 0.5) * self.leavesBlobRadiusDelta;
				const pos: Vec3f = .{
					@as(f32, @floatFromInt(position[0])) + (random.nextFloat(self.state.seed) - 0.5)*1.5,
					@as(f32, @floatFromInt(position[1])) + (random.nextFloat(self.state.seed) - 0.5)*1.5,
					@as(f32, @floatFromInt(position[2])) + (random.nextFloat(self.state.seed) - 0.5)*1.5};

				self.placeSphere(pos, self.blocks.leaves, radius);
			}
		}

		return isSuccess;
	}
	fn place(self: *@This(), position: Vec3i, block: Block, data: u16) bool {
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;

		const blockWithData = Block{.typ = block.typ, .data = data};
		return self.state.chunk.updateBlockIfAir(position[0], position[1], position[2], blockWithData);
	}
	fn placeBranch(self: *@This(), position: Vec3i, block: Block, data: u16) bool {
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;

		const currentBlock = self.state.chunk.getBlock(position[0], position[1], position[2]);
		if(currentBlock.typ != 0 and currentBlock.typ != self.blocks.leaves.typ) return false;

		const blockWithData = Block{.typ = block.typ, .data = data};
		self.state.chunk.updateBlock(position[0], position[1], position[2], blockWithData);
		return true;
	}
	fn placeSphere(self: *@This(), pos: Vec3f, block: Block, radius: f32) void {
		if(radius <= 0) return;

		const radiusInt: i32 = @intFromFloat(@ceil(radius));
		const diameterInt: usize = 2 * @as(usize, @intCast(radiusInt));

		for(0..diameterInt) |i| {
			for(0..diameterInt) |j| {
				for(0..diameterInt) |k| {
					{
						const x = @as(f32, @floatFromInt(i)) - @ceil(radius);
						const y = @as(f32, @floatFromInt(j)) - @ceil(radius);
						const z = @as(f32, @floatFromInt(k)) - @ceil(radius);
						const squareDistance = (x*x + y*y + z*z);
						const squareMaxDistance = radius*radius;
						if(squareDistance > squareMaxDistance) continue;
					}
					{
						const x = pos[0] + @as(f32, @floatFromInt(i)) - radius;
						const y = pos[1] + @as(f32, @floatFromInt(j)) - radius;
						const z = pos[2] + @as(f32, @floatFromInt(k)) - radius;

						_ = self.place(.{@intFromFloat(x), @intFromFloat(y), @intFromFloat(z)}, block, 0);
					}
				}
			}
		}
	}
};

segments: List(Stem),

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *@This() {
	const self = arenaAllocator.create(@This());
	self.segments = .init(arenaAllocator);

	const segments = parameters.getChild("segments");

	for(segments.array.items) |segment| {
		const blocks = segment.getChild("blocks");
		self.segments.append(
			.{
				.height = segment.get(usize, "height", 0),
				.branchChance = segment.get(f32, "branchChance", 0.0),
				.branchSpacing = segment.get(u32, "branchSpacing", 0),
				.branchSpawnMode = BranchSpawnMode.fromString(segment.get([]const u8, "branchSpawnMode", "random")),
				.branchMaxCount = segment.get(u32, "branchMaxCount", 0),
				.branchMaxCountPerLevel = segment.get(u32, "branchMaxCountPerLevel", std.math.maxInt(u32)),
				.branchSegmentSeriesVariants = segment.getChild("branchSegmentSeriesVariants").clone(arenaAllocator),
				.leavesChance = segment.get(f32, "leavesChance", 0.0),
				.leavesBlobChance = segment.get(f32, "leavesBlobChance", 0.0),
				.leavesBlobRadius = segment.get(f32, "leavesBlobRadius", 0.0),
				.leavesBlobRadiusDelta = segment.get(f32, "leavesBlobRadiusDelta", 0.0),
				.branchPeak = segment.get(bool, "branchPeak", false),
				.mushroomChance = segment.get(f32, "mushroomChance", 0.0),
				.stemThickness = segment.get(usize, "stemThickness", 1),
				.blocks = .{
					.leaves = parseBlock(blocks.get([]const u8, "leaves", "cubyz:oak_leaves")),
					.wood = parseBlock(blocks.get([]const u8, "wood", "cubyz:oak_log")),
					.branch = parseBlock(blocks.get([]const u8, "branch", "cubyz:oak_branch")),
					.mushroom = parseBlock(blocks.get([]const u8, "mushroom", "cubyz:bolete")),
				},
			}
		);
	}

	return self;
}

pub fn getTotalHeight(self: *@This()) usize {
	var totalHeight: usize = 0;
	for(self.segments.items) |segment| {
		totalHeight += segment.height;
	}
	return totalHeight;
}

pub fn generate(self: *@This(), x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, _: bool) void {
	const totalHeight = self.getTotalHeight();

	if(z + @as(i32, @intCast(totalHeight)) >= caveMap.findTerrainChangeAbove(x, y, z))
		return;

	if(z > chunk.super.width) return;

	if(chunk.super.pos.voxelSize >= 2) {
		return;
	}
	const spawnAxis =  if(random.nextFloat(seed) < 0.5) Neighbor.dirPosX else Neighbor.dirPosY;
	var state = TreeState{.seed = seed, .chunk = chunk, .position = .{x, y, z}, .height = 0, .spawnAxis = spawnAxis, .alternateBranchSpacing = 0};

	for(self.segments.items) |segment| {
		segment.generate(&state);
	}
}