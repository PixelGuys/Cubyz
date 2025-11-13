const std = @import("std");

const main = @import("main");
const User = main.server.User;

const command = @import("_command.zig");

pub const description = "Shows info about all the commands.";
pub const usage = "/help\n/help <command>";

pub fn execute(args: []const u8, source: *User) void {
	var msg = main.List(u8).init(main.stackAllocator);
	defer msg.deinit();
	msg.appendSlice("#ffff00");
	if(args.len == 0) {
		var iterator = command.commands.valueIterator();
		while(iterator.next()) |cmd| {
			msg.append('/');
			msg.appendSlice(cmd.name);
			msg.appendSlice(": ");
			msg.appendSlice(cmd.description);
			msg.append('\n');
		}
		msg.appendSlice("\nUse /help <command> for usage of a specific command.\n");
	} else {
		var split = std.mem.splitScalar(u8, args, ' ');
		while(split.next()) |arg| {
			if(command.commands.get(arg)) |cmd| {
				msg.append('/');
				msg.appendSlice(cmd.name);
				msg.appendSlice(": ");
				msg.appendSlice(cmd.description);
				msg.append('\n');
				msg.appendSlice(cmd.usage);
				msg.append('\n');
			} else {
				msg.appendSlice("#ff0000Unrecognized Command \"");
				msg.appendSlice(arg);
				msg.appendSlice("\"#ffff00\n");
			}
		}
	}
	if(msg.items[msg.items.len - 1] == '\n') _ = msg.pop();
	source.sendMessage("{s}", .{msg.items});
}
