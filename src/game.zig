const std = @import("std");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;
const graphics = @import("graphics.zig");
const Fog = graphics.Fog;

pub const camera = struct {
	var rotation: Vec3f = Vec3f{.x = 0, .y = 0, .z = 0};
	var direction: Vec3f = Vec3f{0, 0, 0};
	pub var viewMatrix: Mat4f = Mat4f.identity();
	pub fn moveRotation(mouseX: f32, mouseY: f32) void {
		// Mouse movement along the x-axis rotates the image along the y-axis.
		rotation.x += mouseY;
		if(rotation.x > std.math.pi/2) {
			rotation.x = std.math.pi/2;
		} else if(rotation.x < -std.math.pi/2) {
			rotation.x = -std.math.pi/2;
		}
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation.y += mouseX;

		direction = Vec3f.rotateX(Vec3f{0, 0, -1}, rotation.x).rotateY(rotation.y);
	}

	pub fn updateViewMatrix() void {
		viewMatrix = Mat4f.rotationY(rotation.y).mul(Mat4f.rotationX(rotation.x));
	}
};

pub const World = u1; // TODO
pub var testWorld: World = 0;
pub var world: ?*World = &testWorld;

pub var projectionMatrix: Mat4f = Mat4f.identity();
pub var lodProjectionMatrix: Mat4f = Mat4f.identity();

pub var fog = Fog{.active = true, .color=.{.x=0.5, .y=0.5, .z=0.5}, .density=0.025};