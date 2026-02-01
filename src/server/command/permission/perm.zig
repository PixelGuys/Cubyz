const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permissionLayer = main.server.permissionLayer;

pub const description = "Performs permission interactions.";
pub const usage =
	\\/perm <whitelist/blacklist> <permissionPath>
	\\/perm <whitelist/blacklist> <groupName> <permissionPath>
	\\/perm remove <whitelist/blacklist> <permissionPath>
	\\/perm remove <whitelist/blacklist> <groupName> <permissionPath>
;

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /clear. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (std.ascii.eqlIgnoreCase(arg, "remove")) {
			const helper = Helper.parseHelper(&split) catch {
				source.sendMessage("#ff0000Not the right amount of arguments for /perm remove", .{});
				return;
			};
			if (helper.permissionPath) |permissionPath| {
				if (helper.group) |group| {
					_ = permissionLayer.removeGroupPermission(group, helper.listType, permissionPath) catch {
						source.sendMessage("#ff0000Group {s} does not exist.", .{group});
					};
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
	const helper = Helper.parseHelper(&split) catch {
		source.sendMessage("#ff0000Not the right amount of arguments for /perm", .{});
		return;
	};
	if (helper.permissionPath) |permissionPath| {
		if (helper.group) |group| {
			permissionLayer.addGroupPermission(group, helper.listType, permissionPath) catch {
				source.sendMessage("#ff0000Group {s} does not exist.", .{group});
			};
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
	listType: permissionLayer.Permissions.ListType,
	group: ?[]const u8,
	permissionPath: ?[]const u8,

	pub fn parseHelper(split: *std.mem.SplitIterator(u8, .scalar)) error{Invalid}!Helper {
		var listType: permissionLayer.Permissions.ListType = undefined;
		if (split.next()) |arg| {
			std.debug.print("current arg: {s}\n", .{arg});
			if (std.ascii.eqlIgnoreCase(arg, "whitelist")) {
				listType = .white;
			} else if (std.ascii.eqlIgnoreCase(arg, "blacklist")) {
				listType = .black;
			} else return error.Invalid;
		} else return error.Invalid;

		var group: ?[]const u8 = null;
		var permissionPath: ?[]const u8 = null;
		if (split.next()) |arg| {
			if (!std.ascii.startsWithIgnoreCase(arg, "/")) {
				group = arg;
			} else {
				permissionPath = arg;
			}
		}
		if (permissionPath == null) {
			permissionPath = split.next();
		}

		return .{
			.listType = listType,
			.group = group,
			.permissionPath = permissionPath,
		};
	}
};
