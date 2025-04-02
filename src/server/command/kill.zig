const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Kills the player";
pub const usage = "/kill";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /kill. Expected no arguments.", .{});
		return;
	}
	main.items.Inventory.Sync.addHealth(-std.math.floatMax(f32), .kill, .server, source.id);
}
