const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Vec3i = main.vec.Vec3i;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;
const Mask = main.blueprint.Mask;

pub const description = "Replace blocks in the world edit selection.";
pub const usage = "/replace <old mask> <new pattern>";

pub const Args = union(enum) {
	@"/replace <old mask> <new pattern>": struct {
		oldMask: command.MaskExpression,
		newPattern: command.PatternExpression,
	},
};

pub fn execute(args: *Args, source: *User) void {
	const selection = command.getCurrentSelection(source) catch return;
	const capture = Blueprint.capture(main.globalAllocator, selection);

	switch (capture) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "replace"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(args.@"/replace <old mask> <new pattern>".oldMask.mask, null, args.@"/replace <old mask> <new pattern>".newPattern.pattern);
			modifiedBlueprint.paste(selection.minPos, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
