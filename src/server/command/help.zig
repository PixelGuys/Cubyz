const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
const command = main.server.command;
const User = main.server.User;

pub const description = "Shows info about all the commands.";
pub const usage = "/help\n/help <command>";

const Args = union(enum) {
	@"/help <command>": struct { command: Cmd },
	@"/help": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/help"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	var msg = main.List(u8).init(main.stackAllocator);
	defer msg.deinit();
	msg.appendSlice("#ffff00");
	switch (result) {
		.@"/help" => {
			var iterator = command.commands.valueIterator();
			while (iterator.next()) |cmd| {
				msg.append('/');
				msg.appendSlice(cmd.name);
				msg.appendSlice(": ");
				msg.appendSlice(cmd.description);
				msg.append('\n');
			}
			msg.appendSlice("\nUse /help <command> for usage of a specific command.\n");
		},
		.@"/help <command>" => |params| {
			if (params.command == .bobik) {
				source.sendMessage("#ffff00Even Bobik can't help you anymore", .{});
				return;
			}
			const cmd = params.command.cmd;
			msg.append('/');
			msg.appendSlice(cmd.name);
			msg.appendSlice(": ");
			msg.appendSlice(cmd.description);
			msg.append('\n');
			msg.appendSlice(cmd.usage);
			msg.append('\n');
		},
	}
	if (msg.items[msg.items.len - 1] == '\n') _ = msg.pop();
	source.sendMessage("{s}", .{msg.items});
}

const Cmd = union(enum) {
	cmd: command.Command,
	bobik: void,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorList: *ListUnmanaged(u8)) error{ParseError}!Cmd {
		if (std.mem.eql(u8, arg, "Bobik")) {
			return .bobik;
		}
		return .{
			.cmd = command.commands.get(arg) orelse {
				errorList.print(allocator, "Unrecognized command name for <{s}>, got {s}", .{name, arg});
				return error.ParseError;
			},
		};
	}
};
