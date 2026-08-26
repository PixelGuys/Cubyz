const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const Neighbor = main.chunk.Neighbor;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const ZonElement = main.ZonElement;
const server = main.server;
const BlockDrop = main.server.BlockDrop;

pub fn init(_: ZonElement, _: main.callbacks.Creator) ?*@This() {
	return @as(*@This(), undefined);
}

pub fn run(_: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.blockPos.x;
	const wy = params.chunk.super.pos.wy + params.blockPos.y;
	const wz = params.chunk.super.pos.wz + params.blockPos.z;

	var neighborSupportive: [6]bool = undefined;

	for (Neighbor.iterable) |neighbor| {
		const neighborBlock: Block = main.server.world.?.getBlock(wx +% neighbor.relX(), wy +% neighbor.relY(), wz +% neighbor.relZ()) orelse .{.typ = 0, .data = 0};
		const neighborModel = main.blocks.meshes.model(neighborBlock).model();
		neighborSupportive[neighbor.toInt()] = !neighborBlock.replaceable() and neighborModel.neighborFacingQuads[neighbor.reverse().toInt()].len != 0;
	}

	var newBlock: Block = params.block;

	inline for (comptime std.meta.declarations(main.rotation.rotations)) |rotationMode| {
		if (params.block.mode() == main.rotation.getByID(rotationMode.name)) {
			if (@hasDecl(@field(main.rotation.rotations, rotationMode.name), "updateBlockFromNeighborConnectivity")) {
				@field(main.rotation.rotations, rotationMode.name).updateBlockFromNeighborConnectivity(&newBlock, neighborSupportive);
			} else {
				std.log.err("Rotation mode {s} has no updateBlockFromNeighborConnectivity function and cannot be used for {s} callback", .{rotationMode.name, @typeName(@This())});
			}
		}
	}

	if (newBlock == params.block) return .ignored;

	if (main.server.world.?.cmpxchgBlock(wx, wy, wz, params.block, newBlock) == null) {
		const dropCtx = BlockDrop.Context{
			.oldBlock = params.block,
			.newBlock = newBlock,
			.modelIndex = params.block.mode().model(params.block),
		};
		dropCtx.dropNaturally(.{wx, wy, wz});
		return .handled;
	}
	return .ignored;
}
