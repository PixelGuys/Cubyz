const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Clears pos1 and pos2 of selection.";
pub const usage = "/deselect";

pub const Args = union(enum) {
	@"/deselect": struct {},
};

pub fn execute(_: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	user.worldEditData.selectionPosition1 = null;
	user.worldEditData.selectionPosition2 = null;

	main.network.protocols.genericUpdate.sendWorldEditPos(user.conn, .clear, null);
	user.sendMessage("Cleared selection.", .{});
}
