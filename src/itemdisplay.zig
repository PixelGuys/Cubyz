const std = @import("std");

const game = @import("game.zig");
const Player = game.Player;
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub var showItem: bool = true;
pub var itemDisplayProjectionMatrix: Mat4f = Mat4f.identity();

// Going to handle item animations and other things like - bobbing, interpolation
pub const PlayerItemDisplayManager = struct {
	pub var cameraFollow: Vec3f = .{0, 0, 0};
	var lastTime: i16 = 0;
	var timeDifference: utils.TimeDifference = .{};

	pub fn update() void {
		var time = @as(i16, @truncate(std.time.milliTimestamp()));
		time -%= timeDifference.difference.load(.monotonic);
		const deltaTime = @as(f32, @floatFromInt(time -% lastTime))/1000;

		const blend: f32 = deltaTime * 21;
		cameraFollow = std.math.lerp(cameraFollow, game.camera.rotation, @as(Vec3f, @splat(blend)));
		lastTime = time;
	}
};
