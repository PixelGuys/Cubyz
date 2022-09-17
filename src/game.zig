const std = @import("std");

const assets = @import("assets.zig");
const main = @import("main.zig");
const keyboard = &main.keyboard;
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;
const graphics = @import("graphics.zig");
const Fog = graphics.Fog;

pub const camera = struct {
	var rotation: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	var direction: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var viewMatrix: Mat4f = Mat4f.identity();
	pub fn moveRotation(mouseX: f32, mouseY: f32) void {
		// Mouse movement along the x-axis rotates the image along the y-axis.
		rotation.x += mouseY;
		if(rotation.x > std.math.pi/2.0) {
			rotation.x = std.math.pi/2.0;
		} else if(rotation.x < -std.math.pi/2.0) {
			rotation.x = -std.math.pi/2.0;
		}
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation.y += mouseX;

		direction = Vec3f.rotateX(Vec3f{.x=0, .y=0, .z=-1}, rotation.x).rotateY(rotation.y);
	}

	pub fn updateViewMatrix() void {
		viewMatrix = Mat4f.rotationX(rotation.x).mul(Mat4f.rotationY(rotation.y));
	}
};

pub var playerPos: Vec3d = Vec3d{.x=0, .y=0, .z=0};
pub var isFlying: bool = true;

pub var blockPalette: *assets.BlockPalette = undefined;
pub const World = u1; // TODO
pub var testWorld: World = 0;
pub var world: ?*World = &testWorld;

pub var projectionMatrix: Mat4f = Mat4f.identity();
pub var lodProjectionMatrix: Mat4f = Mat4f.identity();

pub var fog = Fog{.active = true, .color=.{.x=0, .y=1, .z=0.5}, .density=1.0/15.0/256.0};


pub fn update(deltaTime: f64) void {
	var movement = Vec3d{.x=0, .y=0, .z=0};
	var forward = Vec3d.rotateY(Vec3d{.x=0, .y=0, .z=-1}, -camera.rotation.y);
	var right = Vec3d{.x=forward.z, .y=0, .z=-forward.x};
	if(keyboard.forward.pressed) {
		if(keyboard.sprint.pressed) {
			if(isFlying) {
				movement.addEqual(forward.mulScalar(64));
			} else {
				movement.addEqual(forward.mulScalar(8));
			}
		} else {
			movement.addEqual(forward.mulScalar(4));
		}
	}
	if(keyboard.backward.pressed) {
		movement.addEqual(forward.mulScalar(-4));
	}
	if(keyboard.left.pressed) {
		movement.addEqual(right.mulScalar(4));
	}
	if(keyboard.right.pressed) {
		movement.addEqual(right.mulScalar(-4));
	}
	if(keyboard.jump.pressed) {
		if(isFlying) {
			if(keyboard.sprint.pressed) {
				movement.y = 59.45;
			} else {
				movement.y = 5.45;
			}
		} else { // TODO: if (Cubyz.player.isOnGround())
			movement.y = 5.45;
		}
	}
	if(keyboard.fall.pressed) {
		if(isFlying) {
			if(keyboard.sprint.pressed) {
				movement.y = -59.45;
			} else {
				movement.y = -5.45;
			}
		}
	}

	playerPos.addEqual(movement.mulScalar(deltaTime));
}