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
const branch = @import("branch.zig");

pub const dependsOnNeighbors = true;

var modelIndex: ?ModelIndex = null;

const LogData = branch.BranchData;

pub fn init() void {}

pub fn deinit() void {}

pub fn reset() void {
	modelIndex = null;
}

const DirectionWithSign = branch.Direction;

const DirectionWithoutSign = enum(u1) {
	y = 0,
	x = 1,

	fn fromBranchDirection(dir: DirectionWithSign) DirectionWithoutSign {
		return switch(dir) {
			.negYDir => .y,
			.posXDir => .x,
			.posYDir => .y,
			.negXDir => .x,
		};
	}
};

const Pattern = union(enum) {
	dot: void,
	line: DirectionWithoutSign,
	bend: DirectionWithSign,
	intersection: DirectionWithSign,
	cross: void,
	cut: void,
};

fn rotateQuad(pattern: Pattern, side: Neighbor) main.models.QuadInfo {
	const originalCorners: [4]Vec2f = .{
		.{0, 0},
		.{0, 1},
		.{1, 0},
		.{1, 1},
	};
	var corners: [4]Vec2f = originalCorners;

	switch(pattern) {
		.dot, .cross, .cut => {},
		.line => |dir| {
			var angle: f32 = @as(f32, @floatFromInt(@intFromEnum(dir)))*std.math.pi/2.0;
			if(side.relZ() != 0) {
				angle *= -1;
			}
			if(side.isPositive()) {
				angle *= -1;
			}
			if(side.relY() != 0) {
				angle *= -1;
			}
			corners = .{
				vec.rotate2d(originalCorners[0], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[1], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[2], angle, @splat(0.5)),
				vec.rotate2d(originalCorners[3], angle, @splat(0.5)),
			};
		},
		.bend, .intersection => |dir| {
			corners = originalCorners;

			const angle: f32 = -@as(f32, @floatFromInt(@intFromEnum(dir)))*std.math.pi/2.0;
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
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(originalCorners[0][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(originalCorners[0][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(originalCorners[1][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(originalCorners[1][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(originalCorners[2][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(originalCorners[2][1] - offY)),
		@as(Vec3f, @floatFromInt(side.textureX()))*@as(Vec3f, @splat(originalCorners[3][0] - offX)) + @as(Vec3f, @floatFromInt(side.textureY()))*@as(Vec3f, @splat(originalCorners[3][1] - offY)),
	};

	const offset: Vec3f = @floatFromInt(@intFromBool(side.relPos() == Vec3i{1, 1, 1}));

	const res: main.models.QuadInfo = .{
		.corners = .{
			corners3d[0] + offset,
			corners3d[1] + offset,
			corners3d[2] + offset,
			corners3d[3] + offset,
		},
		.cornerUV = .{corners[0], corners[1], corners[2], corners[3]},
		.normal = @as(Vec3f, @floatFromInt(side.relPos())),
		.textureSlot = @intFromEnum(pattern),
	};

	return res;
}

fn getPattern(data: LogData, side: Neighbor) Pattern {
	if(data.isConnected(side)) {
		return .cut;
	}

	const pattern = branch.getPattern(data, side).?;

	switch(pattern) {
		.dot => {
			return .dot;
		},
		.halfLine => |dir| {
			return .{.line = .fromBranchDirection(dir)};
		},
		.line => |dir| {
			return .{.line = .fromBranchDirection(dir)};
		},
		.bend => |dir| {
			return .{.bend = dir};
		},
		.intersection => |dir| {
			return .{.intersection = dir};
		},
		.cross => {
			return .cross;
		},
	}
}

pub fn createBlockModel(_: Block, _: *u16, _: ZonElement) ModelIndex {
	if(modelIndex) |idx| return idx;

	for(0..64) |i| {
		var quads = main.List(main.models.QuadInfo).init(main.stackAllocator);
		defer quads.deinit();

		const data = LogData.init(@intCast(i));

		for(Neighbor.iterable) |neighbor| {
			const pattern = getPattern(data, neighbor);

			quads.append(rotateQuad(pattern, neighbor));
		}

		const index = main.models.Model.init(quads.items);
		if(i == 0) {
			modelIndex = index;
		}
	}

	return modelIndex.?;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(block.data & 63);
}

pub const rotateZ = branch.rotateZ;

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
	const canConnectToNeighbor = currentBlock.mode() == neighborBlock.mode();

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
			const sideBlock = main.renderer.mesh_storage.getBlockFromRenderThread(sidePos[0], sidePos[1], sidePos[2]) orelse continue;
			const canConnectToSide = currentBlock.mode() == sideBlock.mode() and currentBlock.modeData() == sideBlock.modeData();

			if(canConnectToSide) {
				const sideData = LogData.init(sideBlock.data);
				currentData.setConnection(side, sideData.isConnected(side.reverse()));
			}
		}

		currentBlock.data = currentData.enabledConnections;
		return true;
	}
	return false;
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	const canConnectToNeighbor = block.mode() == neighborBlock.mode();
	var currentData = LogData.init(block.data);

	// Handle joining with other logs. While placed, logs extend in a
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
