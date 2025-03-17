const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Clears pos1 and pos2 of selection.";
pub const usage = "/deselect";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /deselect. Expected no arguments.", .{});
		return;
	}

	source.mutex.lock();
	source.commandData.selectionPosition1 = null;
	source.commandData.selectionPosition2 = null;
	source.mutex.unlock();

	main.network.Protocols.genericUpdate.sendWorldEditPos(source.conn, .clear, null);
	source.sendMessage("Cleared selection.", .{});
}
