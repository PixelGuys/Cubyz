const std = @import("std");

const main = @import("main");
const User = main.server.User;
const command = main.server.command;

pub const description = "Kicks a player";
pub const usage = "/kick @<playerId>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /kick. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');

	const target = command.Target.init(&split, source) catch return;
	defer target.deinit();

	target.user.conn.disconnect();
	main.server.sendMessage("{s}§#ffff00 has been kicked from the server", .{target.user.name});
}
