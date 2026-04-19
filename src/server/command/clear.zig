const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /clear. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /clear", .{});
			return;
		}
		if (std.ascii.eqlIgnoreCase(arg, "inventory")) {
			main.items.Inventory.ServerSide.clearPlayerInventory(source);
		} else if (std.ascii.eqlIgnoreCase(arg, "chat")) {
			main.network.protocols.genericUpdate.sendClear(source.conn, .chat);
		} else {
			source.sendMessage("#ff0000Expected either inventory or chat, found \"{s}\"", .{arg});
		}
	}
}
