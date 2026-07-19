const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Get the world seed.";
pub const usage =
	\\/seed
;

const Args = union(enum) {
	@"/seed": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/seed"});

pub fn execute(args: []const u8, source: Source) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	source.sendMessage("#ffff00{}", .{main.server.world.?.settings.seed});
}
