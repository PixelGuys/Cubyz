const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

message: []const u8,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.message = main.worldArena.dupe(u8, zon.get(?[]const u8, "name", null) orelse {
			std.log.err("Missing field \"name\" for message event.", .{});
			return null;
		}),
	};
	return result;
}

pub fn run(_: *@This(), _: main.callbacks.ItemUsedCallback.Params) main.callbacks.Result {
	main.network.protocols.chat.send(main.game.world.?.conn, "HEY");
	return .handled;
}
