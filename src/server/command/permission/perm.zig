const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
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

const Args = union(enum) {
	@"/perm <add> <list> <playerIndex> <permissionPath>": struct {
		add: enum { add },
		list: enum { whitelist, blacklist },
		playerIndex: ?command.PlayerIndex,
		permissionPath: Path,
	},
	@"/perm <playerIndex> <permissionPath>": struct { playerIndex: ?command.PlayerIndex, permissionPath: Path },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/time"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (split.next()) |arg| {
		if (std.ascii.eqlIgnoreCase(arg, "remove")) {
			const helper = Helper.init(source, &split) catch return;
			defer helper.deinit();
			if (!helper.target.user.permissions.removePermission(helper.listType, helper.permissionPath)) {
				source.sendMessage("#ff0000Permission path {s} is not present inside users permission {s}list", .{helper.permissionPath, @tagName(helper.listType)});
			}
		} else if (std.ascii.eqlIgnoreCase(arg, "add")) {
			const helper = Helper.init(source, &split) catch return;
			defer helper.deinit();
			helper.target.user.permissions.addPermission(helper.listType, helper.permissionPath);
		} else {
			split.reset();
			const target = command.Target.init(&split, source) catch return;
			defer target.deinit();

			const permissionPath = split.next() orelse {
				source.sendMessage("#ff0000Too few arguments for /perm", .{});
				return;
			};
			if (permissionPath[0] != '/') {
				source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{permissionPath});
				return;
			}
			if (target.user.hasPermission(permissionPath)) {
				source.sendMessage("#00ff00Player {s}§#00ff00 has permission for path: {s}", .{target.user.name, permissionPath});
			} else {
				source.sendMessage("#ff0000Player {s}§#ff0000 has no permission for path: {s}", .{target.user.name, permissionPath});
			}
		}
	}
}

const Path = struct {
	path: []const u8,

	pub fn parse(allocator: NeverFailingAllocator, _: []const u8, arg: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!Path {
		if (arg[0] != '/') {
			errorMessage.print(allocator, "#ff0000Permission paths always begin with a \"/\", got: {s}", .{arg});
			return error.ParseError;
		}
		return .{.path = arg};
	}
};

const Helper = struct {
	listType: ListType,
	permissionPath: []const u8,
	target: command.Target,

	pub fn init(source: *User, split: *std.mem.SplitIterator(u8, .scalar)) error{InvalidArgs}!Helper {
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

		const target = command.Target.init(split, source) catch return error.InvalidArgs;
		errdefer target.deinit();

		const permissionPath = split.next() orelse {
			source.sendMessage("#ff0000Too few arguments for command /perm.", .{});
			return error.InvalidArgs;
		};

		if (permissionPath[0] != '/') {
			source.sendMessage("#ff0000Permission paths always begin with a \"/\", got: {s}", .{arg});
			return error.InvalidArgs;
		}

		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /perm", .{});
			return error.InvalidArgs;
		}

		return .{.listType = listType, .permissionPath = permissionPath, .target = target};
	}

	pub fn deinit(self: Helper) void {
		self.target.deinit();
	}
};
