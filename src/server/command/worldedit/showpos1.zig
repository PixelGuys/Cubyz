const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Show previously selected 1st position coordinates.";
pub const usage = "/showpos1";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /showpos1. Expected no arguments.", .{});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	const pos = source.commandData.selectionPosition1;
	source.sendMessage("Position 1: ({}, {}, {})", .{pos[0], pos[1], pos[2]});
}
