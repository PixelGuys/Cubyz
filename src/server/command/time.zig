const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set the server time.";
pub const usage = "/time\n/time <day/night>\n/time <time>\n/time <start/stop>";

const Args = union(enum) {
	@"/time <day/night>": struct {phase: enum {day, night}},
	@"/time <start/stop>": struct {command: enum {start, stop}},
	@"/time <number>": struct {number: i64},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/time"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	const gameTime: i64 = switch(result) {
		.@"/time <day/night>" => |params| switch(params.phase) {
			.day => 0,
			.night => main.server.ServerWorld.dayCycle/2,
		},
		.@"/time <start/stop>" => |params| {
			switch(params.command) {
				.start => {
					main.server.world.?.doGameTimeCycle = true;
					source.sendMessage("#ffff00Time started.", .{});
					return;
				},
				.stop => {
					main.server.world.?.doGameTimeCycle = false;
					source.sendMessage("#ffff00Time stopped.", .{});
					return;
				},
			}
		},
		.@"/time <number>" => |params| params.number,
	};

	main.server.world.?.gameTime = gameTime;
	source.sendMessage("#ffff00{}", .{main.server.world.?.gameTime});
}
