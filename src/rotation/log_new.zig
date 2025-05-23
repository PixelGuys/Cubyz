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

var modelIndex: ?ModelIndex = null;

const LogData = packed struct(u6) {
	enabledConnections: u6,

	pub inline fn init(blockData: u16) LogData {
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

pub fn init() void {}

pub fn deinit() void {}

pub fn reset() void {
	modelIndex = null;
}

const DirectionWithSign = enum(u2) {
	negYDir = 0,
	posXDir = 1,
	posYDir = 2,
	negXDir = 3,
};

const DirectionWithoutSign = enum(u1) {
	y = 0,
	x = 1,
};

const Pattern = union(enum) {
	dot: void,
	halfLine: struct {
		dir: DirectionWithoutSign,
	},
	line: struct {
		dir: DirectionWithoutSign,
	},
	bend: struct {
		dir: DirectionWithSign,
	},
	intersection: struct {
		dir: DirectionWithSign,
	},
	cross: void,
	cut: void,
};

fn rotateQuad(originalCorners: [4]Vec2f, pattern: Pattern, side: Neighbor) main.models.QuadInfo {
	var corners: [4]Vec2f = originalCorners;

	switch(pattern) {
		.dot, .cross, .cut => {},
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
	offset[@intFromEnum(side.vectorComponent())] = @floatFromInt(@intFromBool(side.isPositive()));

	const res: main.models.QuadInfo = .{
		.corners = .{
			corners3d[0] + offset,
			corners3d[1] + offset,
			corners3d[2] + offset,
			corners3d[3] + offset,
		},
		.cornerUV = originalCorners,
		.normal = @floatFromInt(side.relPos()),
		.textureSlot = @intFromEnum(pattern),
	};

	return res;
}

fn addQuads(pattern: Pattern, side: Neighbor, out: *main.List(main.models.QuadInfo)) void {
	out.append(rotateQuad(.{
		.{0, 0},
		.{0, 1},
		.{1, 0},
		.{1, 1},
	}, pattern, side));
}

fn getPattern(data: LogData, side: Neighbor) Pattern {
	if (data.isConnected(side)) {
		return .cut;
	}

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
			return .dot;
		},
		1 => {
			var dir: DirectionWithoutSign = .x;
			if(connectedNegY) {
				dir = .y;
			} else if(connectedPosX) {
				dir = .x;
			} else if(connectedPosY) {
				dir = .y;
			}
			return .{.halfLine = .{.dir = dir}};
		},
		2 => {
			if((connectedPosX and connectedNegX) or (connectedPosY and connectedNegY)) {
				var dir: DirectionWithoutSign = .y;
				if(connectedPosX and connectedNegX) {
					dir = .x;
				}

				return .{.line = .{.dir = dir}};
			}

			var dir: DirectionWithSign = .negXDir;

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
			var dir: DirectionWithSign = undefined;
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

pub fn createBlockModel(_: Block, _: *u16, _: ZonElement) ModelIndex {
	if(modelIndex) |idx| return idx;
	
	for(0..64) |i| {
		var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
		defer quads.deinit();

		const data = LogData.init(@intCast(i));
		
		for(Neighbor.iterable) |neighbor| {
			const pattern = getPattern(data, neighbor);

			addQuads(pattern, neighbor, &quads);
		}

		const index = main.models.Model.init(quads.items);
		if(i == 0) {
			modelIndex = index;
		}
	}

	return modelIndex.?;
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
			const old: LogData = .init(rotationTable[a - 1][i]);
			var new: LogData = .init(0);

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
	pos: Vec3i,
	_: Vec3f,
	_: Vec3f,
	_: Vec3i,
	neighbor: ?Neighbor,
	currentBlock: *Block,
	neighborBlock: Block,
	blockPlacing: bool,
) bool {
	const canConnectToNeighbor = currentBlock.mode() == neighborBlock.mode() and currentBlock.modeData() == neighborBlock.modeData();

	if(blockPlacing or canConnectToNeighbor or !neighborBlock.replacable()) {
		const neighborModel = blocks.meshes.model(neighborBlock).model();

		var currentData = LogData.init(currentBlock.data);
		// Log block upon placement should extend towards a block it was placed
		// on if the block is solid or also uses log model.
		const targetVal = ((!neighborBlock.replacable() and (!neighborBlock.viewThrough() or canConnectToNeighbor)) and (canConnectToNeighbor or neighborModel.isNeighborOccluded[neighbor.?.reverse().toInt()]));
		currentData.setConnection(neighbor.?, targetVal);

		for(Neighbor.iterable) |side| {
			if(side == neighbor.?) {
				continue;
			}

			const sidePos = pos + side.relPos();
			const sideBlock = main.renderer.mesh_storage.getBlock(sidePos[0], sidePos[1], sidePos[2]) orelse continue;
			const canConnectToSide = currentBlock.mode() == sideBlock.mode() and currentBlock.modeData() == sideBlock.modeData();

			if(canConnectToSide) {
				const sideData = LogData.init(sideBlock.data);
				currentData.setConnection(side, sideData.isConnected(side.reverse()));
			}
		}

		const result: u16 = currentData.enabledConnections;
		if(result == currentBlock.data) return false;

		currentBlock.data = result;
		return true;
	}
	return false;
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	const canConnectToNeighbor = block.mode() == neighborBlock.mode() and block.modeData() == neighborBlock.modeData();
	var currentData = LogData.init(block.data);

	// Handle joining with other branches. While placed, branches extend in a
	// opposite direction than they were placed from, effectively connecting
	// to the block they were placed at.
	if(canConnectToNeighbor) {
		const neighborData = LogData.init(neighborBlock.data);
		currentData.setConnection(neighbor, neighborData.isConnected(neighbor.reverse()));
	}

	const result: u16 = currentData.enabledConnections;
	if(result == block.data) return false;

	block.data = result;
	return true;
}