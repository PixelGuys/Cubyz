const std = @import("std");

const main = @import("main");
const command = main.server.command;
const particles = main.particles;
const User = main.server.User;

pub const description = "Spawns particles.";
pub const usage =
	\\/particles <id> <x> <y> <z>
	\\/particles <id> <x> <y> <z> <collides>
	\\/particles <id> <x> <y> <z> <collides> <count>
	\\/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>
	\\
	\\tip: use "~" to apply current player position coordinate in <x> <y> <z> fields.
	\\zon example (currently no support for spaces in the zon):
	\\.{
	\\  .shape = .sphere,
	\\  .radius = 5,
	\\  .mode = .scatter,
	\\  .speed = .{0.5, 10},
	\\  .lifeTime = .{0.5, 10},
	\\  .randomRotate = true,
	\\}
;

pub const Args = union(enum) {
	@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>": struct {
		id: []const u8,
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
		collides: ?bool,
		count: ?u32,
		spawnDataZon: ?[]const u8,
	},
};

pub fn execute(args: *Args, source: *User) void {
	const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);
	for (users) |user| {
		main.network.protocols.genericUpdate.sendParticles(
			user.conn,
			args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".id,
			command.resolveCoordinates(
				args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".x,
				args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".y,
				args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".z,
				source,
			),
			args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".collides orelse true,
			args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".count orelse 1,
			args.@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>".spawnDataZon orelse "",
		);
	}
}
