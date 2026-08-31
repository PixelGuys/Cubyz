const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

respawnEffeciency: f32,

pub fn init(zon: ZonElement, _: main.callbacks.Creator) ?*anyopaque {
	const result = main.worldArena.create(@This());
	result.* = .{
		.respawnEffeciency = zon.get(f32, "respawnEffeciency") orelse 1.0,
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	main.sync.setSpawn(params.blockPos, self.respawnEffeciency, .client, main.game.Player.id);
	return .handled;
}
