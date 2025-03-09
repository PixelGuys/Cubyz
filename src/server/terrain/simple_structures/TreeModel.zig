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

const BranchesOptions = struct {
	const SpawnMode = enum {
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

	spawnChance: f32,
	spacing: u32,
	spawnMode: SpawnMode,
	maxCount: u32,
	maxCountPerLevel: u32,
	isPeak: bool,
	segmentSeries: List(*BranchSegment),

	pub fn initFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *@This() {
		const self = allocator.create(@This());
		const segmentSeriesZon = zon.getChild("segmentSeries").toSlice();
		var segmentSeries: List(*BranchSegment) = .initCapacity(allocator, segmentSeriesZon.len);

		for(segmentSeriesZon) |segment| {
			segmentSeries.appendAssumeCapacity(BranchSegment.initFromZon(allocator, segment));
		}
		self.* = .{
			.spawnChance = zon.get(f32, "spawnChance", 0.0),
			.spacing = zon.get(u32, "spacing", 0),
			.spawnMode = .fromString(zon.get([]const u8, "spawnMode", "random")),
			.maxCount = zon.get(u32, "maxCount", std.math.maxInt(u32)),
			.maxCountPerLevel = zon.get(u32, "maxCountPerLevel", std.math.maxInt(u32)),
			.isPeak = zon.get(bool, "isPeak", false),
			.segmentSeries = segmentSeries,
		};
		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		for(self.segmentSeries.items) |segment| {
			segment.deinit(allocator);
		}
		self.segmentSeries.deinit(allocator);
		allocator.destroy(self);
	}
};

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
	thickness: usize,
	skipChance: f32,

	branches: *BranchesOptions,
	leaves: *LeavesOptions,

	mushroomChance: f32,
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
			.branches = .initFromZon(allocator, zon.getChild("branches")),
			.leaves = .initFromZon(allocator, zon.getChild("leaves")),
			.mushroomChance = zon.get(f32, "mushroomChance", 0.0),
			.thickness = zon.get(usize, "thickness", 1),
			.blocks = .initFromZon(blocks),
		};

		return self;
	}

	pub fn deinit(self: *@This(), allocator: NeverFailingAllocator) void {
		self.branches.deinit(allocator);
		self.leaves.deinit(allocator);
		allocator.destroy(self);
	}

	pub fn generate(self: @This(), state: *TreeState) void {
		if(self.height <= 0) return;
		if(self.thickness == 0) return;
		if(random.nextFloat(state.seed) < self.skipChance) return;

		const effectiveHeight = self.height + @as(i32, @intFromFloat((random.nextFloat(state.seed) - 0.5)*self.heightDelta));
		if(effectiveHeight <= 0) return;

		var branchGenerator = BranchGenerator{
			.state = state,
			.blocks = self.blocks,
			.leaves = self.leaves,
		};

		const horizontal = [_]Neighbor{.dirPosX, .dirNegX, .dirPosY, .dirNegY};

		const screwIsRight = switch(self.branches.spawnMode) {
			.screw_right => true,
			.screw_left => false,
			.screw_random => random.nextFloat(state.seed) < 0.5,
			else => false,
		};

		var branchCount: u32 = 0;
		var branchCountThisLevel: u32 = 0;

		for(0..@intCast(effectiveHeight)) |_| {
			switch(self.branches.spawnMode) {
				.random => {
					for(horizontal) |direction| {
						if(self.branches.spawnChance <= 0) continue;
						if(branchCountThisLevel >= self.branches.maxCountPerLevel) continue;
						if(branchCount >= self.branches.maxCount) continue;
						if(random.nextFloat(state.seed) > self.branches.spawnChance) continue;

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
					if(state.alternateBranchSpacing >= self.branches.spacing) {
						_ = self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position);
						_ = self.placeBranch(state, &branchGenerator, state.spawnAxis.reverse(), state.position);
						state.spawnAxis = state.spawnAxis.right();
						state.alternateBranchSpacing = 0;
					} else {
						state.alternateBranchSpacing += 1;
					}
				},
				.alternating_random => blk: {
					if(self.branches.spawnChance <= 0) break :blk;
					if(branchCountThisLevel >= self.branches.maxCountPerLevel) break :blk;
					if(branchCount >= self.branches.maxCount) break :blk;

					if(random.nextFloat(state.seed) < self.branches.spawnChance) {
						const isSuccess = @intFromBool(self.placeBranch(state, &branchGenerator, state.spawnAxis, state.position));
						branchCount += isSuccess;
						branchCountThisLevel += isSuccess;
					}
					if(random.nextFloat(state.seed) < self.branches.spawnChance) {
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
		if(self.branches.isPeak) {
			_ = self.placeBranch(state, &branchGenerator, Neighbor.dirUp, .{state.position[0], state.position[1], state.position[2] - 1});
		}
	}
	fn generateStem(self: @This(), state: *TreeState) void {
		for(0..self.thickness) |x| {
			for(0..self.thickness) |y| {
				const centerOffset = @as(i32, @intCast(self.thickness/2));
				const currentPosition: Vec3i = .{state.position[0] + @as(i32, @intCast(x)) - centerOffset, state.position[1] + @as(i32, @intCast(y)) - centerOffset, state.position[2]};

				self.placeBlock(state, currentPosition, self.blocks.wood);

				if(self.mushroomChance < 0) continue;

				var xDirection: ?Neighbor = null;

				if(x == (self.thickness - 1)) {
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

				if(y == (self.thickness - 1)) {
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
		if(self.branches.segmentSeries.items.len == 0) return false;

		const index = random.nextInt(usize, state.seed)%self.branches.segmentSeries.items.len;
		const series = self.branches.segmentSeries.items[index];

		return branchGenerator.generate(direction, position + direction.relPos(), series);
	}
	fn placeMushroom(self: @This(), state: *TreeState, position: Vec3i, direction: Neighbor) void {
		const pos = position + direction.relPos();

		if(!state.chunk.liesInChunk(pos[0], pos[1], pos[2])) return;
		if(state.chunk.getBlock(pos[0], pos[1], pos[2]).typ != 0) return;

		const under = pos + Neighbor.dirDown.relPos();
		var center = false;

		if(state.chunk.liesInChunk(under[0], under[1], under[2])) {
			const underBlock = state.chunk.getBlock(under[0], under[1], under[2]);
			center = (underBlock.typ == self.blocks.grass.typ) and (random.nextFloat(state.seed) < 0.5);
		}

		const data = self.directionToMushroomData(direction, center);
		const block = Block{.typ = self.blocks.mushroom.typ, .data = data};

		_ = state.chunk.updateBlockInGeneration(pos[0], pos[1], pos[2], block);
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

		if(series.left) |nextSeries| {
			isLeftSuccess = self.junction(left, left, position + left.relPos(), nextSeries);
		}

		if(series.right) |nextSeries| {
			isRightSuccess = self.junction(right, right, position + right.relPos(), nextSeries);
		}

		if(series.forward) |nextSeries| {
			isForwardSuccess = self.junction(forward, forward, position + forward.relPos(), nextSeries);
		}

		if(series.backward) |nextSeries| {
			isBackwardSuccess = self.junction(backward, backward, position + backward.relPos(), nextSeries);
		}

		if(series.up) |nextSeries| {
			isUpSuccess = self.junction(forward, up, position + up.relPos(), nextSeries);
		}

		var blockData: u16 = 0;
		const leavesSpawnChance = series.leaves.spawnChance orelse self.leaves.spawnChance orelse 0.0;

		if(leavesSpawnChance > 0 and random.nextFloat(self.state.seed) < leavesSpawnChance) {
			blockData = self.placeLeaves(position, series);
		} else {
			if(isLeftSuccess) blockData |= left.bitMask();
			if(isRightSuccess) blockData |= right.bitMask();
			if(isForwardSuccess) blockData |= forward.bitMask();
			if(isBackwardSuccess) blockData |= backward.bitMask();
			if(isUpSuccess) blockData |= up.bitMask();
		}
		blockData |= direction.reverse().bitMask();

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
		const spawnMode = series.leaves.spawnMode orelse self.leaves.spawnMode orelse return 0;
		const randomOffsetDelta = series.leaves.randomOffsetDelta orelse self.leaves.randomOffsetDelta orelse 0.0;

		const pos: Vec3f = .{
			@as(f32, @floatFromInt(position[0])) + (random.nextFloat(self.state.seed) - 0.5)*randomOffsetDelta,
			@as(f32, @floatFromInt(position[1])) + (random.nextFloat(self.state.seed) - 0.5)*randomOffsetDelta,
			@as(f32, @floatFromInt(position[2])) + (random.nextFloat(self.state.seed) - 0.5)*randomOffsetDelta,
		};

		switch(spawnMode) {
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

										if(spawnMode == .half_sphere and dz < 0) continue;

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

	if(chunk.super.pos.voxelSize >= 4) {
		return;
	}
	const spawnAxis = if(random.nextFloat(seed) < 0.5) Neighbor.dirPosX else Neighbor.dirPosY;
	var state = TreeState{.seed = seed, .chunk = chunk, .position = .{x, y, z + self.heightOffset}, .height = 0, .spawnAxis = spawnAxis, .alternateBranchSpacing = 0};

	for(self.segments.items) |segment| {
		segment.generate(&state);
	}
}
