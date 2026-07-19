const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Redo last change done to world with world editing commands.";
pub const usage = "/redo";

pub const Args = struct {};

pub fn execute(_: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	if (source.worldEditData.redoHistory.pop()) |action| {
		defer action.deinit();

		const undo = Blueprint.capture(main.globalAllocator, action.selection());
		action.blueprint.paste(action.position, .{.preserveVoid = true});

		switch (undo) {
			.success => |blueprint| {
				source.worldEditData.undoHistory.push(.init(blueprint, action.position, action.message));
			},
			.failure => {
				source.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}
		source.sendMessage("#00ff00Re-done last {s}.", .{action.message});
	} else {
		source.sendMessage("#ccccccNothing to redo.", .{});
	}
}
