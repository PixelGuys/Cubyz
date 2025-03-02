const std = @import("std");

const main = @import("root");
const User = main.server.User;

const pos = @import("pos2.zig");

pub const description = "Show previously selected 2nd position coordinates.";
pub const usage = "//showpos2";
pub const commandNameOverride: ?[]const u8 = "/showpos2";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command //showpos2. Expected no arguments.", .{});
		return;
	}
	source.sendMessage("Position 2: ({}, {}, {})", .{pos.pos[0], pos.pos[1], pos.pos[2]});
}
