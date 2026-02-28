const std = @import("std");

const main = @import("main");
const particles = main.particles;
const User = main.server.User;

const command = @import("_command.zig");

pub const description = "Spawns particles.";
pub const usage =
	\\/particles <id> <x> <y> <z>
	\\/particles <id> <x> <y> <z> <collides>
	\\/particles <id> <x> <y> <z> <collides> <count>
	\\/particles <id> <x> <y> <z> <collides> <count> <spawnDataZon>
	\\
	\\tip: use "~" to apply current player position coordinate in <x> <y> <z> fields.
	\\zon example:
	\\.{
	\\  .shape = .sphere,
	\\  .radius = 5,
	\\  .mode = .scatter,
	\\  .speed = .{0.5, 10},
	\\  .lifeTime = .{0.5, 10},
	\\  .randomRotate = true,
	\\}
;

pub fn execute(args: []const u8, source: *User) void {
	parseArguments(source, args) catch |err| {
		switch (err) {
			error.TooFewArguments => source.sendMessage("#ff0000Too few arguments for command /particles", .{}),
			error.TooManyArguments => source.sendMessage("#ff0000Too many arguments for command /particles", .{}),
			error.InvalidParticleId => source.sendMessage("#ff0000Invalid particle id", .{}),
			error.InvalidBoolean => source.sendMessage("#ff0000Invalid argument. Expected \"true\" or \"false\"", .{}),
			error.InvalidNumber => return,
			else => source.sendMessage("#ff0000Error: {s}", .{@errorName(err)}),
		}
		return;
	};
}

fn parseArguments(source: *User, args: []const u8) anyerror!void {
	const zonIndex = std.mem.indexOf(u8, args, " .{") orelse args.len;
	const zonStr = args[zonIndex..];
	var split = std.mem.splitScalar(u8, std.mem.trimRight(u8, args[0..zonIndex], " "), ' ');
	const particleId = split.next() orelse return error.TooFewArguments;

	const pos = try command.parseCoordinates(&split, source);

	const collides = try parseBool(split.next() orelse "true");
	const particleCount = try parseNumber(split.next() orelse "1", source);

	if (split.next() != null) return error.TooManyArguments;

	const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);
	for (users) |user| {
		main.network.protocols.genericUpdate.sendParticles(user.conn, particleId, pos, collides, particleCount, zonStr);
	}
}

fn parseBool(arg: []const u8) anyerror!bool {
	if (std.mem.eql(u8, arg, "true")) {
		return true;
	} else if (std.mem.eql(u8, arg, "false")) {
		return false;
	}

	return error.InvalidBoolean;
}

fn parseNumber(arg: []const u8, source: *User) anyerror!u32 {
	return std.fmt.parseUnsigned(u32, arg, 0) catch |err| {
		switch (err) {
			error.Overflow => {
				const maxParticleCount = particles.ParticleSystem.maxCapacity;
				source.sendMessage("#ff0000Too many particles spawned \"{s}\", maximum: \"{d}\"", .{arg, maxParticleCount});
				return maxParticleCount;
			},
			error.InvalidCharacter => {
				source.sendMessage("#ff0000Expected number, found \"{s}\"", .{arg});
				return error.InvalidNumber;
			},
		}
	};
}
