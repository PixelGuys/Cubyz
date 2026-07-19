const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Clears pos1 and pos2 of selection.";
pub const usage = "/deselect";

pub const Args = union(enum) {
	@"/deselect": struct {},
};

pub fn execute(_: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doens't support running from console", .{});
		return;
	}
	const source = _source.user;
	source.worldEditData.selectionPosition1 = null;
	source.worldEditData.selectionPosition2 = null;

	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .clear, null);
	source.sendMessage("Cleared selection.", .{});
}
