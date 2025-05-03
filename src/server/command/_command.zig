const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const Command = struct {
	exec: *const fn(args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = &@field(commandList, decl.name).execute,
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
	if(commands.get(command)) |cmd| {
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub fn autocomplete(msg: []const u8, allocator: main.heap.NeverFailingAllocator) main.ListUnmanaged([]const u8) {
	if(std.mem.indexOfScalar(u8, msg, ' ') != null) return .{};

	var matches: main.ListUnmanaged([]const u8) = .{};

	if(commands.contains(msg)) {
		const newKey = std.fmt.allocPrint(allocator.allocator, "/{s}", .{msg}) catch unreachable;
		matches.append(allocator, newKey);
	} else {
		var maxLen: usize = 0;

		var iterator = commands.keyIterator();
		while(iterator.next()) |key| {
			if(std.mem.startsWith(u8, key.*, msg)) {
				const newKey = std.fmt.allocPrint(allocator.allocator, "/{s}", .{key.*}) catch unreachable;
				matches.append(allocator, newKey);

				if(key.len > maxLen) {
					const second = matches.items[0];
					const first = matches.items[matches.items.len - 1];
					matches.items[0] = first;
					matches.items[matches.items.len - 1] = second;
					maxLen = key.len;
				}
			}
		}
	}
	return matches;
}
