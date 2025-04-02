const std = @import("std");

const main = @import("root");
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

var rotatedModels: std.StringHashMap(ModelIndex) = undefined;
const LadderData = packed struct(u4) {
	negX: bool,
	posX: bool,
	negY: bool,
	posY: bool,
};

fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][16]u8 = undefined;
	comptime for(0..16) |i| {
		rotationTable[0][i] = @intCast(i);
	};
	comptime for(1..4) |a| {
		for(0..16) |i| {
			const old: LadderData = @bitCast(@as(u4, @intCast(rotationTable[a - 1][i])));
			const new: LadderData = .{
				.posY = old.posX,
				.negY = old.negX,
				.negX = old.posY,
				.posX = old.negY,
			};
			rotationTable[a][i] = @as(u4, @bitCast(new));
		}
	};
	if(data >= 16) return 0;
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

	const piHalf = std.math.pi/2.0;
	for(1..16) |i| {
		const ladderData: LadderData = @bitCast(@as(u4, @intCast(i)));
		if(i & i - 1 == 0) {
			if(ladderData.negX) negXModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(piHalf).mul(Mat4f.rotationX(piHalf))});
			if(ladderData.posX) posXModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-piHalf).mul(Mat4f.rotationX(piHalf))});
			if(ladderData.negY) negYModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationX(-piHalf).mul(Mat4f.rotationZ(std.math.pi))});
			if(ladderData.posY) posYModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationX(piHalf)});
		} else {
			var models: [4]ModelIndex = undefined;
			var amount: usize = 0;
			if(ladderData.negX) {
				models[amount] = negXModel;
				amount += 1;
			}
			if(ladderData.posX) {
				models[amount] = posXModel;
				amount += 1;
			}
			if(ladderData.negY) {
				models[amount] = negYModel;
				amount += 1;
			}
			if(ladderData.posY) {
				models[amount] = posYModel;
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
	return .{.index = blocks.meshes.modelIndexStart(block).index + (@as(u4, @truncate(block.data)) -| 1)};
}

pub fn generateData(_: *main.game.World, _: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, _: ?Neighbor, currentData: *Block, neighbor: Block, _: bool) bool {
	if(neighbor.mode() == currentData.mode()) parallelPlacing: {
		const rayData = closestRay(.bit, neighbor, null, relativePlayerPos - @as(Vec3f, @floatFromInt(relativeDir)), playerDir);
		const ladderData: LadderData = @bitCast(@as(u4, @truncate(rayData)));
		if((ladderData.negX or ladderData.posX) and relativeDir[0] != 0) break :parallelPlacing;
		if((ladderData.negY or ladderData.posY) and relativeDir[1] != 0) break :parallelPlacing;
		if(currentData.data & rayData == rayData) return false;
		currentData.data |= rayData;
		return true;
	}
	var data: LadderData = @bitCast(@as(u4, @truncate(currentData.data)));
	if(relativeDir[0] == 1) data.posX = true;
	if(relativeDir[0] == -1) data.negX = true;
	if(relativeDir[1] == 1) data.posY = true;
	if(relativeDir[1] == -1) data.negY = true;
	if(@as(u4, @bitCast(data)) != currentData.data) {
		currentData.data = @as(u4, @bitCast(data));
		return true;
	}

	return false;
}

fn closestRay(comptime typ: enum {bit, intersection}, block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) if(typ == .intersection) ?RayIntersectionResult else u16 {
	var result: ?RayIntersectionResult = null;
	var resultBit: u16 = 0;
	for([_]u16{1, 2, 4, 8}) |bit| {
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
