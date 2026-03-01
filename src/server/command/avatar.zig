const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Change your avatar";
pub const usage = "/avatar <entityTypeID>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /avatar. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /avatar", .{});
			return;
		}
		if (main.entity.clientEntityTypes.get(arg)) |entityType| {
			for (main.server.connectionManager.connections.items) |value| {
				main.network.protocols.Customization.send(value, source.id, entityType.id);
			}
			source.sendMessage("#00ff00entityTypeID was changed to {s}.", .{arg});
		} else {
			source.sendMessage("#ff0000entityTypeID {s} doesnt exist", .{arg});
		}
	}
}
