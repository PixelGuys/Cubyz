const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListManaged = main.ListManaged;
const User = main.server.User;
const permission = main.server.permission;
const ListType = permission.Permissions.ListType;
const command = main.server.command;

pub const description = "Performs changes on the permissions of the player or shows the if has permission for a specific permission path";
pub const usage =
	\\/perm <permissionPath>
	\\/perm @<playerIndex> <permissionPath>
	\\/perm <add/remove> <whitelist/blacklist> <permissionPath>
	\\/perm <add/remove> <whitelist/blacklist> @<playerIndex> <permissionPath>
;

pub const Args = union(enum) {
	@"/perm <action> <list> <playerIndex> <permissionPath>": struct {
		action: enum { add, remove },
		list: enum { whitelist, blacklist },
		playerIndex: ?command.PlayerIndex,
		permissionPath: Path,
	},
	@"/perm <playerIndex> <permissionPath>": struct { playerIndex: ?command.PlayerIndex, permissionPath: Path },
};

pub fn execute(args: Args, source: *User) void {
	switch (args) {
		.@"/perm <action> <list> <playerIndex> <permissionPath>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();

			const listType: ListType = switch (params.list) {
				.whitelist => .white,
				.blacklist => .black,
			};

			switch (params.action) {
				.add => main.entity.components.@"cubyz:permissions".server.getPermissions(target.user.id).?.addPermission(listType, params.permissionPath.path),
				.remove => {
					if (!main.entity.components.@"cubyz:permissions".server.getPermissions(target.user.id).?.removePermission(listType, params.permissionPath.path)) {
						source.sendMessage("#ff0000Permission path {s} is not present inside users permission {s}list", .{params.permissionPath.path, @tagName(listType)});
					}
				},
			}
		},
		.@"/perm <playerIndex> <permissionPath>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();

			if (main.entity.components.@"cubyz:permissions".server.hasPermission(target.user.id, params.permissionPath.path)) {
				source.sendMessage("#00ff00Player {s}§#00ff00 has permission for path: {s}", .{target.user.name, params.permissionPath.path});
			} else {
				source.sendMessage("#ff0000Player {s}§#ff0000 has no permission for path: {s}", .{target.user.name, params.permissionPath.path});
			}
		},
	}
}

const Path = struct {
	path: []const u8,

	pub fn parse(_: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!Path {
		if (arg[0] != '/') {
			errorMessage.print("Permission path for <{s}> doesn't begin with a \"/\", got: {s}", .{name, arg});
			return error.ParseError;
		}
		return .{.path = arg};
	}
};
