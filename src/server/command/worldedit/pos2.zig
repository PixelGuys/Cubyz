const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 2.";
pub const usage = "/pos2";

const Args = union(enum) {
	@"/pos2": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/pos2"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const pos: Vec3i = @floor(source.player().pos);

	source.worldEditData.selectionPosition2 = pos;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos2, pos);

	source.sendMessage("Position 2: {}", .{pos});
}
