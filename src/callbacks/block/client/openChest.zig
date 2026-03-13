const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement) ?*anyopaque {
	return @as(*anyopaque, undefined);
}

pub fn run(_: *anyopaque, params: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	if (params.block.onTrigger().inner != &main.callbacks.BlockCallbackWithData.list.createChest.run) return .ignored;
	main.sync.ClientSide.executeCommand(.{.triggerBlock = .init(params.block, params.blockPos, &.{})});

	const inventory = main.items.Inventory.ClientInventory.init(main.globalAllocator, 20, .normal, .serverShared, .{.blockInventory = params.blockPos}, .{}); // TODO: Allow the server side to give us the inventory size

	main.gui.windowlist.chest.setInventory(inventory);
	main.gui.openWindow("chest");
	main.Window.setMouseGrabbed(false);
	return .handled;
}
