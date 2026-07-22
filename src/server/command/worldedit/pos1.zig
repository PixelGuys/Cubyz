const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 1.";
pub const usage = "/pos1";

pub const Args = union(enum) {
	@"/pos1": struct {},
};

pub fn execute(_: Args, source: *User) void {
	const pos: Vec3i = @floor(source.player().pos);

	source.worldEditData.selectionPosition1 = pos;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos1, pos);

	source.sendMessage("Position 1: {}", .{pos});
}
