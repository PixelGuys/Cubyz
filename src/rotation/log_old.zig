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

var rotatedModels: std.StringHashMap(ModelIndex) = undefined;

pub fn init() void {
	rotatedModels = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	rotatedModels.deinit();
}

pub fn reset() void {
	rotatedModels.clearRetainingCapacity();
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.as([]const u8, "cubyz:cube");
	if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();
	// Rotate the model:
	const modelIndex = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.identity()});
	_ = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi)});
	_ = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
	_ = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
	_ = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationX(-std.math.pi/2.0)});
	_ = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi).mul(Mat4f.rotationX(-std.math.pi/2.0))});
	rotatedModels.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + @min(block.data, 5)};
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][6]u8 = undefined;
	comptime for(0..6) |i| {
		rotationTable[0][i] = i;
	};
	comptime for(1..4) |a| {
		for(0..6) |i| {
			const neighbor: Neighbor = @enumFromInt(rotationTable[a - 1][i]);
			rotationTable[a][i] = neighbor.rotateZ().toInt();
		}
	};
	if(data >= 6) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, neighbor: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		currentData.data = neighbor.?.reverse().toInt();
		return true;
	}
	return false;
}
