const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Kicks a player";
pub const usage = "/kick @<playerIndex>";

const Args = union(enum) {
	@"/kick <playerIndex>": struct { playerIndex: command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/kick"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	const target = command.Target.fromPlayerIndex(result.@"/kick <playerIndex>".playerIndex, source) catch return;
	defer target.deinit();

	target.user.conn.disconnect();
	main.server.sendMessage("{s}§#ffff00 has been kicked from the server", .{target.user.name});
}
