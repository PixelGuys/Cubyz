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
	@"/status <effect> <stacks> <time>": struct { id: u32, stacks: u32, time: f32 },
};

pub fn execute(args: Args, _: Source) void {
	switch (args) {
		.@"/status <effect> <stacks> <time>" => |params| {
			main.sync.client.executeCommand(.{.addStatusEffect = .{.id = params.id, .stacks = params.stacks, .timeLeft = params.time}});
		},
	}
}
