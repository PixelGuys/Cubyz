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

fn transform(quad: *main.models.QuadInfo, data: u16) void {
	quad.textureSlot = data%16;
}

pub fn createBlockModel(block: Block, modeData: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.get([]const u8, "model", "cubyz:cube");
	const stateCount = zon.get(u16, "states", 2);
	const blockId = block.id();
	if(stateCount <= 1) {
		std.log.err("Block '{s}' uses texture pile with {} states. 'texturePile' should have at least 2 states, use 'no_rotation' instead", .{blockId, stateCount});
	} else if(stateCount > 16) {
		std.log.err("Block '{s}' uses texture pile with {} states. 'texturePile' can have at most 16 states.", .{blockId, stateCount});
	}
	modeData.* = stateCount;

	if(rotatedModels.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();

	const modelIndex = baseModel.transformModel(transform, .{@as(u16, @intCast(0))});
	for(1..16) |data| {
		_ = baseModel.transformModel(transform, .{@as(u16, @intCast(data))});
	}
	rotatedModels.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return .{.index = blocks.meshes.modelIndexStart(block).index + @min(block.data, block.modeData() - 1)};
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		currentData.data = 0;
		return true;
	}
	if(currentData.data >= currentData.modeData() - 1) {
		return false;
	}
	currentData.data = currentData.data + 1;
	return true;
}

pub fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
	if(currentData.data == 0) {
		currentData.* = .{.typ = 0, .data = 0};
	} else {
		currentData.data = currentData.data - 1;
	}
}

pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) RotationMode.CanBeChangedInto {
	switch(RotationMode.DefaultFunctions.canBeChangedInto(oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess)) {
		.no, .yes_costsDurability, .yes_dropsItems => return .no,
		.yes, .yes_costsItems => {
			const amountChange = @as(i32, newBlock.data) - if(oldBlock.typ == newBlock.typ) @as(i32, oldBlock.data) else 0;
			if(amountChange <= 0) {
				return .{.yes_dropsItems = @intCast(-amountChange)};
			} else {
				if(item.item == null or item.item.? != .baseItem or item.item.?.baseItem.block != newBlock.typ) return .no;
				return .{.yes_costsItems = @intCast(amountChange)};
			}
		},
	}
}
