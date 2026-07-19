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

pub fn execute(_: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
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
