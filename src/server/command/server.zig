const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/server <stop/restart>
;

const Args = union(enum) {
	@"/server <action>": struct { action: main.server.stopType },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/server"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (result.@"/server <action>".action == .restart and !main.settings.launchConfig.headlessServer) {
		source.sendMessage("#ff0000Headfull restart isn't supported yet.", .{});
		return;
	}

	main.server.stop(result.@"/server <action>".action);
}
