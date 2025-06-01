const std = @import("std");

const main = @import("main");
const particles = main.particles;
const User = main.server.User;

pub const description = "Spawns particles.";
pub const usage =
	\\/particle <id> <x> <y> <z>
	\\/particle <id> <x> <y> <z> <collides>
	\\/particle <id> <x> <y> <z> <collides> <count>
;

pub fn execute(args: []const u8, source: *User) void {
	const particleID, const x, const y, const z, const collides, const particleCount = parseArguments(source, args) catch |err| {
		switch(err) {
			error.TooFewArguments => source.sendMessage("#ff0000Too few arguments for command /particle", .{}),
			error.TooManyArguments => source.sendMessage("#ff0000Too many arguments for command /particle", .{}),
			error.InvalidParticleID => source.sendMessage("#ff0000Invalid particle id", .{}),
			error.InvalidBoolean => source.sendMessage("#ff0000Invalid argument. Expected \"true\" or \"false\"", .{}),
			error.InvalidNumber => source.sendMessage("#ff0000Invalid number", .{}),
		}
		return;
	};

	const emitter: particles.Emitter = .init(particleID, collides);
	emitter.spawnParticles(particleCount, particles.Emitter.SpawnPoint, .{
		.mode = .spread,
		.position = main.vec.Vec3d{x, y, z},
	});
}

pub const CommandError = error{
	TooManyArguments,
	TooFewArguments,
	InvalidBoolean,
	InvalidNumber,
	InvalidParticleID,
};

fn parseArguments(source: *User, args: []const u8) CommandError!struct {[]const u8, f64, f64, f64, bool, u32} {
	var split = std.mem.splitScalar(u8, args, ' ');
	const particleID = split.next() orelse return error.TooFewArguments;
	_ = particles.ParticleManager.getTypeById(particleID) orelse return error.InvalidParticleID;

	const x = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[0]);
	const y = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[1]);
	const z = try parsePosition(split.next() orelse return error.TooFewArguments, source.player.pos[2]);
	const collides = try parseBool(split.next() orelse "false");
	const particleCount = try parseNumber(split.next() orelse "1");
	if(split.next() != null) return error.TooManyArguments;

	return .{particleID, x, y, z, collides, particleCount};
}

fn parsePosition(arg: []const u8, playerPos: f64) CommandError!f64 {
	const hasTilde = if(arg.len == 0) false else arg[0] == '~';
	const numberSlice = if(hasTilde) arg[1..] else arg;
	const num: f64 = std.fmt.parseFloat(f64, numberSlice) catch ret: {
		if(arg.len > 1 or arg.len == 0) return error.InvalidNumber;
		break :ret 0;
	};

	return if(hasTilde) playerPos + num else num;
}

fn parseBool(arg: []const u8) CommandError!bool {
	if(std.mem.eql(u8, arg, "true")) {
		return true;
	} else if(std.mem.eql(u8, arg, "false")) {
		return false;
	}

	return error.InvalidBoolean;
}

fn parseNumber(arg: []const u8) CommandError!u32 {
	return std.fmt.parseUnsigned(u32, arg, 0) catch |err| {
		switch(err) {
			error.Overflow => return std.math.maxInt(u32),
			error.InvalidCharacter => return error.InvalidNumber,
		}
	};
}
