const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 1.";
pub const usage = "/pos1";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /pos1. Expected no arguments.", .{});
		return;
	}

	const pos: Vec3i = @intFromFloat(source.player.pos);

	source.worldEditData.selectionPosition1 = pos;
	main.network.Protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos);

	source.sendMessage("Position 1: {}", .{pos});
}
