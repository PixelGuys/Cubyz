const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Get or set a player's gamemode.";
pub const usage =
	\\/gamemode <survival/creative>
	\\/gamemode @playerIndex <survival/creative>
	\\/gamemode
	\\/gamemode @playerIndex
;

pub const Args = union(enum) {
	@"/gamemode <playerIndex> <mode>": struct { playerIndex: ?command.PlayerIndex, mode: ?main.game.Gamemode },
};

pub fn execute(result: Args, source: *User) void {
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
