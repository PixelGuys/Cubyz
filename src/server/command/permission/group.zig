const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permissionLayer = main.server.permissionLayer;

pub const description = "lets you create, delete, join and leave groups";
pub const usage = "/group <create/delete/join/leave> <groupName>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /group. Expected one argument.", .{});
		return;
	}
	var op: enum { create, delete, join, leave } = undefined;

	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (std.ascii.eqlIgnoreCase(arg, "create")) {
			op = .create;
		} else if (std.ascii.eqlIgnoreCase(arg, "delete")) {
			op = .delete;
		} else if (std.ascii.eqlIgnoreCase(arg, "join")) {
			op = .join;
		} else if (std.ascii.eqlIgnoreCase(arg, "leave")) {
			op = .leave;
		} else {
			source.sendMessage("#ff0000Expected either create, delete, join or leave, found \"{s}\"", .{arg});
			return;
		}
	}
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /group", .{});
			return;
		}
		if (std.ascii.startsWithIgnoreCase(arg, "/")) {
			source.sendMessage("#ff0000Groups are not allowed to start with /", .{});
			return;
		}
		switch (op) {
			.create => {
				permissionLayer.createGroup(arg, main.globalAllocator) catch {
					source.sendMessage("#ff0000Group with name {s} already exists.", .{arg});
				};
			},
			.delete => {
				if (!permissionLayer.deleteGroup(arg)) {
					source.sendMessage("#ff0000Group with name {s} did not exists.", .{arg});
				}
			},
			.join => {
				permissionLayer.addUserToGroup(source, arg) catch {
					source.sendMessage("#ff0000Group {s} does not exist.", .{arg});
				};
			},
			.leave => {
				permissionLayer.removeUserFromGroup(source, arg) catch {
					source.sendMessage("#ff0000Group {s} does not exist.", .{arg});
				};
			},
		}
	}
}
