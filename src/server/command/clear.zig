const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears your inventory";
pub const usage = "/clear";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /clear. Expected no arguments.", .{});
		return;
	}
	main.items.Inventory.Sync.ServerSide.clearPlayerInventory(source);
}
