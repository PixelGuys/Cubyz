const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Damages the player";
pub const usage = "/damage";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /clear. Expected no arguments.", .{});
		return;
	}
	main.items.Inventory.Sync.addHealth(-1, .kill, .server, source);
}