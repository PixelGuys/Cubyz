const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Undo last change done to world with world editing commands.";
pub const usage = "/undo";

pub const Args = union(enum) {
	@"/undo": struct {},
};

pub fn execute(_: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	if (user.worldEditData.undoHistory.pop()) |action| {
		defer action.deinit();

		const redo = Blueprint.capture(main.globalAllocator, action.selection());
		action.blueprint.paste(action.position, .{.preserveVoid = true});

		switch (redo) {
			.success => |blueprint| {
				user.worldEditData.redoHistory.push(.init(blueprint, action.position, action.message));
			},
			.failure => {
				user.sendMessage("#ff0000Error: Could not capture redo history.", .{});
			},
		}
		user.sendMessage("#00ff00Un-done last {s}.", .{action.message});
	} else {
		user.sendMessage("#ccccccNothing to undo.", .{});
	}
}
