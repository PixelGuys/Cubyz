const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Copy selection to clipboard.";
pub const usage = "/copy";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /copy. Expected no arguments.", .{});
		return;
	}
	const selection = command.getCurrentSelection(source) catch return;
	source.sendMessage("Copying: {f}", .{selection});

	const result = Blueprint.capture(main.globalAllocator, selection);
	switch (result) {
		.success => {
			if (source.worldEditData.clipboard != null) {
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
