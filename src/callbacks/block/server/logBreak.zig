const std = @import("std");
const main = @import("main");
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const widerUpdaterRange = 5;

pub fn init(_: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	return result;
}

pub fn run(_: *@This(), params: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {
	const wx = params.chunk.super.pos.wx + params.x;
	const wy = params.chunk.super.pos.wy + params.y;
	const wz = params.chunk.super.pos.wz + params.z;

	if(main.server.world) |world| {
		for(0..widerUpdaterRange*2 + 1) |offsetX| {
			for(0..widerUpdaterRange*2 + 1) |offsetY| {
				for(0..widerUpdaterRange*2 + 1) |offsetZ| {
					const X = @as(i32, @intCast(offsetX)) - widerUpdaterRange;
					const Y = @as(i32, @intCast(offsetY)) - widerUpdaterRange;
					const Z = @as(i32, @intCast(offsetZ)) - widerUpdaterRange;

					// out of range
					if(X*X + Y*Y + Z*Z > widerUpdaterRange*widerUpdaterRange)
						continue;

					_ = world.updateSystem.add(Vec3i{wx + X, wy + Y, wz + Z});
				}
			}
		}
	}
	return .handled;
}
