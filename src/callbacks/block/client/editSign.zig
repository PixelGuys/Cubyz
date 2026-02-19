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
	const text: []const u8 = blk: {
		const entity = main.block_entity.getByPosition(params.blockPos, params.chunk) orelse break :blk &.{};
		const data = entity.getComponent(.client, "cubyz:sign") orelse break :blk &.{};
		break :blk data.text;
	};
	main.gui.windowlist.sign_editor.openFromSignData(params.blockPos, text);
	return .handled;
}
