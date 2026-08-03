const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Get or set the server time.";
pub const usage =
	\\/time
	\\/time <time>
	\\/time <day/night>
	\\/time <start/stop>"
;

pub const Args = union(enum) {
	@"/time <phase>": struct { phase: enum { day, dusk, night, dawn } },
	@"/time <subcommand>": struct { subcommand: enum { start, stop } },
	@"/time <number>": struct { number: i64 },
	@"/time": struct {},
};

pub fn execute(args: Args, source: Source) void {
	const gameTime: i64 = switch (args) {
		.@"/time" => time: {
			source.sendMessage("#ffff00{}", .{main.server.world.?.gameTime});
			break :time main.server.world.?.gameTime;
		},
		.@"/time <number>" => |params| params.number,
		.@"/time <phase>" => |params| switch (params.phase) {
			.day => main.game.World.DayTime.dayStart,
			.dusk => main.game.World.DayTime.duskStart,
			.night => main.game.World.DayTime.nightStart,
			.dawn => main.game.World.DayTime.dawnStart,
		},
		.@"/time <subcommand>" => |params| {
			switch (params.subcommand) {
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
	};
	main.server.world.?.gameTime = gameTime;
}
