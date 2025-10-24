const std = @import("std");

const vec = @import("vec.zig");

const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const Animation = struct {
	const Frame = struct {
		duration: f64,
		position: Vec3d,
		rotation: Vec3d,
	};

    length: f64 = 0,
    speed: f64 = 1,
	loop: bool = true,
	playTime: f64 = 0,
	currentFrame: u32 = 0,
    currentPosition: Vec3d = .{0, 0, 0},
    currentRotation: Vec3d = .{0, 0, 0},

    frames: [3]Frame = .{
        .{
            .duration = 0.65,
            .position = .{0, 0, 0},
            .rotation = .{0, 0, 0},
        },
        .{
            .duration = 0.35,
            .position = .{0.2, -0.1, 0.15},
            .rotation = .{0, 30, 0},
        },
        .{
            .duration = 0,
            .position = .{-0.2, 1, -0.2},
            .rotation = .{0, -120, 15},
        },
        // .{
        //     .duration = 0,
        //     .position = .{0, 0, 0},
        //     .rotation = .{0, 0, 0},
        // },
    },

    pub fn init(self: *Animation) void {
        for (&self.frames) |*frame| {
            self.length += frame.duration;
            frame.rotation = std.math.degreesToRadians(frame.rotation);
        }
    }

	pub fn update(self: *Animation, deltaTime: f64) void {
		self.playTime += deltaTime * self.speed;

        if(self.frames[self.currentFrame].duration <= self.playTime) {
			self.currentFrame += 1;
            self.playTime = 0;
		}
        
        if(self.loop and self.currentFrame >= self.frames.len-1) {
            self.currentFrame = 0;
        }

        self.currentPosition = self.getPosition();
        self.currentRotation = self.getRotation();
	}

    pub fn reset(self: *Animation) void {
        self.playTime = 0;
        self.currentFrame = 0;
        self.currentPosition = self.frames[0].position;
        self.currentRotation = self.frames[0].rotation;
    }

	pub fn getPosition(self: *Animation) Vec3d {
		const current = self.currentFrame;
		return std.math.lerp(
			self.frames[current].position, 
			self.frames[current+1].position, 
			@as(Vec3d, @splat(easeInOut(self.playTime/self.frames[current].duration))),
			);
	}

	pub fn getRotation(self: *Animation) Vec3d {
		const current = self.currentFrame;
		return std.math.lerp(
			self.frames[current].rotation, 
			self.frames[current+1].rotation, 
			@as(Vec3d, @splat(easeInOut(self.playTime/self.frames[current].duration))),
			);
	}

	pub inline fn easeInOut(x: f64) f64 {
		return -(@cos(std.math.pi*x) - 1)*0.5;
	}

	pub inline fn easeIn(x: f64) f64 {
		return 1 - @cos(std.math.pi*x*0.5);
	}
};