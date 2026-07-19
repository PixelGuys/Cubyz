const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 2.";
pub const usage = "/pos2";

pub const Args = union(enum) {
	@"/pos2": struct {},
};

pub fn execute(_: Args, source: *User) void {
	const pos: Vec3i = @floor(source.player().pos);

	source.worldEditData.selectionPosition2 = pos;
	main.network.protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos2, pos);

	source.sendMessage("Position 2: {}", .{pos});
}
