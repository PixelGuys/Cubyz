const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	return result;
}

pub fn run(_: *@This(), params: main.callbacks.ItemUsedCallback.Params) main.callbacks.Result {
	if (params.target != .block) return .ignored;

	main.game.Player.selectionPosition1 = params.target.block.blockPos;
	main.network.protocols.genericUpdate.sendWorldEditPos(main.game.world.?.conn, .selectedPos1, params.target.block.blockPos);
	return .handled;
}
