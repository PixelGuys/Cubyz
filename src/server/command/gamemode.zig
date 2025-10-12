const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set your gamemode.";
pub const usage = "/gamemode\n/gamemode <survival/creative>";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len == 0) {
		source.sendMessage("#ffff00{s}", .{@tagName(source.gamemode.load(.monotonic))});
		return;
	}
	if(std.ascii.eqlIgnoreCase(args, "survival") or std.ascii.eqlIgnoreCase(args, "s")) {
		main.items.Inventory.Sync.setGamemode(source, .survival);
	} else if(std.ascii.eqlIgnoreCase(args, "creative") or std.ascii.eqlIgnoreCase(args, "c")) {
		main.items.Inventory.Sync.setGamemode(source, .creative);
	} else {
		source.sendMessage("#ff0000Invalid argument for command /gamemode. Must be '[s]urvival' or '[c]reative'.", .{});
		return;
	}
}
