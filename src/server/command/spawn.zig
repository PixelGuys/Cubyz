const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Get or set a player's / the world spawn point";
pub const usage =
	\\/spawn
	\\/spawn <x> <y> <z>
	\\/spawn @<playerIndex>
	\\/spawn @<playerIndex> <x> <y> <z>
	\\/spawn world
	\\/spawn world <x> <y> <z>
;

const Args = union(enum) {
	@"/spawn <playerIndex> <x> <y> <z>": struct { playerIndex: ?command.PlayerIndex, x: command.Coordinate, y: command.Coordinate, z: command.Coordinate },
	@"/spawn <world> <x> <y> <z>": struct { world: enum { world }, x: command.Coordinate, y: command.Coordinate, z: command.Coordinate },
	@"/spawn <world>": struct { world: enum { world } },
	@"/spawn <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/spawn"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/spawn <playerIndex> <x> <y> <z>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			target.user.spawnPos = command.resolveCoordinates(params.x, params.y, params.z, source);
		},
		.@"/spawn <playerIndex>" => |params| {
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			source.sendMessage("#ffff00{}", .{target.user.getSpawnPos()});
		},
		.@"/spawn <world> <x> <y> <z>" => |params| {
			const pos = command.resolveCoordinates(params.x, params.y, params.z, source);
			const world = main.server.world.?;
			world.spawn = @trunc(pos);
		},
		.@"/spawn <world>" => {
			const world = main.server.world.?;
			source.sendMessage("#ffff00World spawn: {}", .{world.spawn});
		},
	}
}
