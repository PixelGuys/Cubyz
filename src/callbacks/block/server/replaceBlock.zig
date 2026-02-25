const std = @import("std");

const main = @import("main");

block: main.blocks.Block,

pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.block = main.blocks.parseBlock(zon.get(?[]const u8, "block", null) orelse {
			std.log.err("Missing field \"block\" for replaceBlock event", .{});
			return null;
		}),
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.blockPos.x;
	const wy = params.chunk.super.pos.wy + params.blockPos.y;
	const wz = params.chunk.super.pos.wz + params.blockPos.z;

	_ = main.server.world.?.cmpxchgBlock(wx, wy, wz, params.block, self.block, false);
	return .handled;
}
