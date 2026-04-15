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

pub fn init(_: ZonElement) ?*@This() {
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
		neighborSupportive[neighbor.toInt()] = !neighborBlock.replacable() and neighborModel.neighborFacingQuads[neighbor.reverse().toInt()].len != 0;
	}

	var newBlock: Block = params.block;

	inline for (comptime std.meta.declarations(main.rotation.list)) |rotationMode| {
		if (params.block.mode() == main.rotation.getByID(rotationMode.name)) {
			if (@hasDecl(@field(main.rotation.list, rotationMode.name), "updateBlockFromNeighborConnectivity")) {
				@field(main.rotation.list, rotationMode.name).updateBlockFromNeighborConnectivity(&newBlock, neighborSupportive);
			} else {
				std.log.err("Rotation mode {s} has no updateBlockFromNeighborConnectivity function and cannot be used for {s} callback", .{rotationMode.name, @typeName(@This())});
			}
		}
	}

	if (newBlock == params.block) return .ignored;

	if (main.server.world.?.cmpxchgBlock(wx, wy, wz, params.block, newBlock) == null) {
		const dropAmount = params.block.mode().itemDropsOnChange(params.block, newBlock);
		const drops = params.block.blockDrops();
		for (0..dropAmount) |_| {
			for (drops) |drop| {
				if (drop.chance == 1 or main.random.nextFloat(&main.seed) < drop.chance) {
					for (drop.items) |stack| {
						var dir = main.vec.normalize(main.random.nextFloatVectorSigned(3, &main.seed));
						// Bias upwards
						dir[2] += main.random.nextFloat(&main.seed)*4.0;
						const model = params.block.mode().model(params.block).model();
						const pos = Vec3f{
							@as(f32, @floatFromInt(wx)) + model.min[0] + main.random.nextFloat(&main.seed)*(model.max[0] - model.min[0]),
							@as(f32, @floatFromInt(wy)) + model.min[1] + main.random.nextFloat(&main.seed)*(model.max[1] - model.min[1]),
							@as(f32, @floatFromInt(wz)) + model.min[2] + main.random.nextFloat(&main.seed)*(model.max[2] - model.min[2]),
						};
						main.server.world.?.drop(stack.clone(), pos, dir, 1);
					}
				}
			}
		}
		return .handled;
	}
	return .ignored;
}
