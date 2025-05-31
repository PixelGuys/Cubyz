const std = @import("std");

const main = @import("main");
const particles = main.particles;
const User = main.server.User;

pub const description = "Spawns particles";
pub const usage =
	\\/particle <id> <x> <y> <z>
	\\/particle <id> <x> <y> <z> <collides>
	\\/particle <id> <x> <y> <z> <collides> <count>
;

pub fn execute(args: []const u8, source: *User) void {
	var particleID: ?[]const u8 = null;
	var x: ?f64 = null;
	var y: ?f64 = null;
	var z: ?f64 = null;
	var collides: ?bool = null;
	var particleCount: ?u32 = null;

	var split = std.mem.splitScalar(u8, args, ' ');
	while(split.next()) |arg| {
		if(particleID == null) {
			if(std.mem.containsAtLeast(u8, arg, 1, ":")) {
				if(particles.ParticleManager.getTypeById(arg)) |_| {
					particleID = arg;
				} else {
					source.sendMessage("#ff0000Invalid particle id", .{});
					return;
				}
			}
		} else if(x == null or y == null or z == null) {
			const hasTilde = if(arg.len == 0) false else arg[0] == '~';
			const numberSlice = if(hasTilde) arg[1..] else arg;
			const num: f64 = std.fmt.parseFloat(f64, numberSlice) catch ret: {
				if(arg.len > 1 or arg.len == 0) {
					source.sendMessage("#ff0000Expected number, found \"{s}\"", .{arg});
					return;
				}
				break :ret 0;
			};
			const playerPos = main.game.Player.getEyePosBlocking();
			if(x == null) {
				x = if(hasTilde) playerPos[0] + num else num;
			} else if(y == null) {
				y = if(hasTilde) playerPos[1] + num else num;
			} else if(z == null) {
				z = if(hasTilde) playerPos[2] + num else num;
			}
		} else if(collides == null) {
			if(std.mem.eql(u8, arg, "true")) {
				collides = true;
			} else if(std.mem.eql(u8, arg, "false")) {
				collides = false;
			} else {
				source.sendMessage("#ff0000Invalid argument. Expected \"true\" or \"false\"", .{});
				return;
			}
		} else if(particleCount == null) {
			particleCount = std.fmt.parseUnsigned(u32, arg, 0) catch |err| ret: {
				switch(err) {
					error.Overflow => {
						break :ret std.math.maxInt(u32);
					},
					error.InvalidCharacter => {
						source.sendMessage("#ff0000Expected number, found \"{s}\"", .{arg});
						return;
					},
				}
			};
		} else {
			source.sendMessage("#ff0000Too many arguments for command /particle", .{});
			return;
		}
	}

	if(particleID == null or x == null or y == null or z == null) {
		source.sendMessage("#ff0000Too few arguments for command /particle", .{});
		return;
	}
	x = std.math.clamp(x.?, -1e9, 1e9); // TODO: Remove after #310 is implemented
	y = std.math.clamp(y.?, -1e9, 1e9);
	z = std.math.clamp(z.?, -1e9, 1e9);
	if(collides == null) {
		collides = false;
	}
	if(particleCount == null) {
		particleCount = 1;
	}

	const emitter: particles.Emitter = .init(particleID.?, collides.?);
	emitter.spawnParticles(particleCount.?, particles.Emitter.SpawnPoint, .{
		.mode = .spread,
		.position = main.vec.Vec3d{x.?, y.?, z.?},
	});
}
