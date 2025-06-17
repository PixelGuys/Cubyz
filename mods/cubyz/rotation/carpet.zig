const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const Degrees = rotation.Degrees;
const RayIntersectionResult = rotation.RayIntersectionResult;
const RotationMode = rotation.RotationMode;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

const torch = @import("torch.zig");

pub const naturalStandard: u16 = 0b10000;
var rotatedModels: std.StringHashMap(ModelIndex) = undefined;
const CarpetData = packed struct(u6) {
	negX: bool,
	posX: bool,
	negY: bool,
	posY: bool,
	negZ: bool,
	posZ: bool,
};

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][64]u8 = undefined;
	comptime for(0..64) |i| {
		rotationTable[0][i] = @intCast(i);
	};
	comptime for(1..4) |a| {
		for(0..64) |i| {
			const old: CarpetData = @bitCast(@as(u6, @intCast(rotationTable[a - 1][i])));
			const new: CarpetData = .{
				.posZ = old.posZ,
				.negZ = old.negZ,
				.posY = old.posX,
				.negY = old.negX,
				.negX = old.posY,
				.posX = old.negY,
			};
			rotationTable[a][i] = @as(u6, @bitCast(new));
		}
	};
	if(data >= 64) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

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
	var negXModel: ModelIndex = undefined;
	var posXModel: ModelIndex = undefined;
	var negYModel: ModelIndex = undefined;
	var posYModel: ModelIndex = undefined;
	var negZModel: ModelIndex = undefined;
	var posZModel: ModelIndex = undefined;
	for(1..64) |i| {
		const carpetData: CarpetData = @bitCast(@as(u6, @intCast(i)));
		if(i & i - 1 == 0) {
			if(carpetData.negX) negXModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			if(carpetData.posX) posXModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			if(carpetData.negY) negYModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationX(-std.math.pi/2.0)});
			if(carpetData.posY) posYModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi).mul(Mat4f.rotationX(-std.math.pi/2.0))});
			if(carpetData.negZ) negZModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.identity()});
			if(carpetData.posZ) posZModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationY(std.math.pi)});
		} else {
			var models: [6]ModelIndex = undefined;
			var amount: usize = 0;
			if(carpetData.negX) {
				models[amount] = negXModel;
				amount += 1;
			}
			if(carpetData.posX) {
				models[amount] = posXModel;
				amount += 1;
			}
			if(carpetData.negY) {
				models[amount] = negYModel;
				amount += 1;
			}
			if(carpetData.posY) {
				models[amount] = posYModel;
				amount += 1;
			}
			if(carpetData.negZ) {
				models[amount] = negZModel;
				amount += 1;
			}
			if(carpetData.posZ) {
				models[amount] = posZModel;
				amount += 1;
			}
			_ = main.models.Model.mergeModels(models[0..amount]);
		}
	}
	const modelIndex = negXModel;
	rotatedModels.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + (@as(u6, @truncate(block.data)) -| 1)};
}

pub fn generateData(_: *main.game.World, _: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, _: ?Neighbor, currentData: *Block, neighbor: Block, _: bool) bool {
	if(neighbor.mode() == currentData.mode()) parallelPlacing: {
		const bit = closestRay(.bit, neighbor, null, relativePlayerPos - @as(Vec3f, @floatFromInt(relativeDir)), playerDir);
		const bitData: CarpetData = @bitCast(@as(u6, @truncate(bit)));
		if((bitData.negX or bitData.posX) and relativeDir[0] != 0) break :parallelPlacing;
		if((bitData.negY or bitData.posY) and relativeDir[1] != 0) break :parallelPlacing;
		if((bitData.negZ or bitData.posZ) and relativeDir[2] != 0) break :parallelPlacing;
		if(currentData.data & bit == bit) return false;
		currentData.data |= bit;
		return true;
	}
	var data: CarpetData = @bitCast(@as(u6, @truncate(currentData.data)));
	if(relativeDir[0] == 1) data.posX = true;
	if(relativeDir[0] == -1) data.negX = true;
	if(relativeDir[1] == 1) data.posY = true;
	if(relativeDir[1] == -1) data.negY = true;
	if(relativeDir[2] == 1) data.posZ = true;
	if(relativeDir[2] == -1) data.negZ = true;
	if(@as(u6, @bitCast(data)) != currentData.data) {
		currentData.data = @as(u6, @bitCast(data));
		return true;
	} else {
		return false;
	}
}

fn closestRay(comptime typ: enum {bit, intersection}, block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) if(typ == .intersection) ?RayIntersectionResult else u16 {
	var result: ?RayIntersectionResult = null;
	var resultBit: u16 = 0;
	for([_]u16{1, 2, 4, 8, 16, 32}) |bit| {
		if(block.data & bit != 0) {
			const modelIndex = ModelIndex{.index = blocks.meshes.modelIndexStart(block).index + bit - 1};
			if(RotationMode.DefaultFunctions.rayModelIntersection(modelIndex, relativePlayerPos, playerDir)) |intersection| {
				if(result == null or result.?.distance > intersection.distance) {
					result = intersection;
					resultBit = bit;
				}
			}
		}
	}
	if(typ == .bit) return resultBit;
	return result;
}

pub fn rayIntersection(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
	return closestRay(.intersection, block, item, relativePlayerPos, playerDir);
}

pub fn onBlockBreaking(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
	const bit = closestRay(.bit, currentData.*, item, relativePlayerPos, playerDir);
	currentData.data &= ~bit;
	if(currentData.data == 0) currentData.typ = 0;
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
	return torch.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess);
}
