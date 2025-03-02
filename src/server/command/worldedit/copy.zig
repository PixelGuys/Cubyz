const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const pos1 = @import("pos1.zig");
const pos2 = @import("pos2.zig");

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Copy selection to clipboard.";
pub const usage = "//copy";
pub const commandNameOverride: ?[]const u8 = "/copy";

pub var clipboard: ?*Blueprint = null;
pub var playerOffset: main.vec.Vec3i = .{0, 0, 0};

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command //copy. Expected no arguments.", .{});
		return;
	}
	source.sendMessage(
		"Copying: ({d:.3}, {d:.3}, {d:.3}) ({d:.3}, {d:.3}, {d:.3})",
		.{pos1.pos[0], pos1.pos[1], pos1.pos[2], pos2.pos[0], pos2.pos[1], pos2.pos[2]}
	);
	playerOffset = .{
		pos1.pos[0] - @as(i32, @intFromFloat(source.player.pos[0])),
		pos1.pos[1] - @as(i32, @intFromFloat(source.player.pos[1])),
		pos1.pos[2] - @as(i32, @intFromFloat(source.player.pos[2])),
	};
	// For some reason doesn't work. WIP - don't approve.
	// if (clipboard) |c| c.deinit();

	clipboard = Blueprint.capture(main.blueprint.arenaAllocator, pos1.pos, pos2.pos) catch |err| {
		source.sendMessage("#ff0000Error: {s}", .{err});
		return;
	};
}
