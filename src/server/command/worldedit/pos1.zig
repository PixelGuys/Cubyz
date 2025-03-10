const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Select the player's position as position 1.";
pub const usage = "/pos1";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /pos1. Expected no arguments.", .{});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	source.commandData.selectionPosition1 = .{
		@intFromFloat(source.player.pos[0]),
		@intFromFloat(source.player.pos[1]),
		@intFromFloat(source.player.pos[2]),
	};

	main.network.Protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, source.commandData.selectionPosition1.?);

	const pos = source.commandData.selectionPosition1.?;
	source.sendMessage("Position 1: ({}, {}, {})", .{pos[0], pos[1], pos[2]});
}
