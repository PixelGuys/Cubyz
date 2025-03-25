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

pub const naturalStandard: u16 = 1;
pub const dependsOnNeighbors = true;
var rotatedModels: std.StringHashMap(ModelIndex) = undefined;
const TorchData = packed struct(u5) {
	center: bool,
	negX: bool,
	posX: bool,
	negY: bool,
	posY: bool,
};

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
	const baseModelId: []const u8 = zon.get([]const u8, "base", "cubyz:cube");
	const sideModelId: []const u8 = zon.get([]const u8, "side", "cubyz:cube");
	const key: []const u8 = std.mem.concat(main.stackAllocator.allocator, u8, &.{baseModelId, sideModelId}) catch unreachable;
	defer main.stackAllocator.free(key);

	if(rotatedModels.get(key)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(baseModelId).model();
	const sideModel = main.models.getModelIndex(sideModelId).model();
	// Rotate the model:
	var centerModel: ModelIndex = undefined;
	var negXModel: ModelIndex = undefined;
	var posXModel: ModelIndex = undefined;
	var negYModel: ModelIndex = undefined;
	var posYModel: ModelIndex = undefined;
	for(1..32) |i| {
		const torchData: TorchData = @bitCast(@as(u5, @intCast(i)));
		if(i & i - 1 == 0) {
			if(torchData.center) centerModel = baseModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.identity()});
			if(torchData.negX) negXModel = sideModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(0)});
			if(torchData.posX) posXModel = sideModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi)});
			if(torchData.negY) negYModel = sideModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(std.math.pi/2.0)});
			if(torchData.posY) posYModel = sideModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(-std.math.pi/2.0)});
		} else {
			var models: [5]ModelIndex = undefined;
			var amount: usize = 0;
			if(torchData.center) {
				models[amount] = centerModel;
				amount += 1;
			}
			if(torchData.negX) {
				models[amount] = negXModel;
				amount += 1;
			}
			if(torchData.posX) {
				models[amount] = posXModel;
				amount += 1;
			}
			if(torchData.negY) {
				models[amount] = negYModel;
				amount += 1;
			}
			if(torchData.posY) {
				models[amount] = posYModel;
				amount += 1;
			}
			_ = main.models.Model.mergeModels(models[0..amount]);
		}
	}
	const modelIndex = centerModel;
	rotatedModels.put(key, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + (@as(u5, @truncate(block.data)) -| 1)};
}

fn rotateZ(data: u16, angle: Degrees) u16 {
	comptime var rotationTable: [4][32]u8 = undefined;
	comptime for(0..32) |i| {
		rotationTable[0][i] = @intCast(i);
	};
	comptime for(1..4) |a| {
		for(0..32) |i| {
			const old: TorchData = @bitCast(@as(u5, @intCast(rotationTable[a - 1][i])));
			const new: TorchData = .{
				.center = old.center,
				.negY = old.negX,
				.posY = old.posX,
				.posX = old.negY,
				.negX = old.posY,
			};
			rotationTable[a][i] = @as(u5, @bitCast(new));
		}
	};
	if(data >= 32) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, _: bool) bool {
	if(neighbor == null) return false;
	const neighborModel = blocks.meshes.model(neighborBlock).model();
	const neighborSupport = neighborBlock.solid() and neighborModel.neighborFacingQuads[neighbor.?.reverse().toInt()].len != 0;
	if(!neighborSupport) return false;
	var data: TorchData = @bitCast(@as(u5, @truncate(currentData.data)));
	if(relativeDir[0] == 1) data.posX = true;
	if(relativeDir[0] == -1) data.negX = true;
	if(relativeDir[1] == 1) data.posY = true;
	if(relativeDir[1] == -1) data.negY = true;
	if(relativeDir[2] == -1) data.center = true;
	if(@as(u5, @bitCast(data)) != currentData.data) {
		currentData.data = @as(u5, @bitCast(data));
		return true;
	} else {
		return false;
	}
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	const neighborModel = blocks.meshes.model(neighborBlock).model();
	const neighborSupport = neighborBlock.solid() and neighborModel.neighborFacingQuads[neighbor.reverse().toInt()].len != 0;
	var currentData: TorchData = @bitCast(@as(u5, @truncate(block.data)));
	switch(neighbor) {
		.dirNegX => {
			currentData.negX = currentData.negX and neighborSupport;
		},
		.dirPosX => {
			currentData.posX = currentData.posX and neighborSupport;
		},
		.dirNegY => {
			currentData.negY = currentData.negY and neighborSupport;
		},
		.dirPosY => {
			currentData.posY = currentData.posY and neighborSupport;
		},
		.dirDown => {
			currentData.center = currentData.center and neighborSupport;
		},
		else => {},
	}
	const result: u16 = @as(u5, @bitCast(currentData));
	if(result == block.data) return false;
	block.data = result;
	if(result == 0) block.typ = 0;
	return true;
}

fn closestRay(comptime typ: enum {bit, intersection}, block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) if(typ == .intersection) ?RayIntersectionResult else u16 {
	var result: ?RayIntersectionResult = null;
	var resultBit: u16 = 0;
	for([_]u16{1, 2, 4, 8, 16}) |bit| {
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
	switch(RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess)) {
		.no, .yes_costsDurability, .yes_dropsItems => return .no,
		.yes, .yes_costsItems => {
			const torchAmountChange = @as(i32, @popCount(newBlock.data)) - if(oldBlock.typ == newBlock.typ) @as(i32, @popCount(oldBlock.data)) else 0;
			if(torchAmountChange <= 0) {
				return .{.yes_dropsItems = @intCast(-torchAmountChange)};
			} else {
				if(item.item == null or item.item.? != .baseItem or !std.meta.eql(item.item.?.baseItem.block, newBlock.typ)) return .no;
				return .{.yes_costsItems = @intCast(torchAmountChange)};
			}
		},
	}
}
