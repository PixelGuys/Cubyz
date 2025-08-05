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

fn transform(quad: *main.models.QuadInfo, data: u16) void {
	quad.textureSlot = data%2;
}

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
    const baseModelIndex = main.models.getModelIndex(zon.as([]const u8, "cubyz:cube"));

    const modelIndex = baseModelIndex.model().transformModel(transform, .{@as(u16, 0)});
    _ = baseModelIndex.model().transformModel(transform, .{@as(u16, 1)});
    return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(block.data % 2);
}
