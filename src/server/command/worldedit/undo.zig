const std = @import("std");

const main = @import("root");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Undo last change done to world with world editing commands.";
pub const usage = "/undo";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /undo. Expected no arguments.", .{});
		return;
	}
	if(source.worldEditData.undoHistory.pop()) |action| {
		action.blueprint.paste(action.position);
		source.sendMessage("#00ff00Un-done last {s}.", .{action.message});
	} else {
		source.sendMessage("#ccccccNothing to undo.", .{});
	}
}
