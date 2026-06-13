const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const User = main.server.User;

pub const description = "Kicks a player";
pub const usage = "/kick @<playerIndex>";

const Args = union(enum) {
	@"/kick <playerIndex>": struct { playerIndex: command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/kick"});

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var errorMessage: main.List(u8) = .empty;
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
