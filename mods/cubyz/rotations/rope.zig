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

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

pub fn findPlacementPos(_: *main.game.World, pos: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, neighbor: ?Neighbor, block: *Block, neighborBlock: Block) Vec3i {
	if (block.typ == neighborBlock.typ) {
		var searchedBlock: Block = neighborBlock;
		const ropeBuildLimit: usize = 32;
		const neighborPos: Vec3i = pos + neighbor.?.relPos();
		for (0..ropeBuildLimit) |i| {
			if (block.typ != searchedBlock.typ) return neighborPos + Vec3i{0, 0, -@as(i32, @intCast(i)) + 1};
			searchedBlock = main.renderer.mesh_storage.getBlockFromRenderThread(neighborPos[0], neighborPos[1], neighborPos[2] - @as(i32, @intCast(i))) orelse return pos;
		}
	}
	return pos;
}