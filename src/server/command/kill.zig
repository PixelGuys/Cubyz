const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

const @"cubyz:health" = main.entity.components.@"cubyz:health";

pub const description = "Kills the player";
pub const usage =
	\\/kill
	\\/kill @<playerIndex>
;

pub const Args = union(enum) {
	@"/kill <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

pub fn execute(args: Args, source: Source) void {
	const target = command.Target.fromPlayerIndex(args.@"/kill <playerIndex>".playerIndex, source) catch return;

	@"cubyz:health".server.addHealth(target.user.id, -std.math.floatMax(f32));
}
