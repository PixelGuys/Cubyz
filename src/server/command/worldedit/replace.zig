const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;
const Mask = main.blueprint.Mask;

pub const description = "Replace blocks in the world edit selection.";
pub const usage = "/replace <old mask> <new pattern>";

pub fn execute(args: []const u8, source: *User) void {
	var argsSplit = std.mem.splitScalar(u8, args, ' ');
	const oldMaskString = argsSplit.next() orelse {
		return source.sendMessage("#ff0000Missing required <old> argument.", .{});
	};
	const newPatternString = argsSplit.next() orelse {
		return source.sendMessage("#ff0000Missing required <new> argument.", .{});
	};

	const pos1 = source.worldEditData.selectionPosition1 orelse {
		return source.sendMessage("#ff0000Position 1 isn't set", .{});
	};
	const pos2 = source.worldEditData.selectionPosition2 orelse {
		return source.sendMessage("#ff0000Position 2 isn't set", .{});
	};

	const oldMask = Mask.initFromString(main.stackAllocator, oldMaskString) catch |err| {
		return source.sendMessage("#ff0000Error parsing mask: {s}", .{@errorName(err)});
	};
	defer oldMask.deinit(main.stackAllocator);

	const newPattern = Pattern.initFromString(main.stackAllocator, newPatternString) catch |err| {
		return source.sendMessage("#ff0000Error parsing pattern: {s}", .{@errorName(err)});
	};
	defer newPattern.deinit(main.stackAllocator);

	const posStart: Vec3i = @min(pos1, pos2);
	const posEnd: Vec3i = @max(pos1, pos2);

	const selection = Blueprint.capture(main.globalAllocator, posStart, posEnd);

	switch(selection) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, posStart, "replace"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(oldMask, null, newPattern);
			modifiedBlueprint.paste(posStart, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
