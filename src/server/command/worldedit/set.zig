const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;

const command = @import("../_command.zig");

pub const description = "Set all blocks within selection to a block.";
pub const usage = "/set <pattern>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Missing required <pattern> argument.", .{});
		return;
	}
	const pos1, const pos2 = command.getSelectionBounds(source) catch return;
	const pattern = Pattern.initFromString(main.stackAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing pattern: {s}", .{@errorName(err)});
		return;
	};
	defer pattern.deinit(main.stackAllocator);

	const selection = Blueprint.capture(main.globalAllocator, pos1, pos2);

	switch (selection) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, pos1, "set"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(null, source.worldEditData.mask, pattern);
			modifiedBlueprint.paste(pos1, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
