const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement, _: main.callbacks.Creator) ?*@This() {
	return @as(*@This(), undefined);
}

pub fn run(_: *@This(), params: main.callbacks.ParticleCollideCallback.Params) main.callbacks.Result {
	params.source.currentFrame = 0;
	return .handled;
}
