const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const Degrees = rotation.Degrees;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const dependsOnNeighbors = true;
var fenceModels: std.StringHashMap(ModelIndex) = undefined;
const FenceData = packed struct(u4) {
	isConnectedNegX: bool,
	isConnectedPosX: bool,
	isConnectedNegY: bool,
	isConnectedPosY: bool,
};

pub fn init() void {
	fenceModels = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	fenceModels.deinit();
}

pub fn reset() void {
	fenceModels.clearRetainingCapacity();
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][16]u8 = undefined;
	comptime for(0..16) |i| {
		rotationTable[0][i] = @intCast(i);
	};
	comptime for(1..4) |a| {
		for(0..16) |i| {
			const old: FenceData = @bitCast(@as(u4, @intCast(rotationTable[a - 1][i])));
			const new: FenceData = .{
				.isConnectedNegY = old.isConnectedNegX,
				.isConnectedPosY = old.isConnectedPosX,
				.isConnectedPosX = old.isConnectedNegY,
				.isConnectedNegX = old.isConnectedPosY,
			};
			rotationTable[a][i] = @as(u4, @bitCast(new));
		}
	};
	if(data >= 16) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

fn fenceTransform(quad: *main.models.QuadInfo, data: FenceData) void {
	for(&quad.corners, &quad.cornerUV) |*corner, *cornerUV| {
		if(!data.isConnectedNegX and corner[0] == 0) {
			corner[0] = 0.5;
			cornerUV[0] = 0.5;
		}
		if(!data.isConnectedPosX and corner[0] == 1) {
			corner[0] = 0.5;
			cornerUV[0] = 0.5;
		}
		if(!data.isConnectedNegY and corner[1] == 0) {
			corner[1] = 0.5;
			if(@abs(quad.normal[2]) > 0.7) {
				cornerUV[1] = 0.5;
			} else {
				cornerUV[0] = 0.5;
			}
		}
		if(!data.isConnectedPosY and corner[1] == 1) {
			corner[1] = 0.5;
			if(@abs(quad.normal[2]) > 0.7) {
				cornerUV[1] = 0.5;
			} else {
				cornerUV[0] = 0.5;
			}
		}
	}
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.as([]const u8, "cubyz:cube");
	if(fenceModels.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();
	// Rotate the model:
	const modelIndex: ModelIndex = baseModel.transformModel(fenceTransform, .{@as(FenceData, @bitCast(@as(u4, 0)))});
	for(1..16) |fenceData| {
		_ = baseModel.transformModel(fenceTransform, .{@as(FenceData, @bitCast(@as(u4, @intCast(fenceData))))});
	}
	fenceModels.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(block.data & 15);
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	const blockBaseModelIndex = blocks.meshes.modelIndexStart(block.*);
	const neighborBaseModelIndex = blocks.meshes.modelIndexStart(neighborBlock);
	const neighborModel = blocks.meshes.model(neighborBlock).model();
	const targetVal = !neighborBlock.replacable() and !neighborBlock.transparent() and (blockBaseModelIndex == neighborBaseModelIndex or neighborModel.isNeighborOccluded[neighbor.reverse().toInt()]);
	var currentData: FenceData = @bitCast(@as(u4, @truncate(block.data)));
	switch(neighbor) {
		.dirNegX => {
			currentData.isConnectedNegX = targetVal;
		},
		.dirPosX => {
			currentData.isConnectedPosX = targetVal;
		},
		.dirNegY => {
			currentData.isConnectedNegY = targetVal;
		},
		.dirPosY => {
			currentData.isConnectedPosY = targetVal;
		},
		else => {},
	}
	const result: u16 = @as(u4, @bitCast(currentData));
	if(result == block.data) return false;
	block.data = result;
	return true;
}
