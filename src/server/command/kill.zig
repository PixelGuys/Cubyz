const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Kills the player";
pub const usage =
	\\/kill
	\\/kill @<playerIndex>
;

pub const Args = union(enum) {
	@"/kill <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

pub fn execute(args: Args, source: *User) void {
	const target = command.Target.fromPlayerIndex(args.@"/kill <playerIndex>".playerIndex, source) catch return;
	defer target.deinit();

	main.sync.addHealth(-std.math.floatMax(f32), .kill, .server, target.user.id);
}
