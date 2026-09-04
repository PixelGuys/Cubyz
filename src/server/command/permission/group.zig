const std = @import("std");

const main = @import("main");
const permission = main.server.permission;
const Group = permission.Group;
const command = main.server.command;
const Source = command.Source;

pub const description = "Lets you create and delete groups, add and remove players and modify their permission paths";
pub const usage =
	\\/group <create/delete> <groupName>
	\\/group <groupName> <add/remove> @<playerIndex>
	\\/group <groupName> <whitelist/blacklist> <add/remove> <permissionPath>
	\\/group <groupName> <whitelist/blacklist> <permissionPath>
;

pub const Args = union(enum) {
	@"/group <create> <groupName>": struct {
		action: enum { create },
		name: []const u8,
	},
	@"/group <delete> <group>": struct {
		action: enum { delete },
		group: GroupArg,
	},
	@"/group <group> <add/remove> @<playerIndex>": struct {
		group: GroupArg,
		action: enum { add, remove },
		playerIndex: command.PlayerIndex,
	},
	@"/group <group> <whitelist/blacklist <add/remove> <permissionPath>": struct {
		group: GroupArg,
		list: enum { whitelist, blacklist },
		action: ?enum { add, remove },
		path: command.PermissionPath,
	},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/group"});

pub fn execute(args: Args, source: Source) void {
	switch (args) {
		.@"/group <create> <groupName>" => |params| {
			const group = Group.createGroup(params.name) catch {
				source.sendMessage("#ff0000Group {s}§#ff0000 already exists.", .{params.name});
				return;
			};
			source.sendMessage("#00ff00Group {s}§#ff0000 with id {d} created", .{params.name, @intFromEnum(group)});
		},
		.@"/group <delete> <group>" => |params| {
			if (!params.group.group.delete()) {
				source.sendMessage("#ff0000Could not delete group {f}§#ff0000 as it already didn't exists / was renamed", .{params.group.group});
				return;
			}
			source.sendMessage("#00ff00Group {f}§#00ff00 deleted", .{params.group.group});
		},
		.@"/group <group> <add/remove> @<playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			const group = params.group.group;
			switch (params.action) {
				.add => {
					main.entity.components.@"cubyz:permissions".server.addToGroup(target.user.id, group);
					source.sendMessage("#00ff00User {f}§#00ff00 added to group {f}", .{target.user, group});
				},
				.remove => {
					if (!main.entity.components.@"cubyz:permissions".server.removeFromGroup(target.user.id, group)) {
						source.sendMessage("#ff0000Could not leave group {f}§#ff0000 as {f}§#ff0000 was already not a member", .{group, target.user});
						return;
					}
					source.sendMessage("#00ff00User {f}§#00ff00 removed from group {f}§#ff0000", .{target.user, group});
				},
			}
		},
		.@"/group <group> <whitelist/blacklist <add/remove> <permissionPath>" => |params| {
			const listType: permission.Permissions.ListType = switch (params.list) {
				.whitelist => .white,
				.blacklist => .black,
			};
			const group = params.group.group;
			if (params.action) |action| {
				switch (action) {
					.add => {
						group.addPermission(main.stackAllocator, listType, params.path.path);
						source.sendMessage("#00ff00Permission path {s} added to group {f}§#00ff00's permission {s}list", .{params.path.path, group, @tagName(listType)});
					},
					.remove => {
						if (!group.removePermission(main.stackAllocator, listType, params.path.path)) {
							source.sendMessage("#ff0000Permission path {s} is not present inside group {f}§#ff0000 permission {s}list", .{params.path.path, group, @tagName(listType)});
							return;
						}
						source.sendMessage("#00ff00Permission path {s} removed from group {f}§#00ff00's permission {s}list", .{params.path.path, group, @tagName(listType)});
					},
				}
			} else {
				if (group.hasPermission(params.path.path) == .yes) {
					source.sendMessage("#00ff00Group {f}§#00ff00 has permission for path: {s}", .{group, params.path.path});
				} else {
					source.sendMessage("#ff0000Group {f}§#ff0000 has no permission for path: {s}", .{group, params.path.path});
				}
			}
		},
	}
}

const GroupArg = struct {
	group: Group,

	const nameArg: []const u8 = "name:";
	const idArg: []const u8 = "id:";

	pub fn parse(_: main.heap.NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *main.ListManaged(u8)) error{ParseError}!GroupArg {
		if (std.mem.startsWith(u8, arg, idArg)) {
			if (arg.len == idArg.len) {
				errorMessage.print("No id specified after id: for <{s}>", .{name});
				return error.ParseError;
			}
			return parseId(name, arg[idArg.len..], errorMessage);
		}

		if (std.mem.startsWith(u8, arg, nameArg)) {
			if (arg.len == nameArg.len) {
				errorMessage.print("No name specified after name: for <{s}>", .{name});
				return error.ParseError;
			}
			return parseName(name, arg[nameArg.len..], errorMessage);
		}

		if (parseName(name, arg, errorMessage)) |group| {
			return group;
		} else |_| {
			return parseId(name, arg, errorMessage);
		}
	}

	fn parseId(name: []const u8, arg: []const u8, errorMessage: *main.ListManaged(u8)) error{ParseError}!GroupArg {
		const id = std.fmt.parseInt(u32, arg, 10) catch {
			errorMessage.print("id: '{s}' for <{s}> not a valid number", .{arg[idArg.len..], name});
			return error.ParseError;
		};
		return .{.group = Group.getById(id) catch {
			errorMessage.print("id: '{s}' for <{s}> is not a valid group", .{arg[idArg.len..], name});
			return error.ParseError;
		}};
	}

	fn parseName(name: []const u8, arg: []const u8, errorMessage: *main.ListManaged(u8)) error{ParseError}!GroupArg {
		return .{.group = Group.getByName(arg) catch {
			errorMessage.print("name: '{s}' for <{s}> is not a valid group", .{arg[idArg.len..], name});
			return error.ParseError;
		}};
	}
};
