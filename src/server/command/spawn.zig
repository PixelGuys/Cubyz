const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Teleport to spawn. (Admins: Get or set spawn points)";
pub const usage =
\\/spawn
\\/spawn <x> <y> <z>
\\/spawn @<playerIndex>
\\/spawn @<playerIndex> <x> <y> <z>
\\/spawn world
\\/spawn world <x> <y> <z>
;

const Args = union(enum) {
	@"/spawn": struct {},
	@"/spawn <playerIndex> <x> <y> <z>": struct { playerIndex: ?command.PlayerIndex, x: command.Coordinate, y: command.Coordinate, z: command.Coordinate },
	@"/spawn <world> <x> <y> <z>": struct { world: enum { world }, x: command.Coordinate, y: command.Coordinate, z: command.Coordinate },
	@"/spawn <world>": struct { world: enum { world } },
	@"/spawn <playerIndex>": struct { playerIndex: ?command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/spawn"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/spawn" => {
		    // --- CUSTOM ASHFRAME (back_pos) ---
			source.player().back_pos = source.player().pos;
			// --- CUSTOM ASHFRAME (back_pos) ---

			// Bypasses getSpawnPos() and pulls the global map coordinates directly
			const global_spawn = @as(main.vec.Vec3d, @floatFromInt(main.server.world.?.spawn));

			// Move player position internally and update client side
			source.player().pos = global_spawn;
			main.network.protocols.genericUpdate.sendTPCoordinates(source.conn, global_spawn);
			source.sendMessage("#00ff00Teleporting to global spawn...", .{});
		},
		.@"/spawn <playerIndex> <x> <y> <z>" => |params| {
			if (!source.hasPermission("/command/spawn/admin")) {
				source.sendMessage("#ff0000You do not have permission to modify player spawn points.", .{});
				return;
			}
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			target.user.spawnPos = command.resolveCoordinates(params.x, params.y, params.z, source);
		},
		.@"/spawn <playerIndex>" => |params| {
			if (!source.hasPermission("/command/spawn/admin")) {
				source.sendMessage("#ff0000You do not have permission to view other players' spawn points.", .{});
				return;
			}
			const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
			defer target.deinit();
			source.sendMessage("#ffff00{}", .{target.user.getSpawnPos()});
		},
		.@"/spawn <world> <x> <y> <z>" => |params| {
			if (!source.hasPermission("/command/spawn/admin")) {
				source.sendMessage("#ff0000You do not have permission to modify the world spawn.", .{});
				return;
			}
			const pos = command.resolveCoordinates(params.x, params.y, params.z, source);
			const world = main.server.world.?;
			world.spawn = @trunc(pos);
		},
		.@"/spawn <world>" => {
			if (!source.hasPermission("/command/spawn/admin")) {
				source.sendMessage("#ff0000You do not have permission to view the absolute world spawn coordinates.", .{});
				return;
			}
			const world = main.server.world.?;
			source.sendMessage("#ffff00World spawn: {}", .{world.spawn});
		},
	}
}
