const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Kills yourself";
pub const usage =
	\\/unstuck
;

pub const Args = union(enum) {
	@"/unstuck": struct {},
};

pub fn execute(args: Args, source: Source) void {
	_ = args;

	main.sync.addHealth(-std.math.floatMax(f32), .kill, .server, source.user.id);
}