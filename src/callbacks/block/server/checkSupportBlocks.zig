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

	for(Neighbor.iterable) |neighbor| {
		const neighborBlock: Block = main.server.world.?.getBlock(wx +% neighbor.relX(), wy +% neighbor.relY(), wz +% neighbor.relZ()) orelse .{.typ = 0, .data = 0};
		const neighborModel = main.blocks.meshes.model(neighborBlock).model();
		neighborSupportive[neighbor.toInt()] = !neighborBlock.replacable() and neighborModel.neighborFacingQuads[neighbor.reverse().toInt()].len != 0;
	}

	var newBlock: Block = params.block;

	if(params.block.mode() == main.rotation.getByID("cubyz:torch")) {
		var data: main.rotation.list.@"cubyz:torch".TorchData = @bitCast(@as(u5, @truncate(params.block.data)));
		if(data.center and !neighborSupportive[Neighbor.dirDown.toInt()]) data.center = false;
		if(data.negX and !neighborSupportive[Neighbor.dirNegX.toInt()]) data.negX = false;
		if(data.posX and !neighborSupportive[Neighbor.dirPosX.toInt()]) data.posX = false;
		if(data.negY and !neighborSupportive[Neighbor.dirNegY.toInt()]) data.negY = false;
		if(data.posY and !neighborSupportive[Neighbor.dirPosY.toInt()]) data.posY = false;
		newBlock.data = @as(u5, @bitCast(data));
		if(newBlock.data == 0) newBlock.typ = 0;
	} else {
		std.log.err("Expected {s} to have cubyz:decayable or cubyz:branch as rotation", .{params.block.id()});
	}

	if(newBlock == params.block) return .ignored;

	if(main.server.world.?.cmpxchgBlock(wx, wy, wz, params.block, newBlock) == null) {
		const drops = params.block.blockDrops();
		for(drops) |drop| {
			if(drop.chance == 1 or main.random.nextFloat(&main.seed) < drop.chance) {
				for(drop.items) |stack| {
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
		return .handled;
	}
	return .ignored;
}
