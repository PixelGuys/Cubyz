const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Set edit mask. When used with no mask expression it will clear current mask.";
pub const usage =
	\\/mask <mask>
	\\/mask
;

const Args = union(enum) {
	@"/mask <mask>": struct { mask: ?command.MaskExpression },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/mask"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (result.@"/mask <mask>".mask) |mask| {
		source.worldEditData.mask = mask.mask;
		source.sendMessage("#00ff00Mask set.", .{});
	} else {
		if (source.worldEditData.mask) |mask| mask.deinit(main.globalAllocator);
		source.worldEditData.mask = null;
		source.sendMessage("#00ff00Mask cleared.", .{});
		return;
	}
}
