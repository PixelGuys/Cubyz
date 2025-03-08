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

const Stem = struct {
	height: usize,
	branchChance: f32,
	branchMaxCount: u32,
	branchMaxCountPerLevel: u32,
	branchSegmentSeriesVariants: ZonElement,
	leavesChance: f32,
	leavesBlobChance: f32,
	mushroomChance: f32,
	blocks: Blocks,

	pub fn generate(self: @This(), state: *TreeState) void {
		if(self.height == 0) return;

		var branchGenerator = BranchGenerator{
			.state = state,
			.blocks = self.blocks,
			.leavesChance = self.leavesChance,
			.leavesBlobChance = self.leavesBlobChance};

		var branchCount: u32 = 0;
		var branchCountThisLevel: u32 = 0;

		const horizontal = [_]Neighbor{.dirPosX, .dirNegX, .dirPosY, .dirNegY};

		for(0..self.height) |_| {
			for(horizontal) |direction| {
				if(self.mushroomChance > 0 and random.nextFloat(state.seed) < self.mushroomChance) {
					const center = (state.height == 0) and (random.nextFloat(state.seed) < 0.5);
					self.placeMushroom(state, state.position + direction.relPos(), direction, center);
					continue;
				}
				if(branchCountThisLevel >= self.branchMaxCountPerLevel) continue;
				if(self.branchChance <= 0) continue;
				if(branchCount >= self.branchMaxCount) continue;

				const isSuccess: u32 = @intFromBool(self.placeBranch(state, &branchGenerator, direction, state.position));
				branchCount += isSuccess;
				branchCountThisLevel += isSuccess;
				continue;
			}
			self.placeBlock(state, state.position, self.blocks.wood);

			state.position[2] += 1;
			state.height += 1;
			branchCountThisLevel = 0;
		}
	}
	fn placeBlock(_: @This(), state: *TreeState, position: Vec3i, block: Block) void {
		if(!state.chunk.liesInChunk(position[0], position[1], position[2])) return;
		state.chunk.updateBlockIfDegradable(position[0], position[1], position[2], block);
	}
	fn placeBranch(self: @This(), state: *TreeState, branchGenerator: *BranchGenerator, direction: Neighbor, position: Vec3i) bool {
		if(self.branchSegmentSeriesVariants.isNull()) return false;
		if(random.nextFloat(state.seed) > self.branchChance) return false;

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
	top: Block,
	branch: Block,
	mushroom: Block,
};

const TreeState = struct {
	seed: *u64,
	chunk: *ServerChunk,
	position: Vec3i,
	height: usize,
};

const BranchGenerator = struct {
	state: *TreeState,
	blocks: Blocks,
	leavesChance: f32,
	leavesBlobChance: f32,

	pub fn generate(self: *@This(), direction: Neighbor, position: Vec3i, series: ZonElement) bool {
		return junction(self, direction, position, series);
	}
	fn junction(self: *@This(), direction: Neighbor, position: Vec3i, series: ZonElement) bool {
		var leftSeries = series.getChild("left");
		var rightSeries = series.getChild("right");
		var forwardSeries = series.getChild("forward");

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

		if(!leftSeries.isNull()) {
			isLeftSuccess = self.junction(left, position + left.relPos(), leftSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isLeftSuccess = self.place(position + left.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!rightSeries.isNull()){
			isRightSuccess = self.junction(right, position + right.relPos(), rightSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isRightSuccess = self.place(position + right.relPos(), self.blocks.leaves, 0);
			}
		}

		if(!forwardSeries.isNull()) {
			isForwardSuccess = self.junction(direction, position + direction.relPos(), forwardSeries);
		} else {
			if(self.leavesChance > 0 and random.nextFloat(self.state.seed) < self.leavesChance) {
				isForwardSuccess = self.place(position + forward.relPos(), self.blocks.leaves, 0);
			}
		}
		isTopSuccess = self.place(position + up.relPos(), self.blocks.leaves, 0);

		const isEnd = leftSeries.isNull() and rightSeries.isNull() and forwardSeries.isNull();

		if(isEnd and self.leavesBlobChance > 0 and random.nextFloat(self.state.seed) < self.leavesBlobChance) {
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
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;

		const blockWithData = Block{.typ = block.typ, .data = data};
		return self.state.chunk.updateBlockIfAir(position[0], position[1], position[2], blockWithData);
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
				.branchMaxCount = segment.get(u32, "branchMaxCount", 0),
				.branchMaxCountPerLevel = segment.get(u32, "branchMaxCountPerLevel", std.math.maxInt(u32)),
				.branchSegmentSeriesVariants = segment.getChild("branchSegmentSeriesVariants").clone(arenaAllocator),
				.leavesChance = segment.get(f32, "leavesChance", 0.0),
				.leavesBlobChance = segment.get(f32, "leavesBlobChance", 0.0),
				.mushroomChance = segment.get(f32, "mushroomChance", 0.0),
				.blocks = .{
					.leaves = parseBlock(blocks.get([]const u8, "leaves", "cubyz:oak_leaves")),
					.wood = parseBlock(blocks.get([]const u8, "wood", "cubyz:oak_log")),
					.top = parseBlock(blocks.get([]const u8, "top", "cubyz:oak_top")),
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
	var state = TreeState{.seed = seed, .chunk = chunk, .position = .{x, y, z}, .height = 0};

	for(self.segments.items) |segment| {
		segment.generate(&state);
	}
}