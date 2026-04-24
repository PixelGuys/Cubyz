const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;

const command = @import("../_command.zig");

pub const description = "Lets you create and delete groups, add and remove players and modify their permission paths";
pub const usage =
	\\/group <create/delete> <groupName>
	\\/group <add/remove> <groupName> @<playerIndex>
	\\/group <whitelist/blacklist> <groupName> <add/remove> <permissionPath>
	\\/group <whitelist/blacklist> <groupName> <permissionPath>
;

const Operation = enum {
	create,
	delete,
	add,
	remove,
	whitelist,
	blacklist,
};

const PathOps = enum {
	add,
	remove,
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
	const op: Operation = std.meta.stringToEnum(Operation, opString) orelse {
		source.sendMessage("#ff0000Expected either create, delete, join, leave, whitelist or blacklist, found \"{s}\"", .{opString});
		return;
	};
	const groupName = split.next() orelse {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
		return;
	};
	switch (op) {
		.create, .delete => handleGroupChanges(op, groupName, &split, source),
		.add, .remove => handleGroupUserChanges(op, groupName, &split, source),
		.whitelist, .blacklist => handleGroupPermissionChanges(op, groupName, &split, source),
	}
}

fn handleGroupChanges(op: Operation, groupName: []const u8, split: *std.mem.SplitIterator(u8, .scalar), source: *User) void {
	if (split.next() != null) {
		source.sendMessage("#ff0000Too many arguments for command /group. Usage: " ++ usage, .{});
		return;
	}
	switch (op) {
		.create => {
			permission.createGroup(groupName) catch {
				source.sendMessage("#ff0000Group {s}#ff0000 already exists.", .{groupName});
				return;
			};
			source.sendMessage("#00ff00Group {s} created", .{groupName});
		},
		.delete => {
			if (!permission.deleteGroup(groupName)) {
				source.sendMessage("#ff0000Group {s}#ff0000 could not be removed as it already doesn't exist.", .{groupName});
				return;
			}
			source.sendMessage("#00ff00Group {s} deleted", .{groupName});
		},
		else => unreachable,
	}
}

fn handleGroupUserChanges(op: Operation, groupName: []const u8, split: *std.mem.SplitIterator(u8, .scalar), source: *User) void {
	const target = command.Target.init(split, source) catch return;
	defer target.deinit();
	if (split.next() != null) {
		source.sendMessage("#ff0000Too many arguments for command /group. Usage: " ++ usage, .{});
		return;
	}
	switch (op) {
		.add => {
			target.user.addToGroup(groupName) catch {
				source.sendMessage("#ff0000Group {s}#ff0000 does not exist.", .{groupName});
				return;
			};
			source.sendMessage("#00ff00User {f} added to group {s}", .{target.user, groupName});
		},
		.remove => {
			if (!target.user.removeFromGroup(groupName)) {
				source.sendMessage("#ff0000Could not leave group {s}#ff0000 as {f} was already not a member", .{groupName, target.user});
				return;
			}
			source.sendMessage("#00ff00User {f} removed from group {s}", .{target.user, groupName});
		},
		else => unreachable,
	}
}

fn handleGroupPermissionChanges(op: Operation, groupName: []const u8, split: *std.mem.SplitIterator(u8, .scalar), source: *User) void {
	const listType: permission.Permissions.ListType = switch (op) {
		.whitelist => .white,
		.blacklist => .black,
		else => unreachable,
	};
	const group = permission.getGroup(groupName) catch {
		source.sendMessage("#ff0000Group with name {s} not found", .{groupName});
		return;
	};

	const arg = split.next() orelse {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
		return;
	};

	const pathOp: ?PathOps = blk: {
		if (split.peek() == null) break :blk null;
		break :blk std.meta.stringToEnum(PathOps, arg) orelse {
			source.sendMessage("#ff0000Expected either add or remove, found \"{s}\"", .{arg});
			return;
		};
	};
	const path = split.next() orelse blk: {
		if (pathOp == null) break :blk arg;
		source.sendMessage("#ff0000Too few arguments for command /perm.", .{});
		return;
	};
	if (path[0] != '/') {
		source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{path});
		return;
	}

	if (split.next() != null) {
		source.sendMessage("#ff0000Too many arguments for command /group. Usage: " ++ usage, .{});
		return;
	}
	if (pathOp) |_op| {
		switch (_op) {
			.add => {
				group.permissions.addPermission(listType, path);
				source.sendMessage("#00ff00Permission path {s} added to group {s}'s permission {s}list", .{path, groupName, @tagName(listType)});
			},
			.remove => {
				if (!group.permissions.removePermission(listType, path)) {
					source.sendMessage("#ff0000Permission path {s} is not present inside group {s} permission {s}list", .{path, groupName, @tagName(listType)});
					return;
				}
				source.sendMessage("#00ff00Permission path {s} removed from group {s}'s permission {s}list", .{path, groupName, @tagName(listType)});
			},
		}
	} else {
		if (group.hasPermission(path) == .yes) {
			source.sendMessage("#00ff00Group {s} has permission for path: {s}", .{groupName, path});
		} else {
			source.sendMessage("#ff0000Group {s} has no permission for path: {s}", .{groupName, path});
		}
	}
}
