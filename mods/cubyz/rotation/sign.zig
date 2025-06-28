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

pub const naturalStandard: u16 = 0;
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

const centerRotations = 8;
const sideRotations = 4;

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const floorModelId: []const u8 = zon.get([]const u8, "floor", "cubyz:cube");
	const sideModelId: []const u8 = zon.get([]const u8, "side", "cubyz:cube");
	const ceilingModelId: []const u8 = zon.get([]const u8, "ceiling", "cubyz:cube");
	const key: []const u8 = std.mem.concat(main.stackAllocator.allocator, u8, &.{floorModelId, sideModelId, ceilingModelId}) catch unreachable;
	defer main.stackAllocator.free(key);

	if(rotatedModels.get(key)) |modelIndex| return modelIndex;

	const floorModel = main.models.getModelIndex(floorModelId).model();
	const sideModel = main.models.getModelIndex(sideModelId).model();
	const ceilingModel = main.models.getModelIndex(ceilingModelId).model();
	var modelIndex: ModelIndex = undefined;
	// Rotate the model:
	for(0..centerRotations) |i| {
		const index = floorModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(@as(f32, @floatFromInt(i))*2.0*std.math.pi/centerRotations)});
		if(i == 0) modelIndex = index;
	}
	for(0..centerRotations) |i| {
		_ = ceilingModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(@as(f32, @floatFromInt(i))*2.0*std.math.pi/centerRotations)});
	}
	for(0..sideRotations) |i| {
		_ = sideModel.transformModel(rotation.rotationMatrixTransform, .{Mat4f.rotationZ(@as(f32, @floatFromInt(i))*2.0*std.math.pi/sideRotations)});
	}
	rotatedModels.put(key, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(@min(centerRotations*2 + sideRotations, block.data));
}

pub fn rotateZ(data: u16, angle: Degrees) u16 {
	const rotationTable: [4][2*centerRotations + sideRotations]u8 = .{
		.{
			0,  1,  2,  3,  4,  5,  6,  7,
			8,  9,  10, 11, 12, 13, 14, 15,
			16, 17, 18, 19,
		},
		.{
			2,  3,  4,  5,  6,  7,  0, 1,
			10, 11, 12, 13, 14, 15, 8, 9,
			17, 18, 19, 16,
		},
		.{
			4,  5,  6,  7,  0, 1, 2,  3,
			12, 13, 14, 15, 8, 9, 10, 11,
			18, 19, 16, 17,
		},
		.{
			6,  7,  0,  1,  2,  3,  4,  5,
			14, 15, 8,  9,  10, 11, 12, 13,
			19, 16, 17, 18,
		},
	};
	if(data >= 2*centerRotations + sideRotations) return 0;
	return rotationTable[@intFromEnum(angle)][data];
}

fn getRotationFromDir(dir: Vec3f) u16 {
	const x = dir[0];
	const y = dir[1];
	var data: u3 = 0;
	if(@abs(x) > @abs(y)) {
		if(x < 0) {
			data = 0;
		} else {
			data = 4;
		}
		if(@abs(x) < 2*@abs(y)) {
			if((x < 0) == (y < 0)) {
				data +%= 1;
			} else {
				data -%= 1;
			}
		}
	} else {
		if(y < 0) {
			data = 2;
		} else {
			data = 6;
		}
		if(@abs(y) < 2*@abs(x)) {
			if((x < 0) == (y < 0)) {
				data -%= 1;
			} else {
				data +%= 1;
			}
		}
	}
	return data;
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(neighbor == null) return false;
	if(!blockPlacing) return false;
	currentData.data = switch(Neighbor.fromRelPos(relativeDir) orelse unreachable) {
		.dirNegX => 2*centerRotations,
		.dirNegY => 2*centerRotations + 1,
		.dirPosX => 2*centerRotations + 2,
		.dirPosY => 2*centerRotations + 3,
		.dirUp => centerRotations + getRotationFromDir(playerDir),
		.dirDown => getRotationFromDir(playerDir),
	};
	return true;
}

pub fn updateData(block: *Block, neighbor: Neighbor, _: Block) bool {
	const shouldBeBroken = switch(neighbor) {
		.dirNegX => block.data == 2*centerRotations,
		.dirNegY => block.data == 2*centerRotations + 1,
		.dirPosX => block.data == 2*centerRotations + 2,
		.dirPosY => block.data == 2*centerRotations + 3,
		.dirDown => block.data < centerRotations,
		.dirUp => block.data >= centerRotations and block.data < 2*centerRotations,
	};
	if(!shouldBeBroken) return false;
	block.* = .{.typ = 0, .data = 0};
	return true;
}
