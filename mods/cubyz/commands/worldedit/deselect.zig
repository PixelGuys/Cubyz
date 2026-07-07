const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears pos1 and pos2 of selection.";
pub const usage = "/deselect";

const Args = union(enum) {
	@"/deselect": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/deselect"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	source.worldEditData.selectionPosition1 = null;
	source.worldEditData.selectionPosition2 = null;

	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .clear, null);
	source.sendMessage("Cleared selection.", .{});
}
