const std = @import("std");

const main = @import("main");
const User = main.server.User;

const command = @import("_command.zig");

pub const description = "Get or set a players spawn point";
pub const usage =
	\\/spawn
	\\/spawn <x> <y> <z>
	\\/spawn @<playerIndex>
	\\/spawn @<playerIndex> <x> <y> <z>
;

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	const target = command.Target.init(&split, source) catch return;
	defer target.deinit();
	if (split.peek().?.len > 0) {
		const pos = command.parseCoordinates(&split, source) catch return;
		if (split.next()) |_| {
			source.sendMessage("#ff0000Too many arguments for command /spawn", .{});
			return;
		}
		target.user.spawnPos = pos;
	} else {
		source.sendMessage("#ffff00{}", .{target.user.spawnPos});
	}
}
