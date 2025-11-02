const std = @import("std");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

const c = @cImport({
    @cInclude("cgltf.h");
});

// pub fn cglfw_alloc(user: *anyopaque, data: []anyopaque) void {

// }

pub fn loadGltf() void {
    var options: c.cgltf_options = .{
        .type = c.cgltf_file_type_glb,
    };
    var data: *c.cgltf_data = undefined;
    // var file = main.files.cwd().read(main.stackAllocator, "assets/cubyz/entity/models/Untitled.gltf") catch |err| blk: {
    //         std.log.err("Error while reading player model: {s}", .{@errorName(err)});
    //         break :blk &.{};
    //     };
    // defer main.stackAllocator.free(file);

    // for (file) |i| {
    //     std.debug.print("{c}", .{i});
    // }
    
    // const result = c.cgltf_parse(&options, @ptrCast(&file), @intCast(file.len), @ptrCast(&data));
    var result = c.cgltf_parse_file(&options, "assets/cubyz/entity/models/snale_right_hand.glb", @ptrCast(&data));
    
    const name = switch (result) {
            0 =>  "result_success",
            1 =>  "result_data_too_short",
            2 =>  "result_unknown_format",
            3 =>  "result_invalid_json",
            4 =>  "result_invalid_gltf",
            5 =>  "result_invalid_options",
            6 =>  "result_file_not_found",
            7 =>  "result_io_error",
            8 =>  "result_out_of_memory",
            9 =>  "result_legacy_gltf",
            10 => "result_max_enum",
            else => unreachable,
        };
    std.debug.print("yuppii!!!!!!!!!!!!!!! size: {s}\n", .{name});
    if (result != c.cgltf_result_success) {
        return;
    }
    result = c.cgltf_load_buffers(&options, @ptrCast(data), "data:application/octet-stream");
    std.debug.print("yuppii>>>>>>>>> size: {s}\n", .{name});
    if (result != c.cgltf_result_success) {
        c.cgltf_free(@ptrCast(data));
        return;
    }
    std.debug.print("count: {d}\n", .{data.animations_count});
    for (data.animations, 0..data.animations_count) |anim, _| {
        std.debug.print("ANIM name: \"{s}\" samplerCount: {d} channelCount: {d}\n", .{anim.name, anim.samplers_count, anim.channels_count});
        
        for (anim.channels, 0..anim.channels_count) |channel, _| {
            const t = switch (channel.target_path) {
                0 => "animation_path_type_invalid",
                1 => "animation_path_type_translation",
                2 => "animation_path_type_rotation",
                3 => "animation_path_type_scale",
                4 => "animation_path_type_weights",
                5 => "animation_path_type_max_enum",
                else => unreachable,
            };
            std.debug.print("node: {s} target: {s}\n", .{channel.target_node[0].name, t});
            // for (channel.extras) |value| {}
            const sampler = channel.sampler.*;
            const l = switch (sampler.interpolation) {
                0 => "interpolation_type_linear",
                1 => "interpolation_type_step",
                2 => "interpolation_type_cubic_spline",
                3 => "interpolation_type_max_enum",
                else => unreachable,
            };
            const bv = sampler.output[0].buffer_view[0];
            std.debug.print("      lerp: \"{s}\"   data size: {d}\n", .{l, bv.buffer[0].size});
            std.debug.print("      offset: {d}   size: {d}   stride: {d}\n", .{bv.offset, bv.size, sampler.output.*.stride});
            var d: []u8 = undefined;
            if (bv.buffer[0].data) |da| {
                d = @as([]u8, @ptrCast(da));
                d.len = bv.buffer[0].size;
                d = d[bv.offset..bv.offset+bv.size];
                switch (channel.target_path) {
                    c.cgltf_animation_path_type_rotation => {
                        var rotations: []const [4]f32 = @alignCast(@ptrCast(d));   
                        rotations.len = @divFloor(bv.size, @sizeOf(f32) * 4);
                        for (rotations) |v| {
                            std.debug.print("         rot: {any}\n", .{v});
                        }
                    },
                    c.cgltf_animation_path_type_translation => {
                        var positions: []const [3]f32 = @alignCast(@ptrCast(d));   
                        positions.len = @divFloor(bv.size, @sizeOf(f32) * 3);
                        for (positions) |v| {
                            std.debug.print("         pos: {any}\n", .{v});
                        }
                    },
                    else => unreachable,
                }
            }
            
        }

    }
    std.debug.print("free!!\n", .{});
    c.cgltf_free(@ptrCast(data));
}

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