const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Kills the player";
pub const usage =
	\\/kill
	\\/kill @<playerIndex>
;

const Args = union(enum) {
	@"/kill <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/kill"});

pub fn execute(args: []const u8, source: Source) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const target = command.Target.fromPlayerIndex(result.@"/kill <playerIndex>".playerIndex, source) catch return;
	defer target.deinit();

	main.sync.addHealth(-std.math.floatMax(f32), .kill, .server, target.user.id);
}
