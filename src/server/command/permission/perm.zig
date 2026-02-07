const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;
const ListType = permission.Permissions.ListType;

pub const description = "Performs changes on the permissions of the player or a groupp.";
pub const usage =
	\\/perm <whitelist/blacklist> <permissionPath>
	\\/perm <whitelist/blacklist> <groupName> <permissionPath>
	\\/perm remove <whitelist/blacklist> <permissionPath>
	\\/perm remove <whitelist/blacklist> <groupName> <permissionPath>
;

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /perm. Expected at least two arguments.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (std.ascii.eqlIgnoreCase(arg, "remove")) {
			const helper = Helper.parseHelper(source, &split) catch |err| switch (err) {
				error.InvalidAmount => {
					source.sendMessage("#ff0000Not the right amount of arguments for /perm remove", .{});
					return;
				},
				error.InvalidArg => return,
			};
			if (helper.permissionPath) |permissionPath| {
				if (helper.group) |groupName| {
					const group = permission.getGroup(groupName) catch {
						source.sendMessage("#ff0000Group {s}#ff0000 does not exist.", .{groupName});
						return;
					};
					_ = group.permissions.removePermission(helper.listType, permissionPath);
				} else {
					_ = source.permissions.removePermission(helper.listType, permissionPath);
				}
				return;
			} else {
				source.sendMessage("#ff0000Not the right amount of arguments for /perm remove", .{});
				return;
			}
		}
	}
	split.reset();
	const helper = Helper.parseHelper(source, &split) catch |err| switch (err) {
		error.InvalidAmount => {
			source.sendMessage("#ff0000Not the right amount of arguments for /perm", .{});
			return;
		},
		error.InvalidArg => return,
	};
	if (helper.permissionPath) |permissionPath| {
		if (helper.group) |groupName| {
			const group = permission.getGroup(groupName) catch {
				source.sendMessage("#ff0000Group {s}#ff0000 does not exist.", .{groupName});
				return;
			};
			group.permissions.addPermission(helper.listType, permissionPath);
		} else {
			source.permissions.addPermission(helper.listType, permissionPath);
		}
		return;
	} else {
		source.sendMessage("#ff0000Not the right amount of arguments for /perm", .{});
		return;
	}
}

const Helper = struct {
	listType: ListType,
	group: ?[]const u8,
	permissionPath: ?[]const u8,

	pub fn parseHelper(source: *User, split: *std.mem.SplitIterator(u8, .scalar)) error{ InvalidAmount, InvalidArg }!Helper {
		var listType: ListType = undefined;
		if (split.next()) |arg| {
			if (std.ascii.eqlIgnoreCase(arg, "whitelist")) {
				listType = .white;
			} else if (std.ascii.eqlIgnoreCase(arg, "blacklist")) {
				listType = .black;
			} else {
				source.sendMessage("#ff0000Expected either whitelist or blacklist, found \"{s}\"", .{arg});
				return error.InvalidArg;
			}
		} else return error.InvalidAmount;

		var group: ?[]const u8 = null;
		var permissionPath: ?[]const u8 = null;
		if (split.next()) |arg| {
			if (split.peek() != null) {
				group = arg;
			} else {
				permissionPath = arg;
			}
		}
		if (permissionPath == null) {
			permissionPath = split.next();
		}

		if (permissionPath != null and permissionPath.?[0] != '/') {
			source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{permissionPath.?});
			return error.InvalidArg;
		}

		return .{
			.listType = listType,
			.group = group,
			.permissionPath = permissionPath,
		};
	}
};
