const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const Command = struct {
	exec: *const fn(args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
	commandNameOverride: ?[]const u8 = null,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).@"struct".decls) |decl| {
		var commandNameString: []const u8 = decl.name;
		const commandObject = @field(commandList, decl.name);

		if(@hasDecl(commandObject, "commandNameOverride")){
			if (commandObject.commandNameOverride) |commandNameOverride| {
				commandNameString = commandNameOverride;
			}
		}

		commands.put(commandNameString, .{
			.name = commandNameString,
			.description = commandObject.description,
			.usage = commandObject.usage,
			.exec = &commandObject.execute,
		}) catch unreachable;

		std.log.info("Registered Command: {s}", .{commandNameString});
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if(commands.get(command)) |cmd| {
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}
