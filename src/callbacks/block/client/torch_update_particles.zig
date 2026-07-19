const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const particles = main.particles;

pub fn init(_: ZonElement, _: main.callbacks.Creator) ?*anyopaque {
	return @as(*anyopaque, undefined);
}

pub fn run(_: *anyopaque, params: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	var emitter: particles.Emitter = undefined;
	const emitterProperties = particles.EmitterProperties{
		.speed = .init(0.15, 0.2),
		.lifeTime = .init(0.25, 0.5),
		.randomizeRotation = false,
	};
	emitter = .init("cubyz:flame", false, .{.point = .{}}, emitterProperties, .spread);
	emitter.spawnParticles(@as(vec.Vec3f, @floatFromInt(params.blockPos)) + vec.Vec3f{0.5, 0.5, 0.85}, 1);
	return .handled;
}
