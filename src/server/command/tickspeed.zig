const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set the server's random tickrate, measured in blocks per chunk per tick.";
pub const usage = "/tickspeed\n/tickspeed <rate>";

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	if(split.next()) |arg| blk: {
		if(arg.len == 0) break :blk;
		if(split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /tickspeed", .{});
			return;
		}
		const tickSpeed = std.fmt.parseInt(u32, arg, 0) catch {
			source.sendMessage("#ff0000Expected u32 number, found \"{s}\"", .{arg});
			return;
		};
		main.server.world.?.tickSpeed.store(tickSpeed, .monotonic);
		return;
	}
	source.sendMessage("#ffff00{}", .{main.server.world.?.tickSpeed.load(.monotonic)});
}
