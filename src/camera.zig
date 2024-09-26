const std = @import("std");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;
const game = @import("game.zig");
const settings = @import("settings.zig");

// MARK: camera
pub var position: Vec3d = Vec3d{0, 0, 0};
pub var rotation: Vec3f = Vec3f{0, 0, 0};
pub var direction: Vec3f = Vec3f{0, 0, 0};
pub var viewMatrix: Mat4f = Mat4f.identity();
pub fn moveRotation(mouseX: f32, mouseY: f32) void {
	// Mouse movement along the y-axis rotates the image along the x-axis.
	rotation[0] += mouseY;
	if (rotation[0] > std.math.pi / 2.0) {
		rotation[0] = std.math.pi / 2.0;
	} else if (rotation[0] < -std.math.pi / 2.0) {
		rotation[0] = -std.math.pi / 2.0;
	}
	// Mouse movement along the x-axis rotates the image along the z-axis.
	rotation[2] += mouseX;
}

pub fn updateViewMatrix() void {
	direction = vec.rotateZ(vec.rotateY(vec.rotateX(Vec3f{0, 1, 0}, -rotation[0]), -rotation[1]), -rotation[2]);
	viewMatrix = Mat4f.identity().mul(Mat4f.rotationX(rotation[0])).mul(Mat4f.rotationY(rotation[1])).mul(Mat4f.rotationZ(rotation[2]));
}

pub const ViewBobbing = struct { // MARK: ViewBobber
	pub var enabled: bool = true;
	var time: f64 = 0;
	var velocity: f64 = 0;
	var magnitude: f64 = 0;

	pub fn update(deltaTime: f64) void {
		game.Player.mutex.lock();
		defer game.Player.mutex.unlock();
		var targetVelocity: f64 = 0;
		const horizontalMovementSpeed = vec.length(vec.xy(game.Player.super.vel));
		if (horizontalMovementSpeed > 0.01 and game.Player.onGround) {
			targetVelocity = @sqrt(horizontalMovementSpeed / 4);
		}
		// Smooth lerping of bobVel with framerate independent damping
		const fac: f64 = 1 - std.math.exp(-15 * deltaTime);
		velocity = velocity * (1 - fac) + targetVelocity * fac;
		if (game.Player.onGround) { // No view bobbing in the air
			time += velocity * 8 * deltaTime;
		}
		// Maximum magnitude when sprinting (2x walking speed). Magnitude is scaled by player bounding box height
		magnitude = @sqrt(@min(velocity, 2)) * settings.viewBobStrength * game.Player.outerBoundingBoxExtent[2];
	}

	inline fn getPositionBobbing() Vec3d {
		game.Player.mutex.lock();
		defer game.Player.mutex.unlock();
		const xBob = @sin(time);
		const a = 0.5 * -@sin(2 * time);
		const zBob = ((a - a * a * a / 3) * 2 + 0.25 - 0.25 * @cos(2 * time)) * 0.8;
		var bobVec = vec.rotateZ(Vec3d{xBob * magnitude * 0.05, 0, zBob * magnitude * 0.05}, -rotation[2]);
		const eyeMin = game.Player.eyePos - game.Player.desiredEyePos + game.Player.eyeBox.min;
		const eyeMax = game.Player.eyePos - game.Player.desiredEyePos + game.Player.eyeBox.max;
		const eyeBoxSize = game.Player.eyeBox.max - game.Player.eyeBox.min;
		const scaling = @as(Vec3d, @splat(1)) - @as(Vec3d, @splat(2)) * @abs(game.Player.eyePos) / eyeBoxSize;
		bobVec = @max(eyeMin, @min(bobVec * scaling, eyeMax));
		return bobVec;
	}

	inline fn getRotationBobbing() Vec3f {
		game.Player.mutex.lock();
		defer game.Player.mutex.unlock();
		const xRot: f32 = @as(f32, @floatCast(@cos(time * 2 + 0.20) * -0.0015 * magnitude));
		const zRot: f32 = @as(f32, @floatCast(@sin(time + 0.5) * 0.001 * magnitude));
		return Vec3f{xRot, 0, zRot};
	}

	pub fn apply() void {
		if (!enabled) return;
		position += getPositionBobbing();
		rotation += getRotationBobbing();
	}

	pub fn remove() void {
		if (!enabled) return;
		position -= getPositionBobbing();
		rotation -= getRotationBobbing();
	}
};
