const std = @import("std");

const main = @import("main");
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
		const redo = Blueprint.capture(main.globalAllocator, action.position, .{
			action.position[0] + @as(i32, @intCast(action.blueprint.blocks.width)) - 1,
			action.position[1] + @as(i32, @intCast(action.blueprint.blocks.depth)) - 1,
			action.position[2] + @as(i32, @intCast(action.blueprint.blocks.height)) - 1,
		});
		action.blueprint.paste(action.position);

		switch(redo) {
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
