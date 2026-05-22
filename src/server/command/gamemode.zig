const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set your gamemode.";
pub const usage = "/gamemode\n/gamemode <survival/creative>";

const Args = union(enum) {
	@"/gamemode <mode>": struct { mode: main.game.Gamemode },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/gamemode"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	main.sync.setGamemode(source, result.@"/gamemode <mode>".mode);
}
