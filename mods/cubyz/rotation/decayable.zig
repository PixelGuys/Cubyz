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

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, block: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		block.data = 1;
	}
	return blockPlacing;
}
