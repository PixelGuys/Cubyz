const std = @import("std");

const main = @import("main");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Redo last change done to world with world editing commands.";
pub const usage = "/redo";

const Args = struct {};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/redo"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	_ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	if (source.worldEditData.redoHistory.pop()) |action| {
		defer action.deinit();

		const undo = Blueprint.capture(main.globalAllocator, action.selection());
		action.blueprint.paste(action.position, .{.preserveVoid = true});

		switch (undo) {
			.success => |blueprint| {
				source.worldEditData.undoHistory.push(.init(blueprint, action.position, action.message));
			},
			.failure => {
				source.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}
		source.sendMessage("#00ff00Re-done last {s}.", .{action.message});
	} else {
		source.sendMessage("#ccccccNothing to redo.", .{});
	}
}
