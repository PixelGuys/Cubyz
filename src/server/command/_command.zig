const std = @import("std");

const main = @import("root");
const User = main.server.User;

pub const Command = struct {
	exec: *const fn(args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = std.StringHashMap(Command).init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = &@field(commandList, decl.name).execute,
		}) catch unreachable;
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if(commands.get(command)) |cmd| {
		const result = std.fmt.allocPrint(main.stackAllocator.allocator, "#00ff00Executing Command /{s}", .{msg}) catch unreachable;
		defer main.stackAllocator.free(result);
		source.sendMessage(result);
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
	} else {
		const result = std.fmt.allocPrint(main.stackAllocator.allocator, "#ff0000Unrecognized Command \"{s}\"", .{command}) catch unreachable;
		defer main.stackAllocator.free(result);
		source.sendMessage(result);
	}
}