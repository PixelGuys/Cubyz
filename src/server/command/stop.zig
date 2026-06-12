const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/stop
;

const Args = union(enum) {
	@"/stop": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/stop"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = args;
	_ = source;

	main.server.running.store(false, .release);
}
