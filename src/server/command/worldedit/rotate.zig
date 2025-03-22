const std = @import("std");

const main = @import("root");
const User = main.server.User;
const Degrees = main.rotation.Degrees;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage =
	\\/rotate
	\\/rotate <0/90/180/270>
;

pub fn execute(args: []const u8, source: *User) void {
	var angle: Degrees = .@"90";
	if(args.len != 0) {
		angle = std.meta.stringToEnum(Degrees, args) orelse {
			source.sendMessage("#ff0000Error: Invalid angle '{s}'. Use 0, 90, 180 or 270.", .{args});
			return;
		};
	}
	if(source.worldEditData.clipboard == null) {
		source.sendMessage("#ff0000Error: No clipboard content to rotate.", .{});
		return;
	}
	const current = source.worldEditData.clipboard.?;
	defer current.deinit(main.globalAllocator);
	source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, angle);
}
