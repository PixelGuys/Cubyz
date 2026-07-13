const std = @import("std");

const main = @import("main");
const User = main.server.User;
const permission = main.server.permission;
const command = main.server.command;

pub const description = "Lets you create and delete groups, add and remove players and modify their permission paths";
pub const usage =
	\\/group <create/delete> <groupName>
	\\/group <groupName> <add/remove> @<playerIndex>
	\\/group <groupName> <whitelist/blacklist> <add/remove> <permissionPath>
	\\/group <groupName> <whitelist/blacklist> <permissionPath>
;

const Args = union(enum) {
	@"/group <create/delete> <groupName>": struct {
		action: enum { create, delete },
		name: []const u8,
	},
	@"/group <groupName> <add/remove> @<playerIndex>": struct {
		name: []const u8,
		action: enum { add, remove },
		playerIndex: command.PlayerIndex,
	},
	@"/group <groupame> <whitelist/blacklist <add/remove> <permissionPath>": struct {
		name: []const u8,
		list: enum { whitelist, blacklist },
		action: ?enum { add, remove },
		path: command.PermissionPath,
	},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/group"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/group <create/delete> <groupName>" => |params| {
			switch (params.action) {
				.create => {
					permission.createGroup(params.name) catch {
						source.sendMessage("#ff0000Group {s}§#ff0000 already exists.", .{params.name});
						return;
					};
					source.sendMessage("#00ff00Group {s} created", .{params.name});
				},
				.delete => {
					if (!permission.deleteGroup(main.stackAllocator, params.name)) {
						source.sendMessage("#ff0000Group {s}§#ff0000 could not be removed as it already doesn't exist.", .{params.name});
						return;
					}
					source.sendMessage("#00ff00Group {s}§#00ff00 deleted", .{params.name});
				},
			}
		},
		.@"/group <groupName> <add/remove> @<playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			switch (params.action) {
				.add => {
					target.user.addToGroup(params.name) catch {
						source.sendMessage("#ff0000Group {s}§#ff0000 does not exist.", .{params.name});
						return;
					};
					source.sendMessage("#00ff00User {f}§#00ff00 added to group {s}", .{target.user, params.name});
				},
				.remove => {
					if (!target.user.removeFromGroup(params.name)) {
						source.sendMessage("#ff0000Could not leave group {s}§#ff0000 as {f}§#ff0000 was already not a member", .{params.name, target.user});
						return;
					}
					source.sendMessage("#00ff00User {f}§#00ff00 removed from group {s}", .{target.user, params.name});
				},
			}
		},
		.@"/group <groupame> <whitelist/blacklist <add/remove> <permissionPath>" => |params| {
			const listType: permission.Permissions.ListType = switch (params.list) {
				.whitelist => .white,
				.blacklist => .black,
			};
			const group = permission.getGroup(params.name) catch {
				source.sendMessage("#ff0000Group with name {s}§#ff0000 not found", .{params.name});
				return;
			};
			if (params.action) |action| {
				switch (action) {
					.add => {
						group.addPermission(main.stackAllocator, listType, params.path.path);
						source.sendMessage("#00ff00Permission path {s} added to group {s}§#00ff00's permission {s}list", .{params.path.path, params.name, @tagName(listType)});
					},
					.remove => {
						if (!group.removePermission(main.stackAllocator, listType, params.path.path)) {
							source.sendMessage("#ff0000Permission path {s} is not present inside group {s}§#ff0000 permission {s}list", .{params.path.path, params.name, @tagName(listType)});
							return;
						}
						source.sendMessage("#00ff00Permission path {s} removed from group {s}§#00ff00's permission {s}list", .{params.path.path, params.name, @tagName(listType)});
					},
				}
			} else {
				if (group.hasPermission(params.path.path) == .yes) {
					source.sendMessage("#00ff00Group {s}§#00ff00 has permission for path: {s}", .{params.name, params.path.path});
				} else {
					source.sendMessage("#ff0000Group {s}§#ff0000 has no permission for path: {s}", .{params.name, params.path.path});
				}
			}
		},
	}
}
