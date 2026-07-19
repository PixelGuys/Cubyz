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

const Args = union(enum) {
	@"/replace <old mask> <new pattern>": struct {
		oldMask: command.MaskExpression,
		newPattern: command.PatternExpression,
	},

	fn deinit(self: @This(), allocator: main.heap.NeverFailingAllocator) void {
		self.@"/replace <old mask> <new pattern>".newPattern.deinit(allocator);
		self.@"/replace <old mask> <new pattern>".oldMask.deinit(allocator);
	}
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/replace"});

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	defer result.deinit(main.stackAllocator);

	const selection = command.getCurrentSelection(source) catch return;
	const capture = Blueprint.capture(main.globalAllocator, selection);

	switch (capture) {
		.success => |blueprint| {
			source.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "replace"));
			source.worldEditData.redoHistory.clear();

			var modifiedBlueprint = blueprint.clone(main.stackAllocator);
			defer modifiedBlueprint.deinit(main.stackAllocator);

			modifiedBlueprint.replace(result.@"/replace <old mask> <new pattern>".oldMask.mask, null, result.@"/replace <old mask> <new pattern>".newPattern.pattern);
			modifiedBlueprint.paste(selection.minPos, .{.preserveVoid = true});
		},
		.failure => |err| {
			source.sendMessage("#ff0000Error: Could not capture selection. (at {}, {s})", .{err.pos, err.message});
		},
	}
}
