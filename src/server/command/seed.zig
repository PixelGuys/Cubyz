const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get the world seed.";
pub const usage =
	\\/seed
;

pub const Args = union(enum) {
	@"/seed": struct {},
};

pub fn execute(_: *Args, source: *User) void {
	source.sendMessage("#ffff00{}", .{main.server.world.?.settings.seed});
}
