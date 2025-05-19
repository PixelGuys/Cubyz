const std = @import("std");

const main = @import("main");
const User = main.server.User;

const Mask = main.blueprint.Mask;

pub const description = "Set edit mask. When used with no mask expression it will clear current mask.";
pub const usage =
	\\/mask <mask>
	\\/mask
;

pub fn execute(args: []const u8, source: *User) void {
	if(args.len == 0) {
		if(source.worldEditData.mask) |mask| mask.deinit(main.globalAllocator);
		source.worldEditData.mask = null;
		source.sendMessage("#00ff00Mask cleared.", .{});
		return;
	}
	const mask = Mask.initFromString(main.globalAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing mask: {}", .{err});
		return;
	};
	source.worldEditData.mask = mask;
	source.sendMessage("#00ff00Mask set.", .{});
}
