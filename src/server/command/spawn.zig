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
	//const pos = command.parseCoordinates(&split, source);

	var x: ?f64 = null;
	var y: ?f64 = null;
	var z: ?f64 = null;
	while (split.next()) |arg| {
		if (arg.len == 0) break;
		const num: f64 = std.fmt.parseFloat(f64, arg) catch {
			source.sendMessage("#ff0000Expected number, found \"{s}\"", .{arg});
			return;
		};
		if (x == null) {
			x = num;
		} else if (y == null) {
			y = num;
		} else if (z == null) {
			z = num;
		} else {
			source.sendMessage("#ff0000Too many arguments for command /spawn", .{});
			return;
		}
	}
	if (x == null) {
		source.sendMessage("#ffff00{}", .{source.spawnPos});
		return;
	}
	if (y == null) {
		source.sendMessage("#ff0000Invalid number of arguments for /spawn.\nUsage: \n" ++ usage, .{});
		return;
	}
	if (z == null) {
		z = source.player.pos[2];
	}
	x = std.math.clamp(x.?, -1e9, 1e9); // TODO: Remove after #310 is implemented
	y = std.math.clamp(y.?, -1e9, 1e9);
	z = std.math.clamp(z.?, -1e9, 1e9);

	source.spawnPos = .{x.?, y.?, z.?};
}
