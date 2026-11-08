const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Copy selection to clipboard.";
pub const usage = "/copy";

pub const Args = union(enum) {
	@"/copy": struct {},
};

pub fn execute(_: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	const selection = command.getCurrentSelection(user) catch return;
	user.sendMessage("Copying: {f}", .{selection});

	const result = Blueprint.capture(main.globalAllocator, selection);
	switch (result) {
		.success => {
			if (user.worldEditData.clipboard != null) {
				user.worldEditData.clipboard.?.deinit(main.globalAllocator);
			}
			user.worldEditData.clipboard = result.success;

			user.sendMessage("Copied selection to clipboard.", .{});
		},
		.failure => |e| {
			user.sendMessage("#ff0000Error while copying block {}: {s}", .{e.pos, e.message});
			std.log.warn("Error while copying block {}: {s}", .{e.pos, e.message});
		},
	}
}
