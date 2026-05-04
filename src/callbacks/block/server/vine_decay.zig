const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const ZonElement = main.ZonElement;
const server = main.server;

pub fn init(_: ZonElement) ?*@This() {
	return main.worldArena.create(@This());
}
pub fn run(_: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.blockPos.x;
	const wy = params.chunk.super.pos.wy + params.blockPos.y;
	const wz = params.chunk.super.pos.wz + params.blockPos.z;

	if (params.block.mode() != main.rotation.getByID("cubyz:hanging")) {
		std.log.err("Expected {s} to have cubyz:hanging as rotation", .{params.block.id()});
		return .ignored;
	}

	const world = server.world orelse return .ignored;
	const thisBlock = world.getBlock(wx, wy, wz) orelse return .ignored;

	if (params.block != thisBlock) return .ignored;

	const blockAbove = world.getBlock(wx, wy, wz +% 1) orelse return .ignored;
	const blockAboveModel = blocks.meshes.model(blockAbove).model();

	if (blockAbove.typ == params.block.typ) return .ignored;
	if (blockAbove.replaceable()) return decay(wx, wy, wz, thisBlock);
	if (blockAboveModel.neighborFacingQuads[main.chunk.Neighbor.dirDown.toInt()].len == 0) return decay(wx, wy, wz, thisBlock);

	return .ignored;
}

fn decay(x: i32, y: i32, z: i32, current: Block) main.callbacks.Result {
	if (server.world.?.cmpxchgBlock(x, y, z, current, blocks.Block.air) == null) return .handled;
	return .ignored;
}
