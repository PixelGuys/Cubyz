const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const players = main.server.players;

pub const description = "Adds a status";
pub const usage =
	\\/status <effect> <stacks> <time>
;

const Action = enum { add, block };

pub const Args = union(enum) {
	@"/status <effect> <stacks> <time>": struct { effect: Action, stacks: u32, time: f32 },
};

pub fn execute(args: Args, _: Source) void {
	switch (args) {
		.@"/status <effect> <stacks> <time>" => {
			main.sync.client.executeCommand(.{.addStatusEffect = .{.id = 1, .stacks = 1, .timeLeft = 1}});
		},
	}
}
