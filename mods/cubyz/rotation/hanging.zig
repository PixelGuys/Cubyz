const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const RotationMode = rotation.RotationMode;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const dependsOnNeighbors = true;

fn transform(_: *main.models.QuadInfo) void {}

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const topModelIndex = main.models.getModelIndex(zon.get([]const u8, "top", "cubyz:cube"));
	const bottomModelIndex = main.models.getModelIndex(zon.get([]const u8, "bottom", "cubyz:cube"));

	const modelIndex = topModelIndex.model().transformModel(transform, .{});
	_ = bottomModelIndex.model().transformModel(transform, .{});
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(block.data%2);
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, blockPlacing: bool) bool {
	const sameBlock = neighborBlock.typ == currentData.typ;
	if(blockPlacing) {
		if(neighbor != Neighbor.dirUp) return false;
		if(!sameBlock) {
			const neighborModel = neighborBlock.mode().model(neighborBlock).model();
			const support = !neighborBlock.replacable() and neighborModel.neighborFacingQuads[Neighbor.dirDown.toInt()].len != 0;
			if(!support) return false;
		}
		currentData.data = 1;
		return true;
	}
	return false;
}

pub fn updateData(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
	if(neighbor != .dirDown) return false;

	const newData: u16 = if(neighborBlock.typ == block.typ) 0 else 1;

	if(newData == block.data) return false;
	block.data = newData;
	return true;
}
