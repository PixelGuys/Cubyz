const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 1.";
pub const usage = "/pos1";

const Args = union(enum) {
	@"/pos1": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/pos1"});

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const pos: Vec3i = @floor(source.player().pos);

	source.worldEditData.selectionPosition1 = pos;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos);

	source.sendMessage("Position 1: {}", .{pos});
}
