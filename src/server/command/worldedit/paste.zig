const std = @import("std");

const main = @import("main");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const copy = @import("copy.zig");

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Paste clipboard content to current player position.";
pub const usage = "/paste";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /paste. Expected no arguments.", .{});
		return;
	}

	if(source.worldEditData.clipboard) |clipboard| {
		const pos: Vec3i = @intFromFloat(source.player.pos);
		source.sendMessage("Pasting: {}", .{pos});

		const undo = Blueprint.capture(main.globalAllocator, pos, .{
			pos[0] + @as(i32, @intCast(clipboard.blocks.width)) - 1,
			pos[1] + @as(i32, @intCast(clipboard.blocks.depth)) - 1,
			pos[2] + @as(i32, @intCast(clipboard.blocks.height)) - 1,
		});
		switch(undo) {
			.success => |blueprint| {
				source.worldEditData.undoHistory.push(.init(blueprint, pos, "paste"));
				source.worldEditData.redoHistory.clear();
			},
			.failure => {
				source.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}

		clipboard.paste(pos);
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to paste.", .{});
	}
}
