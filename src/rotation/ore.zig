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

var modelCache: ?ModelIndex = null;

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {
	modelCache = null;
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.as([]const u8, "cubyz:cube");
	if(!std.mem.eql(u8, modelId, "cubyz:cube")) {
		std.log.err("Ores can only be use on cube models, found '{s}'", .{modelId});
	}
	if(modelCache) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex("cubyz:cube").model();
	var quadList = main.List(main.models.QuadInfo).init(main.stackAllocator);
	defer quadList.deinit();
	baseModel.getRawFaces(&quadList);
	const len = quadList.items.len;
	for(0..len) |i| {
		quadList.append(quadList.items[i]);
		quadList.items[i + len].textureSlot += 16;
		quadList.items[i].opaqueInLod = 2;
	}
	const modelIndex = main.models.Model.init(quadList.items);
	modelCache = modelIndex;
	return modelIndex;
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, _: bool) bool {
	return false;
}

pub fn modifyBlock(block: *Block, newBlockType: u16) bool {
	if(block.transparent() or block.viewThrough()) return false;
	if(!main.blocks.meshes.modelIndexStart(block.*).model().allNeighborsOccluded) return false;
	if(block.data != 0) return false;
	block.data = block.typ;
	block.typ = newBlockType;
	return true;
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, _: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
	if(oldBlock == newBlock) return .no;
	if(oldBlock.transparent() or oldBlock.viewThrough()) return .no;
	if(!main.blocks.meshes.modelIndexStart(oldBlock).model().allNeighborsOccluded) return .no;
	if(oldBlock.data != 0) return .no;
	if(newBlock.data != oldBlock.typ) return .no;
	shouldDropSourceBlockOnSuccess.* = false;
	return .{.yes_costsItems = 1};
}

pub fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
	currentData.typ = currentData.data;
	currentData.data = 0;
}
