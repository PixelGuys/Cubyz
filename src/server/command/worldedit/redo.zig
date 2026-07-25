const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Redo last change done to world with world editing commands.";
pub const usage = "/redo";

pub const Args = struct {};

pub fn execute(_: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	if (user.worldEditData.redoHistory.pop()) |action| {
		defer action.deinit();

		const undo = Blueprint.capture(main.globalAllocator, action.selection());
		action.blueprint.paste(action.position, .{.preserveVoid = true});

		switch (undo) {
			.success => |blueprint| {
				user.worldEditData.undoHistory.push(.init(blueprint, action.position, action.message));
			},
			.failure => {
				user.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}
		user.sendMessage("#00ff00Re-done last {s}.", .{action.message});
	} else {
		user.sendMessage("#ccccccNothing to redo.", .{});
	}
}
