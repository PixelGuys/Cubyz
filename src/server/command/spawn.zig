const std = @import("std");

const main = @import("main");
const User = main.server.User;

const command = @import("_command.zig");

pub const description = "Get or set the player spawn point";
pub const usage =
	\\/spawn
	\\/spawn <x> <y> <z>
;

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.peek().?.len > 0) {
		const pos = command.parseCoordinates(&split, source) catch return;
		if (split.next()) |_| {
			source.sendMessage("#ff0000Too many arguments for command /spawn", .{});
			return;
		}
		source.spawnPos = pos;
	} else {
		source.sendMessage("#ffff00{}", .{source.spawnPos});
	}
}
