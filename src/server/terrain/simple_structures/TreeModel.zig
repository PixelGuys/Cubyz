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

pub fn ValueWithDelta(comptime T: type, comptime defaultValue: T, comptime defaultDelta: T) type {
	return struct {
		value: T,
		delta: T,

		pub fn initFromZon(element: ZonElement) @This() {
			if(element == .object) {
				return .{
					.value = element.get(T, "value", defaultValue),
					.delta = element.get(T, "delta", defaultDelta),
				};
			}
			return .{
				.value = element.as(T, defaultValue),
				.delta = defaultDelta,
			};
		}
	};
}

const LeavesOptions = struct {
	const SpawnMode = enum {
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

	spawnMode: ?SpawnMode,
	spawnChance: ?f32,
	radius: ?f32,
	radiusDelta: ?f32,
	randomOffsetDelta: ?f32,
	arcWidthOuter: ?f32,
	arcHeightOuter: ?f32,
	arcRadiusOuter: ?f32,
	arcZOffsetOuter: ?f32,
	arcWidthInner: ?f32,
	arcHeightInner: ?f32,
	arcRadiusInner: ?f32,
	arcZOffsetInner: ?f32,
	arcZOffset: ?f32,

	pub fn initFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *@This() {
		const self = allocator.create(@This());
		self.* = .{
			.spawnMode = if(zon.get(?[]const u8, "spawnMode", null)) |mode| SpawnMode.fromString(mode) else null,
			.spawnChance = zon.get(?f32, "spawnChance", null),
			.radius = zon.get(?f32, "radius", null),
			.radiusDelta = zon.get(?f32, "radiusDelta", null),
			.randomOffsetDelta = zon.get(?f32, "randomOffsetDelta", null),
			.arcWidthOuter = zon.get(?f32, "arcWidthOuter", null),
			.arcHeightOuter = zon.get(?f32, "arcHeightOuter", null),
			.arcRadiusOuter = zon.get(?f32, "arcRadiusOuter", null),
			.arcZOffsetOuter = zon.get(?f32, "arcZOffsetOuter", null),
			.arcWidthInner = zon.get(?f32, "arcWidthInner", null),
			.arcHeightInner = zon.get(?f32, "arcHeightInner", null),
			.arcRadiusInner = zon.get(?f32, "arcRadiusInner", null),
			.arcZOffsetInner = zon.get(?f32, "arcZOffsetInner", null),
			.arcZOffset = zon.get(?f32, "arcZOffset", null),
		};
		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		allocator.destroy(self);
	}
};

const Stem = struct {
	height: i32,
	heightDelta: f32,
	skipChance: f32,
	branchSpawnChance: f32,
	branchSpacing: u32,
	branchSpawnMode: BranchSpawnMode,
	branchMaxCount: u32,
	branchMaxCountPerLevel: u32,
	branchPeak: bool,
	branchSegmentSeriesVariants: List(*BranchSegment),

	leaves: *LeavesOptions,

	mushroomChance: f32,
	stemThickness: usize,
	blocks: Blocks,

	pub fn initFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *@This() {
		const blocks = zon.getChild("blocks");
		const branchSegmentsZon = zon.getChild("branchSegmentSeriesVariants").toSlice();
		var branchSegments: List(*BranchSegment) = .initCapacity(allocator, branchSegmentsZon.len);

		for(branchSegmentsZon) |branchSegment| {
			branchSegments.appendAssumeCapacity(BranchSegment.initFromZon(allocator, branchSegment));
		}
		const self = allocator.create(@This());

		self.* = .{
			.height = zon.get(i32, "height", 0),
			.heightDelta = zon.get(f32, "heightDelta", 0),
			.skipChance = zon.get(f32, "skipChance", 0),
			.branchSpawnChance = zon.get(f32, "branchSpawnChance", 0.0),
			.branchSpacing = zon.get(u32, "branchSpacing", 0),
			.branchSpawnMode = .fromString(zon.get([]const u8, "branchSpawnMode", "random")),
			.branchMaxCount = zon.get(u32, "branchMaxCount", std.math.maxInt(u32)),
			.branchMaxCountPerLevel = zon.get(u32, "branchMaxCountPerLevel", std.math.maxInt(u32)),
			.branchSegmentSeriesVariants = branchSegments,
			.branchPeak = zon.get(bool, "branchPeak", false),
			.leaves = .initFromZon(allocator, zon.getChild("leaves")),
			.mushroomChance = zon.get(f32, "mushroomChance", 0.0),
			.stemThickness = zon.get(usize, "stemThickness", 1),
			.blocks = .initFromZon(blocks),
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
		if(random.nextFloat(state.seed) < self.skipChance) return;

		var branchGenerator = BranchGenerator{
			.state = state,
			.blocks = self.blocks,
			.leaves = self.leaves,
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
						if(self.branchSpawnChance <= 0) continue;
						if(branchCount >= self.branchMaxCount) continue;
						if(random.nextFloat(state.seed) > self.branchSpawnChance) continue;

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
					if(self.branchSpawnChance <= 0) break :blk;
					if(branchCount >= self.branchMaxCount) break :blk;

					if(random.nextFloat(state.seed) < self.branchSpawnChance) {
						const isSuccess = @intFromBool(self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
					}
					if(random.nextFloat(state.seed) < self.branchSpawnChance) {
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

	pub fn initFromZon(zon: ZonElement) @This() {
		return .{
			.leaves = parseBlock(zon.get([]const u8, "leaves", "cubyz:air")),
			.wood = parseBlock(zon.get([]const u8, "wood", "cubyz:air")),
			.branch = parseBlock(zon.get([]const u8, "branch", "cubyz:air")),
			.mushroom = parseBlock(zon.get([]const u8, "mushroom", "cubyz:air")),
			.grass = parseBlock("cubyz:grass"),
		};
	}
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
	leaves: *LeavesOptions,

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
		const leavesSpawnChance = series.leaves.spawnChance orelse self.leaves.spawnChance orelse 0.0;

		if(leavesSpawnChance > 0 and random.nextFloat(self.state.seed) < leavesSpawnChance) {
			blockData = self.placeLeaves(position, series);
			blockData |= direction.reverse().bitMask();
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
	fn placeLeaves(self: *@This(), position: Vec3i, series: *BranchSegment) u16 {
		const leavesSpawnMode = series.leaves.spawnMode orelse self.leaves.spawnMode orelse return 0;
		const leavesRandomOffsetDelta = series.leaves.randomOffsetDelta orelse self.leaves.randomOffsetDelta orelse 0.0;

		const pos: Vec3f = .{
			@as(f32, @floatFromInt(position[0])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
			@as(f32, @floatFromInt(position[1])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
			@as(f32, @floatFromInt(position[2])) + (random.nextFloat(self.state.seed) - 0.5)*leavesRandomOffsetDelta,
		};

		switch(leavesSpawnMode) {
			.sphere, .half_sphere => {
				const sphereRadius = series.leaves.radius orelse self.leaves.radius orelse 0.0;
				const sphereRadiusDelta = series.leaves.radiusDelta orelse self.leaves.radiusDelta orelse 0.0;

				const radius = sphereRadius + (random.nextFloat(self.state.seed) - 0.5)*sphereRadiusDelta;

				if(radius < 0.5) return 0;

				const radiusInt: usize = @intFromFloat(@ceil(radius));

				for(0..radiusInt) |i| {
					for(0..radiusInt) |j| {
						for(0..radiusInt) |k| {
							{
								const distance = hypot3d(@as(f32, @floatFromInt(i)), @as(f32, @floatFromInt(j)), @as(f32, @floatFromInt(k)));
								if(distance > radius) continue;
							}
							for(0..2) |x| {
								for(0..2) |y| {
									for(0..2) |z| {
										const dx = @as(f32, @floatFromInt(x)) - 0.5;
										const dy = @as(f32, @floatFromInt(y)) - 0.5;
										const dz = @as(f32, @floatFromInt(z)) - 0.5;

										if(leavesSpawnMode == .half_sphere and dz < 0) continue;

										const loc: Vec3i = .{
											@intFromFloat(pos[0] + @as(f32, @floatFromInt(i))*std.math.sign(dx)),
											@intFromFloat(pos[1] + @as(f32, @floatFromInt(j))*std.math.sign(dy)),
											@intFromFloat(pos[2] + @as(f32, @floatFromInt(k))*std.math.sign(dz)),
										};
										_ = self.place(loc, self.blocks.leaves, 0);
									}
								}
							}
						}
					}
				}
				return (Neighbor.dirPosX.bitMask() |
					Neighbor.dirNegX.bitMask() |
					Neighbor.dirPosY.bitMask() |
					Neighbor.dirNegY.bitMask() |
					// Intentionally omitting down - it would look strange with arc leaves.
					Neighbor.dirUp.bitMask());
			},
			.arc => {
				const widthOuter = series.leaves.arcWidthOuter orelse self.leaves.arcWidthOuter orelse return 0.0;
				const heightOuter = series.leaves.arcHeightOuter orelse self.leaves.arcHeightOuter orelse 0.0;
				const radiusOuter = series.leaves.arcRadiusOuter orelse self.leaves.arcRadiusOuter orelse 0.0;
				const zOffsetOuter = series.leaves.arcZOffsetOuter orelse self.leaves.arcZOffsetOuter orelse 0.0;

				const widthInner = series.leaves.arcWidthInner orelse self.leaves.arcWidthInner orelse 0.0;
				const heightInner = series.leaves.arcHeightInner orelse self.leaves.arcHeightInner orelse 0.0;
				const radiusInner = series.leaves.arcRadiusInner orelse self.leaves.arcRadiusInner orelse 0.0;
				const zOffsetInner = series.leaves.arcZOffsetInner orelse self.leaves.arcZOffsetInner orelse 0.0;

				const zOffset = series.leaves.arcZOffset orelse self.leaves.arcZOffset orelse 0.0;

				if(radiusOuter <= 0.5) return 0;

				const radiusInt: usize = @intFromFloat(@ceil(radiusOuter));

				for(0..radiusInt) |i| {
					for(0..radiusInt) |j| {
						for(0..(radiusInt*2)) |k| {
							{
								const x = @as(f32, @floatFromInt(i));
								const y = @as(f32, @floatFromInt(j));
								const z = @as(f32, @floatFromInt(k)) - heightOuter;

								const distanceOuter = hypot3d(x/widthOuter, y/widthOuter, (z + zOffsetOuter)/heightOuter);
								const distanceInner = hypot3d(x/widthInner, y/widthInner, (z + zOffsetInner)/heightInner);
								const insideOuter = distanceOuter < radiusOuter;
								const outsideInner = distanceInner > radiusInner;
								if(!insideOuter or !outsideInner) continue;
							}
							for(0..2) |x| {
								for(0..2) |y| {
									const dx = @as(f32, @floatFromInt(x)) - 0.5;
									const dy = @as(f32, @floatFromInt(y)) - 0.5;

									const loc: Vec3i = .{
										@intFromFloat(pos[0] + @as(f32, @floatFromInt(i))*std.math.sign(dx)),
										@intFromFloat(pos[1] + @as(f32, @floatFromInt(j))*std.math.sign(dy)),
										@intFromFloat(pos[2] + (@as(f32, @floatFromInt(k)) - heightOuter + zOffset)),
									};
									_ = self.place(loc, self.blocks.leaves, 0);
								}
							}
						}
					}
				}
				return Neighbor.dirUp.bitMask();
			},
			.none => return 0,
		}
	}
};

fn hypot3d(x: f32, y: f32, z: f32) f32 {
	return std.math.sqrt(x*x + y*y + z*z);
}

const BranchSegment = struct {
	left: ?*BranchSegment,
	right: ?*BranchSegment,
	forward: ?*BranchSegment,
	backward: ?*BranchSegment,
	up: ?*BranchSegment,

	leaves: *LeavesOptions,

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

		self.leaves = LeavesOptions.initFromZon(allocator, series.getChild("leaves"));

		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		if(self.left) |left| left.deinit(allocator);
		if(self.right) |right| right.deinit(allocator);
		if(self.forward) |forward| forward.deinit(allocator);
		if(self.backward) |backward| backward.deinit(allocator);
		if(self.up) |up| up.deinit(allocator);

		self.leaves.deinit(allocator);

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
