const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const Command = struct {
	exec: *const fn (args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
	permissionPath: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for (@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = &@field(commandList, decl.name).execute,
			.permissionPath = "/command/" ++ decl.name,
		}) catch unreachable;
		std.log.debug("Registered command: '/{s}'", .{decl.name});
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if (commands.get(command)) |cmd| {
		if (!source.hasPermission(cmd.permissionPath)) {
			source.sendMessage("#ff0000No permission to use Command \"{s}\"", .{command});
			return;
		}
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub fn parseCoordinate(arg: []const u8, playerPos: f64, source: *User) anyerror!f64 {
	const hasTilde = if (arg.len == 0) false else arg[0] == '~';
	const numberSlice = if (hasTilde) arg[1..] else arg;
	const num: f64 = std.fmt.parseFloat(f64, numberSlice) catch ret: {
		if (arg.len > 1 or arg.len == 0) {
			source.sendMessage("#ff0000Expected number or \"~\", found \"{s}\"", .{arg});
			return error.InvalidNumber;
		}
		break :ret 0;
	};

	return if (hasTilde) playerPos + num else num;
}
