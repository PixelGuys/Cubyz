const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears pos1 and pos2 of selection.";
pub const usage = "/deselect";

pub const Args = union(enum) {
	@"/deselect": struct {},
};

pub fn execute(_: Args, source: *User) void {
	source.worldEditData.selectionPosition1 = null;
	source.worldEditData.selectionPosition2 = null;

	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .clear, null);
	source.sendMessage("Cleared selection.", .{});
}
