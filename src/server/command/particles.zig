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

const Args = union(enum) {
	@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>": struct {
		id: []const u8,
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
		collides: ?enum { true, false },
		count: ?u32,
		spawnDataZon: ?[]const u8,
	},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/particles"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = (ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	}).@"/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>";

	const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);
	for (users) |user| {
		main.network.protocols.genericUpdate.sendParticles(
			user.conn,
			result.id,
			command.resolveCoordinates(
				result.x,
				result.y,
				result.z,
				source,
			),
			result.collides == null or result.collides.? == .true,
			result.count orelse 1,
			result.spawnDataZon orelse "",
		);
	}
}
