const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const Vec3i = main.vec.Vec3i;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;

pub const description = "Set all blocks within selection to a block.";
pub const usage = "/set <pattern>";

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	if (args.len == 0) {
		source.sendMessage("#ff0000Missing required <pattern> argument.", .{});
		return;
	}
	const selection = command.getCurrentSelection(source) catch return;

	const pattern = Pattern.initFromString(main.stackAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing pattern: {s}", .{@errorName(err)});
		return;
	};
	defer pattern.deinit(main.stackAllocator);

	const result = Blueprint.capture(main.globalAllocator, selection);

	switch (result) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "set"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(null, source.worldEditData.mask, pattern);
			modifiedBlueprint.paste(selection.minPos, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
