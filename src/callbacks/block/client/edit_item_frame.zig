const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement, _: main.callbacks.Creator) ?*anyopaque {
	return @as(*anyopaque, undefined);
}

pub fn run(_: *anyopaque, params: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	if (params.block.blockEntity() == null or !std.mem.eql(u8, params.block.blockEntity().?.id, "cubyz:item_frame")) {
		std.log.err("Can only edit item frame if block entity of the block is a item frame.", .{});
		return .ignored;
	}
	main.block_entity.BlockEntityTypes.@"cubyz:item_frame".StorageClient.mutex.lock();
	defer main.block_entity.BlockEntityTypes.@"cubyz:item_frame".StorageClient.mutex.unlock();
	const heldItem = main.game.Player.inventory.getItem(main.game.Player.selectedSlot);
	main.block_entity.BlockEntityTypes.@"cubyz:item_frame".updateItemFromClient(params.blockPos, heldItem);

	return .handled;
}
