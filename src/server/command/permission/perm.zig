const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;
const ListType = permission.Permissions.ListType;
const command = main.server.command;

pub const description = "Performs changes on the permissions of the player or shows the if has permission for a specific permission path";
pub const usage =
	\\/perm add <whitelist/blacklist> <permissionPath>
	\\/perm remove <whitelist/blacklist> <permissionPath>
	\\/perm <permissionPath>
	\\/perm add <whitelist/blacklist> <playerId> <permissionPath>
	\\/perm remove <whitelist/blacklist> <playerId> <permissionPath>
	\\/perm <playerId> <permissionPath>
;

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /perm. Expected at least one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (std.ascii.eqlIgnoreCase(arg, "remove")) {
			const helper = Helper.parseHelper(source, &split) catch return;
			if (!helper.permissions.removePermission(helper.listType, helper.permissionPath)) {
				source.sendMessage("#ff0000Permission path {s} is not present inside users permission {s}list", .{helper.permissionPath, @tagName(helper.listType)});
			}
		} else if (std.ascii.eqlIgnoreCase(arg, "add")) {
			const helper = Helper.parseHelper(source, &split) catch return;
			helper.permissions.addPermission(helper.listType, helper.permissionPath);
		} else {
			var _arg = arg;
			const user: *User = blk: {
				if (split.next()) |next| {
					const user = command.parsePlayerId(arg, source) catch return;
					_arg = next;
					break :blk user;
				}
				break :blk source;
			};
			if (split.next() != null) {
				source.sendMessage("#ff0000Not the right amount of arguments for /perm", .{});
				return;
			}
			if (_arg[0] != '/') {
				source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{_arg});
				return;
			}
			if (user.hasPermission(_arg)) {
				source.sendMessage("#00ff00Player {s}#ff0000 has permission for path: {s}", .{user.name, _arg});
			} else {
				source.sendMessage("#ff0000Player {s}#ff0000 has no permission for path: {s}", .{user.name, _arg});
			}
		}
	}
}

const Helper = struct {
	listType: ListType,
	permissionPath: []const u8,
	permissions: *permission.Permissions,

	pub fn parseHelper(source: *User, split: *std.mem.SplitIterator(u8, .scalar)) error{InvalidArgs}!Helper {
		var listType: ListType = undefined;
		var arg = split.next() orelse {
			source.sendMessage("#ff0000Too few arguments for command /perm", .{});
			return error.InvalidArgs;
		};
		if (std.ascii.eqlIgnoreCase(arg, "whitelist")) {
			listType = .white;
		} else if (std.ascii.eqlIgnoreCase(arg, "blacklist")) {
			listType = .black;
		} else {
			source.sendMessage("#ff0000Expected either whitelist or blacklist, found \"{s}\"", .{arg});
			return error.InvalidArgs;
		}

		arg = split.next() orelse {
			source.sendMessage("#ff0000Too few arguments for command /perm", .{});
			return error.InvalidArgs;
		};

		const permissions: *permission.Permissions = blk: {
			if (split.next()) |next| {
				const user = command.parsePlayerId(arg, source) catch return error.InvalidArgs;
				arg = next;
				break :blk &user.permissions;
			}
			break :blk &source.permissions;
		};

		if (arg[0] != '/') {
			source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{arg});
			return error.InvalidArgs;
		}

		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /perm", .{});
			return error.InvalidArgs;
		}

		return .{.listType = listType, .permissionPath = arg, .permissions = permissions};
	}
};
