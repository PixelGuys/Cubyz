const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/server <stop/restart>
;

const Args = union(enum) {
	@"/server <action>": struct { action: enum { stop, restart } },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/server"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	switch (result.@"/server <action>".action) {
		.stop => {},
		.restart => {
			main.server.restart.store(true, .release);
		},
	}
	main.server.stop();
}
