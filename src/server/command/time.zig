const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Get or set the server time.";
pub const usage = "/time\n/time <day/night>\n/time <time>";

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	if(split.next()) |arg| blk: {
		if(arg.len == 0) break :blk;
		var gameTime: i64 = undefined;
		if(std.ascii.eqlIgnoreCase(arg, "day")) {
			gameTime = 0;
		} else if(std.ascii.eqlIgnoreCase(arg, "night")) {
			gameTime = main.server.ServerWorld.dayCycle/2;
		} else {
			gameTime = std.fmt.parseInt(i64, arg, 0) catch {
				const msg = std.fmt.allocPrint(main.stackAllocator.allocator, "#ff0000Expected i64 number, found \"{s}\"", .{arg}) catch unreachable;
				defer main.stackAllocator.free(msg);
				source.sendMessage(msg);
				return;
			};
		}
		if(split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /time");
			return;
		}
		main.server.world.?.gameTime = gameTime;
		return;
	}
	const msg = std.fmt.allocPrint(main.stackAllocator.allocator, "#ffff00{}", .{main.server.world.?.gameTime}) catch unreachable;
	defer main.stackAllocator.free(msg);
	source.sendMessage(msg);
}