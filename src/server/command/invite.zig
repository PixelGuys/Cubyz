const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const description = "Invite a player";
pub const usage = "/invite <IP>";

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	if(split.next()) |arg| blk: {
		if(arg.len == 0) break :blk;
		if(split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /invite");
		}
		const user = main.server.User.initAndIncreaseRefCount(main.server.connectionManager, arg) catch |err| {
			const msg = std.fmt.allocPrint(main.stackAllocator.allocator, "#ff0000Error while trying to connect: {s}", .{@errorName(err)}) catch unreachable;
			defer main.stackAllocator.free(msg);
			std.log.err("{s}", .{msg[7..]});
			source.sendMessage(msg);
			return;
		};
		user.decreaseRefCount();
		return;
	}
	source.sendMessage("#ff0000Too few arguments for command /invite");
}