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
	if (params.block.blockEntity() == null or !std.mem.eql(u8, params.block.blockEntity().?.id, "cubyz:autocrafter")) {
		std.log.err("Can only open autocrafter if block entity of the block is a autocrafter.", .{});
		return .ignored;
	}
	main.network.protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, params.blockPos);

	const inventory = main.items.Inventory.ClientInventory.init(main.globalAllocator, main.block_entity.BlockEntityTypes.@"cubyz:autocrafter".inventorySize, .serverShared, .{.blockInventory = params.blockPos}, .{});

	main.gui.windowlist.autocrafter.setInventory(inventory);
	main.gui.openWindow("autocrafter");
	main.Window.setMouseGrabbed(false);

	return .handled;
}
