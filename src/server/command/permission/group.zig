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
	\\/group <list> @<playerIndex>
	\\/group <groupName> <add/remove> <whitelist/blacklist> <permissionPath>
	\\/group <groupName> <permissionPath>
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
	@"/group <group> <action> @<playerIndex>": struct {
		group: GroupArg,
		action: enum { add, remove },
		playerIndex: ?command.PlayerIndex,
	},
	@"/group <list> @<playerIndex>": struct {
		action: enum { list },
		playerIndex: ?command.PlayerIndex,
	},
	@"/group <group> <action> <list> <permissionPath>": struct {
		group: GroupArg,
		action: enum { add, remove },
		list: enum { whitelist, blacklist },
		permissionPath: command.PermissionPath,
	},
	@"/group <group> <permissionPath>": struct {
		group: GroupArg,
		permissionPath: command.PermissionPath,
	},
};

pub fn execute(args: Args, source: Source) void {
	switch (args) {
		.@"/group <create> <groupName>" => |params| {
			const group = Group.createGroup(params.name) catch {
				source.sendMessage("#ff0000Group {s}§#ff0000 already exists.", .{params.name});
				return;
			};
			source.sendMessage("#00ff00Group {f}§#00ff00 created", .{group});
		},
		.@"/group <delete> <group>" => |params| {
			if (params.group.group == main.server.permission.Group.default or params.group.group == main.server.permission.Group.moderator) {
				source.sendMessage("#ff0000The default/moderator group can't be deleted", .{});
				return;
			}
			if (!params.group.group.delete()) {
				source.sendMessage("#ff0000Could not delete group {f}§#ff0000 as it was already deleted", .{params.group.group});
				return;
			}
			source.sendMessage("#00ff00Group deleted", .{});
		},
		.@"/group <group> <action> @<playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			const group = params.group.group;
			switch (params.action) {
				.add => {
					main.entity.components.@"cubyz:permissions".server.addToGroup(target.user.id, group);
					source.sendMessage("#00ff00User {f}§#00ff00 added to group {f}", .{target.user, group});
				},
				.remove => {
					if (params.group.group == main.server.permission.Group.default) {
						source.sendMessage("#ff0000Users can't be removed from the default group", .{});
						return;
					}
					if (!main.entity.components.@"cubyz:permissions".server.removeFromGroup(target.user.id, group)) {
						source.sendMessage("#ff0000Could not leave group {f}§#ff0000 as {f}§#ff0000 was already not a member", .{group, target.user});
						return;
					}
					source.sendMessage("#00ff00User {f}§#00ff00 removed from group {f}§#ff0000", .{target.user, group});
				},
			}
		},
		.@"/group <list> @<playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			const groups = main.entity.components.@"cubyz:permissions".server.getPermissionGroups(target.user.id).?;
			source.sendMessage("#00ff00User {f}§#00ff00 is part of these groups:", .{target.user});

			var it = groups.keyIterator();
			while (it.next()) |group| {
				source.sendMessage("#00ff00{f}", .{group});
			}
		},
		.@"/group <group> <action> <list> <permissionPath>" => |params| {
			const listType: permission.Permissions.ListType = switch (params.list) {
				.whitelist => .white,
				.blacklist => .black,
			};

			if (!source.hasPermission(params.permissionPath.path)) {
				source.sendMessage("#ff0000Without permission to use the permission path {s} yourself, you can't modify the permission to use it for groups", .{params.permissionPath.path});
			}

			const group = params.group.group;
			switch (params.action) {
				.add => {
					group.addPermission(listType, params.permissionPath.path) catch {
						source.sendMessage("#00ff00Group has been deleted while processing the command.", .{});
						return;
					};
					source.sendMessage("#00ff00Permission path {s} added to group {f}§#00ff00's permission {s}list", .{params.permissionPath.path, group, @tagName(listType)});
				},
				.remove => {
					if (!(group.removePermission(listType, params.permissionPath.path) catch {
						source.sendMessage("#00ff00Group has been deleted while processing the command.", .{});
						return;
					})) {
						source.sendMessage("#ff0000Permission path {s} is not present inside group {f}§#ff0000 permission {s}list", .{params.permissionPath.path, group, @tagName(listType)});
						return;
					}
					source.sendMessage("#00ff00Permission path {s} removed from group {f}§#00ff00's permission {s}list", .{params.permissionPath.path, group, @tagName(listType)});
				},
			}
		},
		.@"/group <group> <permissionPath>" => |params| {
			const group = params.group.group;
			if ((group.hasPermission(params.permissionPath.path) catch {
				source.sendMessage("#00ff00Group has been deleted while processing the command.", .{});
				return;
			}) == .yes) {
				source.sendMessage("#00ff00Group {f}§#00ff00 has permission for path: {s}", .{group, params.permissionPath.path});
			} else {
				source.sendMessage("#ff0000Group {f}§#ff0000 has no permission for path: {s}", .{group, params.permissionPath.path});
			}
		},
	}
}

const GroupArg = struct {
	group: Group,

	pub fn parse(_: main.heap.NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *main.ListManaged(u8)) error{ParseError}!GroupArg {
		return .{.group = Group.getByName(arg) catch {
			errorMessage.print("name: '{s}' for <{s}> is not a valid group", .{arg, name});
			return error.ParseError;
		}};
	}
};
