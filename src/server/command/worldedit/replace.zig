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

const Args = union(enum) {
	@"/replace <old mask> <new pattern>": struct { oldMask: []const u8, newPattern: []const u8 },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/replace"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const selection = command.getCurrentSelection(source) catch return;

	const oldMask = Mask.initFromString(main.stackAllocator, result.@"/replace <old mask> <new pattern>".oldMask) catch |err| {
		return source.sendMessage("#ff0000Error parsing mask: {s}", .{@errorName(err)});
	};
	defer oldMask.deinit(main.stackAllocator);

	const newPattern = Pattern.initFromString(main.stackAllocator, result.@"/replace <old mask> <new pattern>".newPattern) catch |err| {
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
