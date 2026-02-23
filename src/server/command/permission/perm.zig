const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;
const ListType = permission.Permissions.ListType;

pub const description = "Performs changes on the permissions of the player or shows the if has permission for a specific permission path";
pub const usage =
	\\/perm add <whitelist/blacklist> <permissionPath>
	\\/perm remove <whitelist/blacklist> <permissionPath>
	\\/perm <permissionPath>
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
			if (!source.permissions.removePermission(helper.listType, helper.permissionPath)) {
				source.sendMessage("#ff0000Permission path {s} is not present inside users permission {s}list", .{helper.permissionPath, @tagName(helper.listType)});
			}
		} else if (std.ascii.eqlIgnoreCase(arg, "add")) {
			const helper = Helper.parseHelper(source, &split) catch return;
			source.permissions.addPermission(helper.listType, helper.permissionPath);
		} else if (arg[0] == '/') {
			if (split.next() != null) {
				source.sendMessage("#ff0000Not the right amount of arguments for /perm", .{});
				return;
			}
			if (source.hasPermission(arg)) {
				source.sendMessage("#00ff00User has permission for path: {s}", .{arg});
			} else {
				source.sendMessage("#ff0000User has no permission for path: {s}", .{arg});
			}
		} else {
			source.sendMessage("#ff0000Expected either add, remove or a valid permission path, found \"{s}\"", .{arg});
		}
	}
}

const Helper = struct {
	listType: ListType,
	permissionPath: []const u8,

	pub fn parseHelper(source: *User, split: *std.mem.SplitIterator(u8, .scalar)) error{InvalidArgs}!Helper {
		var listType: ListType = undefined;
		const arg = split.next() orelse {
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

		var permissionPath = split.next() orelse {
			source.sendMessage("#ff0000Too few arguments for command /perm.", .{});
			return error.InvalidArgs;
		};

		if (permissionPath[0] != '/') {
			source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{permissionPath});
			return error.InvalidArgs;
		}

		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /perm", .{});
			return error.InvalidArgs;
		}

		return .{.listType = listType, .permissionPath = permissionPath};
	}
};
