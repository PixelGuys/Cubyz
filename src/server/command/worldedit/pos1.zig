const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 1.";
pub const usage = "/pos1";

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	if (args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /pos1. Expected no arguments.", .{});
		return;
	}

	const pos: Vec3i = @floor(source.player().pos);

	source.worldEditData.selectionPosition1 = pos;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos);

	source.sendMessage("Position 1: {}", .{pos});
}
