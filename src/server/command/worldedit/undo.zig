const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Undo last change done to world with world editing commands.";
pub const usage = "/undo";

const Args = union(enum) {
	@"/undo": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/undo"});

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (source.worldEditData.undoHistory.pop()) |action| {
		defer action.deinit();

		const redo = Blueprint.capture(main.globalAllocator, action.selection());
		action.blueprint.paste(action.position, .{.preserveVoid = true});

		switch (redo) {
			.success => |blueprint| {
				source.worldEditData.redoHistory.push(.init(blueprint, action.position, action.message));
			},
			.failure => {
				source.sendMessage("#ff0000Error: Could not capture redo history.", .{});
			},
		}
		source.sendMessage("#00ff00Un-done last {s}.", .{action.message});
	} else {
		source.sendMessage("#ccccccNothing to undo.", .{});
	}
}
