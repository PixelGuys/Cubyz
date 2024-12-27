const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Get or set your gamemode.";
pub const usage = "/gamemode\n/gamemode <survival/creative>";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len == 0) {
		const msg = std.fmt.allocPrint(main.stackAllocator.allocator, "#ffff00{s}", .{@tagName(source.gamemode.load(.monotonic))}) catch unreachable;
		defer main.stackAllocator.free(msg);
		source.sendMessage(msg);
		return;
	}
	if(std.ascii.eqlIgnoreCase(args, "survival")) {
		main.items.Inventory.Sync.setGamemode(source, .survival);
	} else if(std.ascii.eqlIgnoreCase(args, "creative")) {
		main.items.Inventory.Sync.setGamemode(source, .creative);
	} else {
		source.sendMessage("#ff0000Invalid argument for command /gamemode. Must be 'survival' or 'creative'.");
		return;
	}
}