const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Get or set the players gamemode.";
pub const usage =
	\\/gamemode <survival/creative>
	\\/gamemode @playerIndex <survival/creative>
	\\/gamemode
	\\/gamemode @playerIndex
;

const Args = union(enum) {
	@"/gamemode <playerIndex> <mode>": struct { playerIndex: ?command.PlayerIndex, mode: main.game.Gamemode },
	@"/gamemode <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/gamemode"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/gamemode <playerIndex> <mode>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();

			main.sync.setGamemode(target.user, params.mode);
		},
		.@"/gamemode <playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			source.sendMessage("#ffff00{s}", .{@tagName(target.user.gamemode.load(.monotonic))});
		},
	}
}
