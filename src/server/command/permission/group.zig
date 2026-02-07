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
		source.sendMessage("#ff0000Too few arguments for command /group. Expected one argument.", .{});
		return;
	}

	var split = std.mem.splitScalar(u8, args, ' ');
	const opString = split.next() orelse {
		source.sendMessage("#ff0000Too few arguments for command /group. Expected one argument.", .{});
		return;
	};
	const op: operations = std.meta.stringToEnum(operations, opString) orelse {
		source.sendMessage("#ff0000Expected either create, delete, join or leave, found \"{s}\"", .{opString});
		return;
	};
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /group", .{});
			return;
		}
		switch (op) {
			.create => {
				permission.createGroup(arg) catch {
					source.sendMessage("#ff0000Group with name {s} already exists.", .{arg});
				};
			},
			.delete => {
				if (!permission.deleteGroup(arg)) {
					source.sendMessage("#ff0000Group with name {s} did not exists.", .{arg});
				}
			},
			.join => {
				source.addToGroup(arg) catch {
					source.sendMessage("#ff0000Group {s} does not exist.", .{arg});
				};
			},
			.leave => {
				if (!source.removeFromGroup(arg)) {
					source.sendMessage("#ff0000User {s} was already not in Group {s}.", .{source.name, arg});
				}
			},
		}
	}
}
