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

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var argsSplit = std.mem.splitScalar(u8, args, ' ');
	const oldMaskString = argsSplit.next() orelse {
		return source.sendMessage("#ff0000Missing required <old> argument.", .{});
	};
	const newPatternString = argsSplit.next() orelse {
		return source.sendMessage("#ff0000Missing required <new> argument.", .{});
	};

	const selection = command.getCurrentSelection(source) catch return;

	const oldMask = Mask.initFromString(main.stackAllocator, oldMaskString) catch |err| {
		return source.sendMessage("#ff0000Error parsing mask: {s}", .{@errorName(err)});
	};
	defer oldMask.deinit(main.stackAllocator);

	const newPattern = Pattern.initFromString(main.stackAllocator, newPatternString) catch |err| {
		return source.sendMessage("#ff0000Error parsing pattern: {s}", .{@errorName(err)});
	};
	defer newPattern.deinit(main.stackAllocator);

	const capture = Blueprint.capture(main.globalAllocator, selection);

	switch (capture) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "replace"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(oldMask, null, newPattern);
			modifiedBlueprint.paste(selection.minPos, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
