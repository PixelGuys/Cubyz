const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;

pub const description = "lets you create, delete, join, leave groups and modify there permission paths";
pub const usage =
	\\/group <create/delete/join/leave> <groupName>
	\\/group <whitelist/blacklist> <groupName> <add/remove> <permissionPath>
	\\/group <whitelist/blacklist> <groupName> <permissionPath>
;

const Operations = enum {
	create,
	delete,
	join,
	leave,
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
	const op: Operations = std.meta.stringToEnum(Operations, opString) orelse {
		source.sendMessage("#ff0000Expected either create, delete, join, leave, whitelist or blacklist, found \"{s}\"", .{opString});
		return;
	};
	const groupName = split.next() orelse {
		source.sendMessage("#ff0000Too few arguments for command /group. Usage: " ++ usage, .{});
		return;
	};
	switch (op) {
		.create, .delete, .join, .leave => handleGroupChanges(op, groupName, &split, source),
		.whitelist, .blacklist => handleGroupPermissionChanges(op, groupName, &split, source),
	}
}

fn handleGroupChanges(op: Operations, groupName: []const u8, split: *std.mem.SplitIterator(u8, .scalar), source: *User) void {
	if (split.next() != null) {
		source.sendMessage("#ff0000Too many arguments for command /group. Usage: " ++ usage, .{});
		return;
	}
	switch (op) {
		.create => {
			permission.createGroup(groupName) catch {
				source.sendMessage("#ff0000Group {s}#ff0000 already exists.", .{groupName});
			};
		},
		.delete => {
			if (!permission.deleteGroup(groupName)) {
				source.sendMessage("#ff0000Group {s}#ff0000 could not be removed as it already doesn't exist.", .{groupName});
			}
		},
		.join => {
			source.addToGroup(groupName) catch {
				source.sendMessage("#ff0000Group {s}#ff0000 does not exist.", .{groupName});
			};
		},
		.leave => {
			if (!source.removeFromGroup(groupName)) {
				source.sendMessage("#ff0000Could not leave group {s}#ff0000 as user was already not a member", .{groupName});
			}
		},
		.whitelist, .blacklist => unreachable,
	}
}

fn handleGroupPermissionChanges(op: Operations, groupName: []const u8, split: *std.mem.SplitIterator(u8, .scalar), source: *User) void {
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
			.add => group.permissions.addPermission(listType, path),
			.remove => {
				if (!group.permissions.removePermission(listType, path)) {
					source.sendMessage("#ff0000Permission path {s} is not present inside group {s} permission {s}list", .{path, groupName, @tagName(listType)});
				}
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
