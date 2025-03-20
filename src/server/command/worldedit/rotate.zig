const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const copy = @import("copy.zig");

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage = "/rotate";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /rotate. Expected no arguments.", .{});
		return;
	}
	if(source.worldEditData.clipboard == null) {
		source.sendMessage("#ff0000Error: No clipboard content to rotate.", .{});
	}
	var current = source.worldEditData.clipboard.?;
	source.worldEditData.clipboard = null;
	defer current.deinit(main.globalAllocator);

	const rotated = current.rotateZ(main.globalAllocator, .@"90");
	source.worldEditData.clipboard = rotated;
}
