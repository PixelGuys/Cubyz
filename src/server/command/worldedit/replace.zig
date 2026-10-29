const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const Vec3i = main.vec.Vec3i;

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

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	const selection = command.getCurrentSelection(user) catch return;
	const capture = Blueprint.capture(main.globalAllocator, selection);

	switch (capture) {
		.success => |blueprint| {
			user.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "replace"));
			user.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(args.@"/replace <old mask> <new pattern>".oldMask.mask, null, args.@"/replace <old mask> <new pattern>".newPattern.pattern);
			modifiedBlueprint.paste(selection.minPos, .{.preserveVoid = true});
		},
		.failure => |err| {
			user.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
