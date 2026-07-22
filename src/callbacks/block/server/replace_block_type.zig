const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;

blockTyp: u16,

pub fn init(zon: main.ZonElement, creator: main.callbacks.Creator) ?*@This() {
	const replacedBlock = switch (creator) {
		.block => |b| b,
	};
	const result = main.worldArena.create(@This());
	const blockTyp = main.blocks.getTypeById(zon.get([]const u8, "block") orelse {
		std.log.err("Missing field \"block\" for replace_blockType event", .{});
		return null;
	});
	const block: Block = .{
		.typ = blockTyp,
		.data = 0,
	};
	if (replacedBlock.mode() != block.mode()) {
		std.log.err("The replaced and replacing blocks' rotation modes don't match in replace_blockType event", .{});
		return null;
	}
	result.* = .{
		.blockTyp = blockTyp,
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.blockPos.x;
	const wy = params.chunk.super.pos.wy + params.blockPos.y;
	const wz = params.chunk.super.pos.wz + params.blockPos.z;

	const replacingBlock: Block = .{
		.typ = self.blockTyp,
		.data = params.block.data,
	};
	_ = main.server.world.?.cmpxchgBlock(wx, wy, wz, params.block, replacingBlock);
	return .handled;
}
