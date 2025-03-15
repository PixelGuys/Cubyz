const std = @import("std");

const main = @import("root");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Copy selection to clipboard.";
pub const usage = "/copy";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /copy. Expected no arguments.", .{});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	if(source.commandData.selectionPosition1) |pos1| {
		if(source.commandData.selectionPosition2) |pos2| {
			source.sendMessage("Copying: ({d:.3}, {d:.3}, {d:.3}) ({d:.3}, {d:.3}, {d:.3})", .{pos1[0], pos1[1], pos1[2], pos2[0], pos2[1], pos2[2]});
			if(source.commandData.clipboard != null) {
				source.commandData.clipboard.?.deinit(main.globalAllocator);
			}
			const result = Blueprint.capture(main.globalAllocator, pos1, pos2);
			switch(result) {
				.success => {
					source.commandData.clipboard = result.success;
					source.sendMessage("Copied selection to clipboard.", .{});
				},
				.failure => {
					const e = result.failure;
					source.sendMessage("#ff0000Error while copying block ({d:.3}, {d:.3}, {d:.3}): {s}", .{e.x, e.y, e.z, e.message});
					std.log.warn("Error while copying block ({d:.3}, {d:.3}, {d:.3}): {s}", .{e.x, e.y, e.z, e.message});
				},
			}
		} else {
			source.sendMessage("#ff0000Position 2 isn't set", .{});
		}
	} else {
		source.sendMessage("#ff0000Position 1 isn't set", .{});
	}
}
