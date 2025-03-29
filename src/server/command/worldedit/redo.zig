const std = @import("std");

const main = @import("main");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Redo last change done to world with world editing commands.";
pub const usage = "/redo";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /redo. Expected no arguments.", .{});
		return;
	}
	if(source.worldEditData.redoHistory.pop()) |action| {
		const undo = Blueprint.capture(main.globalAllocator, action.position, .{
			action.position[0] + @as(i32, @intCast(action.blueprint.blocks.width)) - 1,
			action.position[1] + @as(i32, @intCast(action.blueprint.blocks.depth)) - 1,
			action.position[2] + @as(i32, @intCast(action.blueprint.blocks.height)) - 1,
		});
		action.blueprint.paste(action.position);

		switch(undo) {
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
