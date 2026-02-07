const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;

pub const description = "lets you create, delete, join and leave groups";
pub const usage = "/group <create/delete/join/leave> <groupName>";

const operations = enum {
	create,
	delete,
	join,
	leave,
};

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
		return;
	}

	var split = std.mem.splitScalar(u8, args, ' ');
	const opString = split.next() orelse {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
		return;
	};
	const op: operations = std.meta.stringToEnum(operations, opString) orelse {
		source.sendMessage("#ff0000Expected either create, delete, join or leave, found \"{s}\"", .{opString});
		return;
	};
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /group. Usage: " ++ usage, .{});
			return;
		}
		switch (op) {
			.create => {
				permission.createGroup(arg) catch {
					source.sendMessage("#ff0000Group {s}#ff0000 already exists.", .{arg});
				};
			},
			.delete => {
				if (!permission.deleteGroup(arg)) {
					source.sendMessage("#ff0000Group {s}#ff0000 could not be removed as it already doesn't exist.", .{arg});
				}
			},
			.join => {
				source.addToGroup(arg) catch {
					source.sendMessage("#ff0000Group {s}#ff0000 does not exist.", .{arg});
				};
			},
			.leave => {
				if (!source.removeFromGroup(arg)) {
					source.sendMessage("#ff0000Could not leave group {s}#ff0000 as user was already not a member", .{arg});
				}
			},
		}
	} else {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
	}
}
