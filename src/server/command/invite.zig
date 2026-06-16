const std = @import("std");

const main = @import("main");
const User = main.server.User;
const command = main.server.command;

pub const description = "Invite a player";
pub const usage = "/invite <ip>";

const Args = union(enum) {
	@"/invite <ip>": struct { ip: []const u8 },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/invite"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const user = main.server.User.initAndIncreaseRefCount(main.server.connectionManager, result.@"/invite <ip>".ip) catch |err| {
		std.log.err("Error while trying to connect: {s}", .{@errorName(err)});
		source.sendMessage("#ff0000Error while trying to connect: {s}", .{@errorName(err)});
		return;
	};
	user.decreaseRefCount();
	return;
}
