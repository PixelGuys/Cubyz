const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Get or set a player's / the world spawn point";
pub const usage =
	\\/spawn
	\\/spawn <x> <y> <z>
	\\/spawn @<playerIndex>
	\\/spawn @<playerIndex> <x> <y> <z>
	\\/spawn world
	\\/spawn world <x> <y> <z>
;

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	const target = command.Target.init(&split, source) catch return;
	defer target.deinit();
	if (split.peek() != null and split.peek().?.len > 0) {
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
			world.spawn = @trunc(pos);
			return;
		}

		const pos = command.parseCoordinates(&split, source) catch return;
		if (split.next()) |_| {
			source.sendMessage("#ff0000Too many arguments for command /spawn", .{});
			return;
		}
		target.user.spawnPos = pos;
	} else {
		source.sendMessage("#ffff00{}", .{target.user.getSpawnPos()});
	}
}
