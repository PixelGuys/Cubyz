pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {

	const modelId = zon.get([]const u8, "model", "cubyz:cube");
	const stateCount = zon.get(u16, "states", 2);
	const blockId = block.id();
	if(stateCount <= 1) {
		std.log.err("Block '{s}' uses multistate no_rotation with {} states. 'multistate no_rotation' should have at least 2 states, use 'no_rotation' instead", .{blockId, stateCount});
	} else if(stateCount > 16) {
		std.log.err("Block '{s}' uses multistate no_rotation with {} states. 'multistate no_rotation' can have at most 16 states.", .{blockId, stateCount});
	}
	modeData.* = stateCount;

	const baseModel = main.models.getModelIndex(zon.as([]const u8, "cubyz:cube");).model();

	return baseModel;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(min@(block.data, block.modeData() - 1));
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(@min(block.data, block.modeData() - 1));
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, currentData: *Block, _: Block, blockPlacing: bool) bool {
	if(blockPlacing) {
		currentData.data = 0;
		return true;
	}
	return false;
}

