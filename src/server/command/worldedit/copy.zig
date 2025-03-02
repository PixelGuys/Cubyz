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

	const pos1 = source.commandData.selectionPosition1;
	const pos2 = source.commandData.selectionPosition2;

	source.sendMessage("Copying: ({d:.3}, {d:.3}, {d:.3}) ({d:.3}, {d:.3}, {d:.3})", .{pos1[0], pos1[1], pos1[2], pos2[0], pos2[1], pos2[2]});
	if (source.commandData.clipboard != null) {
		source.commandData.clipboard.?.capture(pos1, pos2);
	} else {
		source.commandData.clipboard = Blueprint.init(main.globalAllocator);
		source.commandData.clipboard.?.capture(pos1, pos2);
	}
}
