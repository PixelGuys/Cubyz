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
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
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

const LeavesSpawnMode = enum {
	sphere,
	half_sphere,
	arc,
	none,

	fn fromString(string: []const u8) @This() {
		return std.meta.stringToEnum(@This(), string) orelse {
			std.log.err("Couldn't find leaves spawn mode {s}. Replacing it with none", .{string});
			return .none;
		};
	}
};

const Stem = struct {
	height: i32,
	heightDelta: f32,
	skipChance: f32,
	branchChance: f32,
	branchSpacing: u32,
	branchSpawnMode: BranchSpawnMode,
	branchMaxCount: u32,
	branchMaxCountPerLevel: u32,
	branchPeak: bool,
	branchSegmentSeriesVariants: List(*BranchSegment),

	leavesSpawnMode: LeavesSpawnMode,
	leavesSpawnChance: f32,
	leavesRadius: f32,
	leavesRadiusDelta: f32,
	leavesRandomOffsetDelta: f32,

	mushroomChance: f32,
	stemThickness: usize,
	blocks: Blocks,

	pub fn initFromZon(allocator: NeverFailingAllocator, segment: ZonElement) *@This() {
		const blocks = segment.getChild("blocks");
		const branchSegmentsZon = segment.getChild("branchSegmentSeriesVariants").toSlice();
		var branchSegments: List(*BranchSegment) = .initCapacity(allocator, branchSegmentsZon.len);

		for(branchSegmentsZon) |branchSegment| {
			branchSegments.appendAssumeCapacity(BranchSegment.initFromZon(allocator, branchSegment));
		}
		const self = allocator.create(@This());

		self.* = .{
			.height = segment.get(i32, "height", 0),
			.heightDelta = segment.get(f32, "heightDelta", 0),
			.skipChance = segment.get(f32, "skipChance", 0),
			.branchChance = segment.get(f32, "branchChance", 0.0),
			.branchSpacing = segment.get(u32, "branchSpacing", 0),
			.branchSpawnMode = BranchSpawnMode.fromString(segment.get([]const u8, "branchSpawnMode", "random")),
			.branchMaxCount = segment.get(u32, "branchMaxCount", std.math.maxInt(u32)),
			.branchMaxCountPerLevel = segment.get(u32, "branchMaxCountPerLevel", std.math.maxInt(u32)),
			.branchSegmentSeriesVariants = branchSegments,
			.leavesSpawnMode = LeavesSpawnMode.fromString(segment.get([]const u8, "leavesSpawnMode", "none")),
			.leavesSpawnChance = segment.get(f32, "leavesSpawnChance", 0.0),
			.leavesRadius = segment.get(f32, "leavesRadius", 0.0),
			.leavesRadiusDelta = segment.get(f32, "leavesRadiusDelta", 0.0),
			.leavesRandomOffsetDelta = segment.get(f32, "leavesRandomOffsetDelta", 0.0),
			.branchPeak = segment.get(bool, "branchPeak", false),
			.mushroomChance = segment.get(f32, "mushroomChance", 0.0),
			.stemThickness = segment.get(usize, "stemThickness", 1),
			.blocks = .{
				.leaves = parseBlock(blocks.get([]const u8, "leaves", "cubyz:air")),
				.wood = parseBlock(blocks.get([]const u8, "wood", "cubyz:air")),
				.branch = parseBlock(blocks.get([]const u8, "branch", "cubyz:air")),
				.mushroom = parseBlock(blocks.get([]const u8, "mushroom", "cubyz:air")),
				.grass = parseBlock("cubyz:grass"),
			},
		};

		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		for(self.branchSegmentSeriesVariants.items) |branchSegment| {
			branchSegment.deinit(allocator);
		}
		self.branchSegmentSeriesVariants.deinit(allocator);
		allocator.destroy(self);
	}

	pub fn generate(self: @This(), state: *TreeState) void {
		if(self.height <= 0) return;
		if(self.stemThickness == 0) return;

		var branchGenerator = BranchGenerator{
			.state = state,
			.blocks = self.blocks,
			.leavesSpawnMode = self.leavesSpawnMode,
			.leavesSpawnChance = self.leavesSpawnChance,
			.leavesRadius = self.leavesRadius,
			.leavesRadiusDelta = self.leavesRadiusDelta,
			.leavesRandomOffsetDelta = self.leavesRandomOffsetDelta,
		};

		var branchCount: u32 = 0;
		var branchCountThisLevel: u32 = 0;

		const horizontal = [_]Neighbor{.dirPosX, .dirNegX, .dirPosY, .dirNegY};

		const screwIsRight = switch(self.branchSpawnMode) {
			.screw_right => true,
			.screw_left => false,
			.screw_random => random.nextFloat(state.seed) < 0.5,
			else => false,
		};

		const effectiveHeight = self.height + @as(i32, @intFromFloat((random.nextFloat(state.seed) - 0.5)*self.heightDelta));
		if(effectiveHeight <= 0) return;

		for(0..@intCast(effectiveHeight)) |_| {
			switch(self.branchSpawnMode) {
				.random => {
					for(horizontal) |direction| {
						if(branchCountThisLevel >= self.branchMaxCountPerLevel) continue;
						if(self.branchChance <= 0) continue;
						if(branchCount >= self.branchMaxCount) continue;
						if(random.nextFloat(state.seed) > self.branchChance) continue;

						const isSuccess: u32 = @intFromBool(self.placeBranch(state, &branchGenerator, direction, state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
						continue;
					}
				},
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
			}
			self.generateStem(state);

			state.position[2] += 1;
			state.height += 1;
			branchCountThisLevel = 0;
		}
		if(self.branchPeak) {
			_ = self.placeBranch(state, &branchGenerator, Neighbor.dirUp, .{state.position[0], state.position[1], state.position[2] - 1});
		}
	}
	fn generateStem(self: @This(), state: *TreeState) void {
		for(0..self.stemThickness) |x| {
			for(0..self.stemThickness) |y| {
				const centerOffset = @as(i32, @intCast(self.stemThickness/2));
				const currentPosition: Vec3i = .{state.position[0] + @as(i32, @intCast(x)) - centerOffset, state.position[1] + @as(i32, @intCast(y)) - centerOffset, state.position[2]};

				self.placeBlock(state, currentPosition, self.blocks.wood);

				if(self.mushroomChance < 0) continue;

				var xDirection: ?Neighbor = null;

				if(x == (self.stemThickness - 1)) {
					xDirection = Neighbor.dirPosX;
				} else if(x == 0) {
					xDirection = Neighbor.dirNegX;
				}
				if(xDirection) |direction| {
					if(random.nextFloat(state.seed) < self.mushroomChance) {
						self.placeMushroom(state, currentPosition, direction);
					}
				}

				var yDirection: ?Neighbor = null;

				if(y == (self.stemThickness - 1)) {
					yDirection = Neighbor.dirPosY;
				} else if(y == 0) {
					yDirection = Neighbor.dirNegY;
				}
				if(yDirection) |direction| {
					if(random.nextFloat(state.seed) < self.mushroomChance) {
						self.placeMushroom(state, currentPosition, direction);
					}
				}
			}
		}
	}
	fn placeBlock(_: @This(), state: *TreeState, position: Vec3i, block: Block) void {
		if(!state.chunk.liesInChunk(position[0], position[1], position[2])) return;
		state.chunk.updateBlockInGeneration(position[0], position[1], position[2], block);
	}
	fn placeBranch(self: @This(), state: *TreeState, branchGenerator: *BranchGenerator, direction: Neighbor, position: Vec3i) bool {
		if(self.branchSegmentSeriesVariants.items.len == 0) return false;

		const branchVariantIndex = random.nextInt(usize, state.seed)%self.branchSegmentSeriesVariants.items.len;
		const branchSeries = self.branchSegmentSeriesVariants.items[branchVariantIndex];

		return branchGenerator.generate(direction, position + direction.relPos(), branchSeries);
	}
	fn placeMushroom(self: @This(), state: *TreeState, position: Vec3i, direction: Neighbor) void {
		const placePosition = position + direction.relPos();

		if(!state.chunk.liesInChunk(placePosition[0], placePosition[1], placePosition[2])) return;
		if(state.chunk.getBlock(placePosition[0], placePosition[1], placePosition[2]).typ != 0) return;

		const under = placePosition + Neighbor.dirDown.relPos();
		var center = false;

		if(state.chunk.liesInChunk(under[0], under[1], under[2])) {
			const underBlock = state.chunk.getBlock(under[0], under[1], under[2]);
			center = (underBlock.typ == self.blocks.grass.typ) and (random.nextFloat(state.seed) < 0.5);
		}

		const blockData = self.directionToMushroomData(direction, center);
		const blockWithData = Block{.typ = self.blocks.mushroom.typ, .data = blockData};

		_ = state.chunk.updateBlockInGeneration(placePosition[0], placePosition[1], placePosition[2], blockWithData);
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
	grass: Block,
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

	leavesSpawnMode: LeavesSpawnMode,
	leavesSpawnChance: f32,
	leavesRadius: f32,
	leavesRadiusDelta: f32,
	leavesRandomOffsetDelta: f32,

	pub fn generate(self: *@This(), direction: Neighbor, position: Vec3i, series: *BranchSegment) bool {
		const horizontalDirection = if(direction == Neighbor.dirUp) Neighbor.dirPosX else direction;
		return junction(self, horizontalDirection, direction, position, series);
	}
	fn junction(self: *@This(), horizontalDirection: Neighbor, direction: Neighbor, position: Vec3i, series: *BranchSegment) bool {
		if(!self.isAirOrLeaves(position)) return false;

		const leftSeries = series.left;
		const rightSeries = series.right;
		const forwardSeries = series.forward;
		const backwardSeries = series.backward;
		const upSeries = series.up;

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

		if(leftSeries) |nextSeries| {
			isLeftSuccess = self.junction(left, left, position + left.relPos(), nextSeries);
		}

		if(rightSeries) |nextSeries| {
			isRightSuccess = self.junction(right, right, position + right.relPos(), nextSeries);
		}

		if(forwardSeries) |nextSeries| {
			isForwardSuccess = self.junction(forward, forward, position + forward.relPos(), nextSeries);
		}

		if(backwardSeries) |nextSeries| {
			isBackwardSuccess = self.junction(backward, backward, position + backward.relPos(), nextSeries);
		}

		if(upSeries) |nextSeries| {
			isUpSuccess = self.junction(forward, up, position + up.relPos(), nextSeries);
		}

		var blockData: u16 = 0;
		const leavesSpawnChance = series.leavesSpawnChance orelse self.leavesSpawnChance;

		if(leavesSpawnChance > 0 and random.nextFloat(self.state.seed) < leavesSpawnChance) {
			self.placeLeaves(position, series);
			blockData = (Neighbor.dirPosX.bitMask() |
				Neighbor.dirNegX.bitMask() |
				Neighbor.dirPosY.bitMask() |
				Neighbor.dirNegY.bitMask() |
				// Intentionally omitting down - it would look strange with arc leaves.
				Neighbor.dirUp.bitMask());
		} else {
			blockData |= direction.reverse().bitMask();
			if(isLeftSuccess) blockData |= left.bitMask();
			if(isRightSuccess) blockData |= right.bitMask();
			if(isForwardSuccess) blockData |= forward.bitMask();
			if(isBackwardSuccess) blockData |= backward.bitMask();
			if(isUpSuccess) blockData |= up.bitMask();
		}

		return self.placeBranch(position, self.blocks.branch, blockData);
	}
	fn place(self: *@This(), position: Vec3i, block: Block, data: u16) bool {
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;
		if(self.state.chunk.getBlock(position[0], position[1], position[2]).typ != 0) return false;

		const blockWithData = Block{.typ = block.typ, .data = data};
		self.state.chunk.updateBlockInGeneration(position[0], position[1], position[2], blockWithData);
		return true;
	}
	fn isAirOrLeaves(self: *@This(), position: Vec3i) bool {
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;

		const currentBlock = self.state.chunk.getBlock(position[0], position[1], position[2]);
		return currentBlock.typ == 0 or currentBlock.typ == self.blocks.leaves.typ;
	}
	fn placeBranch(self: *@This(), position: Vec3i, block: Block, data: u16) bool {
		if(!self.state.chunk.liesInChunk(position[0], position[1], position[2])) return true;

		const blockWithData = Block{.typ = block.typ, .data = data};
		self.state.chunk.updateBlockInGeneration(position[0], position[1], position[2], blockWithData);
		return true;
	}
	fn placeLeaves(self: *@This(), position: Vec3i, series: *BranchSegment) void {
		const leavesSpawnMode = series.leavesSpawnMode orelse self.leavesSpawnMode;
		if(leavesSpawnMode == LeavesSpawnMode.none) return;

		const blobRadius = series.leavesRadius orelse self.leavesRadius;
		const blobRadiusDelta = series.leavesRadiusDelta orelse self.leavesRadiusDelta;

		const radius = blobRadius + (random.nextFloat(self.state.seed) - 0.5)*blobRadiusDelta;
		const leavesRandomOffsetDelta = series.leavesRandomOffsetDelta orelse self.leavesRandomOffsetDelta;

		const pos: Vec3f = .{
			@as(f32, @floatFromInt(position[0])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
			@as(f32, @floatFromInt(position[1])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
			@as(f32, @floatFromInt(position[2])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
		};

		if(radius < 1.0) return;

		const radiusInt: i32 = @intFromFloat(@ceil(radius));
		const diameterInt: usize = 2*@as(usize, @intCast(radiusInt));

		const zStart: usize = if(leavesSpawnMode == .half_sphere) @intCast(radiusInt) else 0;

		for(0..diameterInt) |i| {
			for(0..diameterInt) |j| {
				for(zStart..diameterInt) |k| {
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

						_ = self.place(.{@intFromFloat(x), @intFromFloat(y), @intFromFloat(z)}, self.blocks.leaves, 0);
					}
				}
			}
		}
	}
};

const BranchSegment = struct {
	left: ?*BranchSegment,
	right: ?*BranchSegment,
	forward: ?*BranchSegment,
	backward: ?*BranchSegment,
	up: ?*BranchSegment,

	leavesSpawnMode: ?LeavesSpawnMode,
	leavesSpawnChance: ?f32,
	leavesRadius: ?f32,
	leavesRadiusDelta: ?f32,
	leavesRandomOffsetDelta: ?f32,

	pub fn initFromZon(allocator: NeverFailingAllocator, series: ZonElement) *@This() {
		const self = allocator.create(@This());

		const left = series.getChild("left");
		const right = series.getChild("right");
		const forward = series.getChild("forward");
		const backward = series.getChild("backward");
		const up = series.getChild("up");

		self.left = if(left.isNull()) null else .initFromZon(allocator, left);
		self.right = if(right.isNull()) null else .initFromZon(allocator, right);
		self.forward = if(forward.isNull()) null else .initFromZon(allocator, forward);
		self.backward = if(backward.isNull()) null else .initFromZon(allocator, backward);
		self.up = if(up.isNull()) null else .initFromZon(allocator, up);

		self.leavesSpawnMode = if(series.get(?[]const u8, "leavesSpawnMode", null)) |mode| LeavesSpawnMode.fromString(mode) else null;
		self.leavesSpawnChance = series.get(?f32, "leavesSpawnChance", null);
		self.leavesRadius = series.get(?f32, "leavesRadius", null);
		self.leavesRadiusDelta = series.get(?f32, "leavesRadiusDelta", null);
		self.leavesRandomOffsetDelta = series.get(?f32, "leavesRandomOffsetDelta", null);

		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		if(self.left) |left| left.deinit(allocator);
		if(self.right) |right| right.deinit(allocator);
		if(self.forward) |forward| forward.deinit(allocator);
		if(self.backward) |backward| backward.deinit(allocator);
		if(self.up) |up| up.deinit(allocator);

		allocator.free(self.*);
	}
};

segments: List(*Stem),
heightOffset: i32,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *@This() {
	const self = arenaAllocator.create(@This());
	self.segments = .init(arenaAllocator);
	self.heightOffset = parameters.get(i32, "heightOffset", 0);

	const segments = parameters.getChild("segments");

	for(segments.array.items) |segment| {
		self.segments.append(.initFromZon(arenaAllocator, segment));
	}

	return self;
}

pub fn getTotalHeight(self: *@This()) i32 {
	var totalHeight: i32 = 0;
	for(self.segments.items) |segment| {
		totalHeight += segment.height;
	}
	return totalHeight;
}

pub fn generate(self: *@This(), x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, _: bool) void {
	const totalHeight = self.getTotalHeight();

	if(z + totalHeight >= caveMap.findTerrainChangeAbove(x, y, z))
		return;

	if(z > chunk.super.width) return;

	if(chunk.super.pos.voxelSize >= 2) {
		return;
	}
	const spawnAxis = if(random.nextFloat(seed) < 0.5) Neighbor.dirPosX else Neighbor.dirPosY;
	var state = TreeState{.seed = seed, .chunk = chunk, .position = .{x, y, z + self.heightOffset}, .height = 0, .spawnAxis = spawnAxis, .alternateBranchSpacing = 0};

	for(self.segments.items) |segment| {
		segment.generate(&state);
	}
}
