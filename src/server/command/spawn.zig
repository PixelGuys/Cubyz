const std = @import("std");

const main = @import("main");
const User = main.server.User;

const command = @import("_command.zig");

pub const description = 
    \\Get or set the player / world spawn point
    \\Note: when setting the world spawn point, the change will only apply to new players. Players who where already once on the server retain their old spawn point
;
pub const usage =
	\\/spawn
	\\/spawn <x> <y> <z>
	\\/spawn world
	\\/spawn world <x> <y> <z>
;

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.peek().?.len > 0) {
		if (std.mem.eql(u8, split.peek().?, "world")) {
			_ = split.next();
			if (split.peek() == null or split.peek().?.len == 0) {
				const world = main.server.world.?;
				source.sendMessage("#ffff00World spawn: {}", .{world.spawn});
				return;
			}
			const pos = command.parseCoordinates(&split, source) catch return;
			if (split.next()) |_| {
				source.sendMessage("#ff0000Too many arguments for command /spawn", .{});
				return;
			}
			const world = main.server.world.?;
			world.spawn = @intFromFloat(pos);
			return;
		}

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
