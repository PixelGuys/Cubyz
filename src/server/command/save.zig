const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Force saves the world";
pub const usage = "/save";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /save. Expected no arguments.");
		return;
	}
	if (main.server.world) |world| {
        world.forceSave() catch |err| {
            std.log.err("Failed to save the world: {s}", .{@errorName(err)});
        };
    }
}