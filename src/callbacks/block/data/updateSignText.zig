const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement) ?*anyopaque {
	return @as(*anyopaque, undefined);
}

pub fn run(_: *anyopaque, params: main.callbacks.BlockCallbackWithData.Params) main.callbacks.Result {
	main.block_entity.ComponentTypes.@"cubyz:sign".updateText(params.pos, params.chunk, params.block, params.data.remaining, params.ctx.side);
	return .handled;
}
