const std = @import("std");

const main = @import("main");
const User = main.server.User;
const command = main.server.command;

pub const description = "Invite a player";
pub const usage = "/invite <ip>";

pub const Args = union(enum) {
	@"/invite <ip>": struct { ip: []const u8 },
};

pub fn execute(args: Args, source: *User) void {
	const user = main.server.User.initAndIncreaseRefCount(main.server.connectionManager, args.@"/invite <ip>".ip) catch |err| {
		std.log.err("Error while trying to connect: {s}", .{@errorName(err)});
		source.sendMessage("#ff0000Error while trying to connect: {s}", .{@errorName(err)});
		return;
	};
	user.decreaseRefCount();
	return;
}
