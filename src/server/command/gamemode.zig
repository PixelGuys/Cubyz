const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Get or set a player's gamemode.";
pub const usage =
	\\/gamemode <survival/creative>
	\\/gamemode @playerIndex <survival/creative>
	\\/gamemode
	\\/gamemode @playerIndex
;

const Args = union(enum) {
	@"/gamemode <playerIndex> <mode>": struct { playerIndex: ?command.PlayerIndex, mode: ?main.game.Gamemode },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/gamemode"});

pub fn execute(args: []const u8, source: Source) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/gamemode <playerIndex> <mode>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();

			if (params.mode) |mode| {
				main.sync.setGamemode(target.user, mode);
			} else {
				source.sendMessage("#ffff00{s}", .{@tagName(target.user.gamemode.load(.monotonic))});
			}
		},
	}
}
