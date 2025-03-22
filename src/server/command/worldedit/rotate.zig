const std = @import("std");

const main = @import("root");
const User = main.server.User;

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
	const current = source.worldEditData.clipboard.?;
	defer current.deinit(main.globalAllocator);
	source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, .@"90");
}
