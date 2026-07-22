const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set the server's random tickrate, measured in blocks per chunk per tick.";
pub const usage =
	\\/tickspeed
	\\/tickspeed <rate>
;

pub const Args = union(enum) {
	@"/tickspeed <rate>": struct { rate: u32 },
	@"/tickspeed": struct {},
};

pub fn execute(args: Args, source: *User) void {
	switch (args) {
		.@"/tickspeed <rate>" => |tickSpeed| main.server.world.?.tickSpeed.store(tickSpeed.rate, .monotonic),
		.@"/tickspeed" => {},
	}
	source.sendMessage("#ffff00{}", .{main.server.world.?.tickSpeed.load(.monotonic)});
}
