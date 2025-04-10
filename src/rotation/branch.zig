const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const Degrees = rotation.Degrees;
const RotationMode = rotation.RotationMode;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const dependsOnNeighbors = true;
var branchModels: std.HashMap(HashMapKey, ModelIndex, HashMapKey, std.hash_map.default_max_load_percentage) = undefined;
const HashMapKey = struct {
	radius: u16,
	shellModelId: []const u8,
	textureSlotOffset: u32,

	pub fn hash(_: HashMapKey, val: HashMapKey) u64 {
		var hasher = std.hash.Wyhash.init(0);
		std.hash.autoHashStrat(&hasher, val, .DeepRecursive);
		return hasher.final();
	}
	pub fn eql(_: HashMapKey, val1: HashMapKey, val2: HashMapKey) bool {
		if(val1.radius != val2.radius) return false;
		if(val1.textureSlotOffset != val2.textureSlotOffset) return false;
		return std.mem.eql(u8, val1.shellModelId, val2.shellModelId);
	}
};
const BranchData = packed struct(u6) {
	enabledConnections: u6,

	pub inline fn init(blockData: u16) BranchData {
		return .{.enabledConnections = @truncate(blockData)};
	}

	pub inline fn isConnected(self: @This(), neighbor: Neighbor) bool {
		return (self.enabledConnections & Neighbor.bitMask(neighbor)) != 0;
	}

	pub inline fn setConnection(self: *@This(), neighbor: Neighbor, value: bool) void {
		if(value) {
			self.enabledConnections |= Neighbor.bitMask(neighbor);
		} else {
			self.enabledConnections &= ~Neighbor.bitMask(neighbor);
		}
	}
};

pub fn init() void {
	branchModels = .initContext(main.globalAllocator.allocator, undefined);
}

pub fn deinit() void {
	branchModels.deinit();
}

pub fn reset() void {
	branchModels.clearRetainingCapacity();
}

const Direction = enum(u2) {
	negYDir = 0,
	posXDir = 1,
	posYDir = 2,
	negXDir = 3,
};

const Pattern = union(enum) {
	dot: void,
	halfLine: struct {
		dir: Direction,
	},
	line: struct {
		dir: Direction,
	},
	bend: struct {
		dir: Direction,
	},
	intersection: struct {
		dir: Direction,
	},
	cross: void,
};

fn rotateQuad(originalCorners: [4]Vec2f, pattern: Pattern, min: f32, max: f32, side: Neighbor, textureSlotOffset: u32) main.models.QuadInfo {
	var corners: [4]Vec2f = originalCorners;

	switch(pattern) {
		.dot, .cross => {},
		inline else => |typ| {
			const angle: f32 = @as(f32, @floatFromInt(@intFromEnum(typ.dir)))*std.math.pi/2.0;
			corners = .{
				vec.rotate2d(originalCorners[0], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[1], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[2], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[3], angle, @splat(0.5)),
			};
		},
	}

	const offX: f32 = @floatFromInt(@intFromBool(@reduce(.Add, side.textureX()) < 0));
	const offY: f32 = @floatFromInt(@intFromBool(@reduce(.Add, side.textureY()) < 0));

	const corners3d = .{
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[0][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[0][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[1][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[1][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[2][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[2][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(corners[3][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(corners[3][1] - offY)),
	};

	var offset: Vec3f = .{0.0, 0.0, 0.0};
	offset[@intFromEnum(side.vectorComponent())] = if(side.isPositive()) max else min;

	const res: main.models.QuadInfo = .{
		.corners = .{
			corners3d[0] + offset,
			corners3d[1] + offset,
			corners3d[2] + offset,
			corners3d[3] + offset,
		},
		.cornerUV = originalCorners,
		.normal = @floatFromInt(side.relPos()),
		.textureSlot = textureSlotOffset + @intFromEnum(pattern),
	};

	return res;
}

fn addQuads(pattern: Pattern, side: Neighbor, radius: f32, out: *main.List(main.models.QuadInfo), textureSlotOffset: u32) void {
	const min: f32 = (8.0 - radius)/16.0;
	const max: f32 = (8.0 + radius)/16.0;
	switch(pattern) {
		.dot => {
			out.append(rotateQuad(.{
				.{min, min},
				.{min, max},
				.{max, min},
				.{max, max},
			}, pattern, min, max, side, textureSlotOffset));
		},
		.halfLine => {
			out.append(rotateQuad(.{
				.{min, 0.0},
				.{min, max},
				.{max, 0.0},
				.{max, max},
			}, pattern, min, max, side, textureSlotOffset));
		},
		.line => {
			out.append(rotateQuad(.{
				.{min, 0.0},
				.{min, 1.0},
				.{max, 0.0},
				.{max, 1.0},
			}, pattern, min, max, side, textureSlotOffset));
		},
		.bend => {
			out.append(rotateQuad(.{
				.{0.0, 0.0},
				.{0.0, max},
				.{max, 0.0},
				.{max, max},
			}, pattern, min, max, side, textureSlotOffset));
		},
		.intersection => {
			out.append(rotateQuad(.{
				.{0.0, 0.0},
				.{0.0, max},
				.{1.0, 0.0},
				.{1.0, max},
			}, pattern, min, max, side, textureSlotOffset));
		},
		.cross => {
			out.append(rotateQuad(.{
				.{0.0, 0.0},
				.{0.0, 1.0},
				.{1.0, 0.0},
				.{1.0, 1.0},
			}, pattern, min, max, side, textureSlotOffset));
		},
	}
}

fn getPattern(data: BranchData, side: Neighbor) ?Pattern {
	const posX = Neighbor.fromRelPos(side.textureX()).?;
	const negX = Neighbor.fromRelPos(side.textureX()).?.reverse();
	const posY = Neighbor.fromRelPos(side.textureY()).?;
	const negY = Neighbor.fromRelPos(side.textureY()).?.reverse();

	const connectedPosX = data.isConnected(posX);
	const connectedNegX = data.isConnected(negX);
	const connectedPosY = data.isConnected(posY);
	const connectedNegY = data.isConnected(negY);

	const count: u6 = @as(u6, @intFromBool(connectedPosX)) + @as(u6, @intFromBool(connectedNegX)) + @as(u6, @intFromBool(connectedPosY)) + @as(u6, @intFromBool(connectedNegY));

	return switch(count) {
		0 => {
			if(data.isConnected(side)) {
				return null;
			}

			return .dot;
		},
		1 => {
			var dir: Direction = .negXDir;
			if(connectedNegY) {
				dir = .negYDir;
			} else if(connectedPosX) {
				dir = .posXDir;
			} else if(connectedPosY) {
				dir = .posYDir;
			}
			return .{.halfLine = .{.dir = dir}};
		},
		2 => {
			if((connectedPosX and connectedNegX) or (connectedPosY and connectedNegY)) {
				var dir: Direction = .negYDir;
				if(connectedPosX and connectedNegX) {
					dir = .posXDir;
				}

				return .{.line = .{.dir = dir}};
			}

			var dir: Direction = .negXDir;

			if(connectedNegY) {
				dir = .negYDir;
				if(connectedPosX) {
					dir = .posXDir;
				}
			} else if(connectedPosX) {
				dir = .posXDir;
				if(connectedPosY) {
					dir = .posYDir;
				}
			} else if(connectedPosY) {
				dir = .posYDir;
				if(connectedNegX) {
					dir = .negXDir;
				}
			}

			return .{.bend = .{.dir = dir}};
		},
		3 => {
			var dir: Direction = undefined;
			if(!connectedPosY) dir = .negYDir;
			if(!connectedNegX) dir = .posXDir;
			if(!connectedNegY) dir = .posYDir;
			if(!connectedPosX) dir = .negXDir;

			return .{.intersection = .{.dir = dir}};
		},
		4 => {
			return .cross;
		},
		else => undefined,
	};
}

pub fn createBlockModel(_: Block, modeData: *u16, zon: ZonElement) ModelIndex {
	var radius = zon.get(f32, "radius", 4);
	const radiusForComparisons = std.math.lossyCast(u16, @round(radius*65536.0/16.0));
	radius = @as(f32, @floatFromInt(radiusForComparisons))*16.0/65536.0;
	modeData.* = radiusForComparisons;
	const shellModelId = zon.get([]const u8, "shellModel", "");
	const textureSlotOffset = zon.get(u32, "textureSlotOffset", 0);
	if(branchModels.get(.{.radius = radiusForComparisons, .shellModelId = shellModelId, .textureSlotOffset = textureSlotOffset})) |modelIndex| return modelIndex;

	var shellQuads = main.List(main.models.QuadInfo).init(main.stackAllocator);
	defer shellQuads.deinit();
	if(shellModelId.len != 0) {
		const shellModel = main.models.getModelIndex(shellModelId).model();
		shellModel.getRawFaces(&shellQuads);
	}

	var modelIndex: ModelIndex = undefined;
	for(0..64) |i| {
		var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
		defer quads.deinit();
		quads.appendSlice(shellQuads.items);

		for(Neighbor.iterable) |neighbor| {
			const pattern = getPattern(BranchData.init(@intCast(i)), neighbor);

			if(pattern) |pat| {
				addQuads(pat, neighbor, radius, &quads, textureSlotOffset);
			}
		}

		const index = main.models.Model.init(quads.items);
		if(i == 0) {
			modelIndex = index;
		}
	}

	branchModels.put(.{.radius = radiusForComparisons, .shellModelId = shellModelId, .textureSlotOffset = textureSlotOffset}, modelIndex) catch unreachable;

	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + (block.data & 63)};
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	@setEvalBranchQuota(65_536);

	comptime var rotationTable: [4][16]u8 = undefined;
	comptime for(0..16) |i| {
		rotationTable[0][i] = @intCast(i << 2);
	};
	comptime for(1..4) |a| {
		for(0..16) |i| {
			const old: BranchData = .init(rotationTable[a - 1][i]);
			var new: BranchData = .init(0);

			new.setConnection(Neighbor.dirPosX.rotateZ(), old.isConnected(Neighbor.dirPosX));
			new.setConnection(Neighbor.dirNegX.rotateZ(), old.isConnected(Neighbor.dirNegX));
			new.setConnection(Neighbor.dirPosY.rotateZ(), old.isConnected(Neighbor.dirPosY));
			new.setConnection(Neighbor.dirNegY.rotateZ(), old.isConnected(Neighbor.dirNegY));

			rotationTable[a][i] = new.enabledConnections;
		}
	};
	if(data >= 0b111111) return 0;
	const rotationIndex = (data & 0b111100) >> 2;
	const upDownFlags = data & 0b000011;
	return rotationTable[@intFromEnum(angle)][rotationIndex] | upDownFlags;
}

pub fn generateData(
	_: *main.game.World,
	_: Vec3i,
	_: Vec3f,
	_: Vec3f,
	_: Vec3i,
	neighbor: ?Neighbor,
	currentBlock: *Block,
	neighborBlock: Block,
	blockPlacing: bool,
) bool {
	const canConnectToNeighbor = currentBlock.mode() == neighborBlock.mode() and currentBlock.modeData() == neighborBlock.modeData();

	if(blockPlacing or canConnectToNeighbor or neighborBlock.solid()) {
		const neighborModel = blocks.meshes.model(neighborBlock).model();

		var currentData = BranchData.init(currentBlock.data);
		// Branch block upon placement should extend towards a block it was placed
		// on if the block is solid or also uses branch model.
		const targetVal = ((neighborBlock.solid() and (!neighborBlock.viewThrough() or canConnectToNeighbor)) and (canConnectToNeighbor or neighborModel.isNeighborOccluded[neighbor.?.reverse().toInt()]));
		currentData.setConnection(neighbor.?, targetVal);

		const result: u16 = currentData.enabledConnections;
		if(result == currentBlock.data) return false;

		currentBlock.data = result;
		return true;
	}
	return false;
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	const canConnectToNeighbor = block.mode() == neighborBlock.mode() and block.modeData() == neighborBlock.modeData();
	var currentData = BranchData.init(block.data);

	// Handle joining with other branches. While placed, branches extend in a
	// opposite direction than they were placed from, effectively connecting
	// to the block they were placed at.
	if(canConnectToNeighbor) {
		const neighborData = BranchData.init(neighborBlock.data);
		currentData.setConnection(neighbor, neighborData.isConnected(neighbor.reverse()));
	} else if(!neighborBlock.solid()) {
		currentData.setConnection(neighbor, false);
	}

	const result: u16 = currentData.enabledConnections;
	if(result == block.data) return false;

	block.data = result;
	return true;
}

fn closestRay(block: Block, relativePlayerPos: Vec3f, playerDir: Vec3f) ?u16 {
	var closestIntersectionDistance: f64 = std.math.inf(f64);
	var resultBitMask: ?u16 = null;
	{
		const modelIndex = blocks.meshes.modelIndexStart(block);
		if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
			closestIntersectionDistance = intersection.distance;
			resultBitMask = 0;
		}
	}
	for(Neighbor.iterable) |direction| {
		const directionBitMask = Neighbor.bitMask(direction);

		if((block.data & directionBitMask) != 0) {
			const modelIndex = ModelIndex{.index = blocks.meshes.modelIndexStart(block).index + directionBitMask};
			if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
				if(@abs(closestIntersectionDistance) > @abs(intersection.distance)) {
					closestIntersectionDistance = intersection.distance;
					resultBitMask = direction.bitMask();
				}
			}
		}
	}
	return resultBitMask;
}

pub fn onBlockBreaking(_: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
	if(closestRay(currentData.*, relativePlayerPos, playerDir)) |directionBitMask| {
		// If player destroys a central part of branch block, branch block is completely destroyed.
		if(directionBitMask == 0) {
			currentData.typ = 0;
			currentData.data = 0;
			return;
		}
		// Otherwise only the connection player aimed at is destroyed.
		currentData.data &= ~directionBitMask;
	}
}
