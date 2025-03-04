const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Show previously selected 2nd position coordinates.";
pub const usage = "/showpos2";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /showpos2. Expected no arguments.", .{});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	const pos = source.commandData.selectionPosition2;
	source.sendMessage("Position 2: ({}, {}, {})", .{pos[0], pos[1], pos[2]});
}
