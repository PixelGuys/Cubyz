const std = @import("std");

const main = @import("root");
const User = main.server.User;
const Vec3i = main.vec.Vec3i;

pub const description = "Select the player position as position 2.";
pub const usage = "/pos2";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /pos2. Expected no arguments.", .{});
		return;
	}

	const pos: Vec3i = @intFromFloat(source.player.pos);

	source.worldEditData.selectionPosition2 = pos;
	main.network.Protocols.genericUpdate.sendWorldEditPos(source.conn, .selectedPos2, pos);

	source.sendMessage("Position 2: {}", .{pos});
}
