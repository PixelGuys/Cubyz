const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const description = "Select the player's position as position 2.";
pub const usage = "//pos2";
pub const commandNameOverride: ?[]const u8 = "/pos2";

pub var pos: Vec3i = .{0, 0, 0};

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command //pos2. Expected no arguments.", .{});
		return;
	}
	pos[0] = @intFromFloat(source.player.pos[0]);
	pos[1] = @intFromFloat(source.player.pos[1]);
	pos[2] = @intFromFloat(source.player.pos[2]);

	source.sendMessage("Position 2: ({}, {}, {})", .{pos[0], pos[1], pos[2]});
}
