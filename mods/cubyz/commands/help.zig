const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.List;
const command = main.server.command;
const User = main.server.User;

pub const description = "Shows info about all the commands.";
pub const usage = "/help\n/help <command>";

const Args = union(enum) {
	@"/help <bobik>": struct { bobik: enum { Bobik, bobik } },
	@"/help <command>": struct { command: Cmd },
	@"/help": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/help"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	var msg: main.ListManaged(u8) = .init(main.stackAllocator);
	defer msg.deinit();
	msg.appendSlice("#ffff00");
	switch (result) {
		.@"/help" => {
			var iterator = command.registeredCommands.valueIterator();
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
			const cmd = params.command.cmd;
			msg.append('/');
			msg.appendSlice(cmd.name);
			msg.appendSlice(": ");
			msg.appendSlice(cmd.description);
			msg.append('\n');
			msg.appendSlice(cmd.usage);
			msg.append('\n');
		},
		.@"/help <bobik>" => {
			msg.appendSlice("Even Bobik can't help you anymore ");
		},
	}
	if (msg.items[msg.items.len - 1] == '\n') _ = msg.pop();
	source.sendMessage("{s}", .{msg.items});
}

const Cmd = struct {
	cmd: command.Command,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorList: *List(u8)) error{ParseError}!Cmd {
		return .{
			.cmd = command.registeredCommands.get(arg) orelse {
				errorList.print(allocator, "Unrecognized command name for <{s}>, got {s}", .{name, arg});
				return error.ParseError;
			},
		};
	}
};
