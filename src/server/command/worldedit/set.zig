const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Vec3i = main.vec.Vec3i;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;

pub const description = "Set all blocks within selection to a block.";
pub const usage = "/set <pattern>";

const Args = union(enum) {
	@"/set": struct { selection: []const u8 },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/set"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const argsResult = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	const selection = command.getCurrentSelection(source) catch return;

	const pattern = Pattern.initFromString(main.stackAllocator, argsResult.@"/set".selection) catch |err| {
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
