const std = @import("std");

const main = @import("root");
const User = main.server.User;
const Degrees = main.rotation.Degrees;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage = "/rotate [0|90|180|270]";

pub fn execute(args: []const u8, source: *User) void {
	var angle: Degrees = .@"90";
	if(args.len != 0) {
		angle = if(std.mem.eql(u8, args, "0")) .@"0" else if(std.mem.eql(u8, args, "90")) .@"90" else if(std.mem.eql(u8, args, "180")) .@"180" else if(std.mem.eql(u8, args, "270")) .@"270" else {
			source.sendMessage("#ff0000Error: Invalid angle '{s}'. Use 0, 90, 180 or 270.", .{args});
			return;
		};
	}
	if(source.worldEditData.clipboard == null) {
		source.sendMessage("#ff0000Error: No clipboard content to rotate.", .{});
	}
	const current = source.worldEditData.clipboard.?;
	defer current.deinit(main.globalAllocator);
	source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, angle);
}
