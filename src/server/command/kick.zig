const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Kicks a player";
pub const usage = "/kick @<playerIndex>";

pub const Args = union(enum) {
	@"/kick <playerIndex>": struct { playerIndex: command.PlayerIndex },
};

pub fn execute(args: *Args, source: *User) void {
	const target = command.Target.fromPlayerIndex(args.@"/kick <playerIndex>".playerIndex, source) catch return;
	defer target.deinit();

	target.user.conn.disconnect();
	main.server.sendMessage("{s}§#ffff00 has been kicked from the server", .{target.user.name});
}
