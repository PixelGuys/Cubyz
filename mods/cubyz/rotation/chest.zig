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
	var iterator = rotatedModels.keyIterator();
	while(iterator.next()) |key| {
		main.globalAllocator.free(key.*);
	}
	rotatedModels.deinit();
}

pub fn reset() void {
	var iterator = rotatedModels.keyIterator();
	while(iterator.next()) |key| {
		main.globalAllocator.free(key.*);
	}
	rotatedModels.clearRetainingCapacity();
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const closedId = zon.get([]const u8, "closed", "cubyz:cube");
	const openId = zon.get([]const u8, "open", "cubyz:cube");
	const lidId = zon.get([]const u8, "lid", "cubyz:cube");
	const joinedId = std.fmt.allocPrint(main.globalAllocator.allocator, "{s}:{s}:{s}", .{closedId, openId, lidId}) catch unreachable;
	if(rotatedModels.get(joinedId)) |modelIndex| return modelIndex;

	const closedModel = main.models.getModelIndex(closedId).model();
	// Rotate the model:
	const modelIndex: ModelIndex = closedModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0)});
	_ = closedModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0)});
	_ = closedModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi)});
	_ = closedModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.identity()});

	const openModel = main.models.getModelIndex(openId).model();

	_ = openModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0)});
	_ = openModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0)});
	_ = openModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi)});
	_ = openModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.identity()});

	rotatedModels.put(joinedId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(@min(block.data, 7));
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][4]u8 = undefined;
	comptime for(0..4) |i| {
		rotationTable[0][i] = i;
	};
	comptime for(1..4) |a| {
		for(0..4) |i| {
			const neighbor: Neighbor = @enumFromInt(rotationTable[a - 1][i] + 2);
			rotationTable[a][i] = neighbor.rotateZ().toInt() - 2;
		}
	};
	if(data >= 8) return 0;
	return rotationTable[@intFromEnum(angle)][data & 3] | (data & 4);
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, playerDir: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		if(@abs(playerDir[0]) > @abs(playerDir[1])) {
			const dir: Neighbor = if(playerDir[0] < 0) .dirNegX else .dirPosX;
			currentData.data = dir.toInt() - 2;
		} else {
			const dir: Neighbor = if(playerDir[1] < 0) .dirNegY else .dirPosY;
			currentData.data = dir.toInt() - 2;
		}
		return true;
	}
	return false;
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) rotation.RotationMode.CanBeChangedInto {
	if(oldBlock.typ == newBlock.typ) return .yes;
	return rotation.RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess);
}