const std = @import("std");

const main = @import("main");
const particles = main.particles;
const User = main.server.User;

pub const description = "Spawns particles.";
pub const usage =
	\\/particles <id> <x> <y> <z>
	\\/particles <id> <x> <y> <z> <collides>
	\\/particles <id> <x> <y> <z> <collides> <count>
	\\
	\\tip: use "~" to apply current player position coordinate in <x> <y> <z> fields.
;

pub fn execute(args: []const u8, source: *User) void {
	parseArguments(source, args) catch |err| {
		switch(err) {
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
	var split = std.mem.splitScalar(u8, args, ' ');
	const particleId = split.next() orelse return error.TooFewArguments;

	const x = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[0], source);
	const y = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[1], source);
	const z = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[2], source);
	const collides = try parseBool(split.next() orelse "true");
	const particleCount = try parseNumber(split.next() orelse "1", source);
	if(split.next() != null) return error.TooManyArguments;

	const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);
	for(users) |user| {
		main.network.Protocols.genericUpdate.sendParticles(user.conn, particleId, .{x, y, z}, collides, particleCount);
	}
}

fn parsePosition(arg: []const u8, playerPos: f64, source: *User) anyerror!f64 {
	const hasTilde = if(arg.len == 0) false else arg[0] == '~';
	const numberSlice = if(hasTilde) arg[1..] else arg;
	const num: f64 = std.fmt.parseFloat(f64, numberSlice) catch ret: {
		if(arg.len > 1 or arg.len == 0) {
			source.sendMessage("#ff0000Expected number or \"~\", found \"{s}\"", .{arg});
			return error.InvalidNumber;
		}
		break :ret 0;
	};

	return if(hasTilde) playerPos + num else num;
}

fn parseBool(arg: []const u8) anyerror!bool {
	if(std.mem.eql(u8, arg, "true")) {
		return true;
	} else if(std.mem.eql(u8, arg, "false")) {
		return false;
	}

	return error.InvalidBoolean;
}

fn parseNumber(arg: []const u8, source: *User) anyerror!u32 {
	return std.fmt.parseUnsigned(u32, arg, 0) catch |err| {
		switch(err) {
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
