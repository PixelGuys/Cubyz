const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/stop
	\\/stop <restart>
;

const Args = union(enum) {
	@"/stop <restart>": struct { restart: ?enum { restart } },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/stop"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (result.@"/stop <restart>".restart != null) {
		main.server.restart.store(true, .release);
	}
	main.server.running.store(false, .release);
}
