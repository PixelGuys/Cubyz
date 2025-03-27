const std = @import("std");

const main = @import("root");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Copy selection to clipboard.";
pub const usage = "/copy";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /copy. Expected no arguments.", .{});
		return;
	}
	const pos1 = source.worldEditData.selectionPosition1 orelse {
		return source.sendMessage("#ff0000Position 1 isn't set", .{});
	};
	const pos2 = source.worldEditData.selectionPosition2 orelse {
		return source.sendMessage("#ff0000Position 2 isn't set", .{});
	};

	source.sendMessage("Copying: {} {}", .{pos1, pos2});

	const result = Blueprint.capture(main.globalAllocator, pos1, pos2);
	switch(result) {
		.success => {
			if(source.worldEditData.clipboard != null) {
				source.worldEditData.clipboard.?.deinit(main.globalAllocator);
			}
			source.worldEditData.clipboard = result.success;

			source.sendMessage("Copied selection to clipboard.", .{});
		},
		.failure => |e| {
			source.sendMessage("#ff0000Error while copying block {}: {s}", .{e.pos, e.message});
			std.log.warn("Error while copying block {}: {s}", .{e.pos, e.message});
		},
	}
}
