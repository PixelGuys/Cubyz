const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const Server = main.server;


pub fn init(_: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	return result;
}

pub fn run(_: *@This(), param: main.callbacks.ServerBlockCallback.Params) main.callbacks.Result {	
	if(Server.world)|world|{

		//Make leaves question themself: Do i have to decay?
		const logRange = 3;
		for (0..logRange*2+1) |offsetX| {
			for (0..logRange*2+1) |offsetY| {
				for (0..logRange*2+1) |offsetZ| {
					const x = param.x+@as(i32,@intCast(offsetX))-logRange;
					const y = param.y+@as(i32,@intCast(offsetY))-logRange;
					const z = param.z+@as(i32,@intCast(offsetZ))-logRange;
					if(x != param.x or y != param.y or param.z != z){
						world.delayedEventQueue.pushBack(.{
							.x = x,
							.y = y,
							.z = z,
						});
					}
				}
			}
		}
	}
    return .handled;
}
