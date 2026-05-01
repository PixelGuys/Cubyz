const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const sdf = main.server.terrain.sdf;
const SdfInstance = sdf.SdfInstance;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:rotated";

const Axis = enum { x, y, z };

const Entry = struct {
	model: sdf.SdfModel,
	positionOffset: Vec3f,
	randomOffset: Vec3f,
};

child: sdf.SdfModel,
axis: Axis,
minAngle: f32,
maxAngle: f32,

const Instance = struct {
	child: SdfInstance,
	axis: Axis,
	sin: f32,
	cos: f32,
};

pub fn init(zon: ZonElement) ?*@This() {
	const child = sdf.SdfModel.initModel(zon.getChild("child")) orelse return null;
	const result = main.worldArena.create(@This());
	result.child = child;
	result.axis = zon.get(?Axis, "axis", null) orelse {
		std.log.err("Missing parameter axis for cubyz:rotated SDF.", .{});
		return null;
	};
	result.minAngle = std.math.degreesToRadians(zon.get(f32, "minAngle", 0));
	result.maxAngle = std.math.degreesToRadians(zon.get(f32, "maxAngle", 360));
	return result;
}

fn rotate(axis: Axis, sin: f32, cos: f32, in: Vec3f) Vec3f {
	switch (axis) {
		.x => {
			return .{
				in[0],
				in[1]*cos - in[2]*sin,
				in[1]*sin + in[2]*cos,
			};
		},
		.y => {
			return .{
				in[0]*cos + in[2]*sin,
				in[1],
				-in[0]*sin + in[2]*cos,
			};
		},
		.z => {
			return .{
				in[0]*cos - in[1]*sin,
				in[0]*sin + in[1]*cos,
				in[2],
			};
		},
	}
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const angle = self.minAngle + (self.maxAngle - self.minAngle)*main.random.nextFloat(seed);
	const sin = @sin(angle);
	const cos = @cos(angle);
	const child = self.child.instantiate(arena, seed);
	var minBounds: Vec3i = @splat(1e9);
	var maxBounds: Vec3i = @splat(-1e9);
	for (0..2) |xi| {
		const x = if (xi == 0) child.minBounds[0] else child.maxBounds[0];
		for (0..2) |yi| {
			const y = if (yi == 0) child.minBounds[1] else child.maxBounds[1];
			for (0..2) |zi| {
				const z = if (zi == 0) child.minBounds[2] else child.maxBounds[2];
				const rotatedCorner = rotate(self.axis, sin, cos, @floatFromInt(Vec3i{x, y, z}));
				minBounds = @min(minBounds, @as(Vec3i, @floor(rotatedCorner)));
				maxBounds = @max(maxBounds, @as(Vec3i, @ceil(rotatedCorner)));
			}
		}
	}

	const instance = arena.create(Instance);
	instance.* = .{
		.child = child,
		.axis = self.axis,
		.sin = sin,
		.cos = cos,
	};
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = minBounds,
		.maxBounds = maxBounds,
		.centerPosOffset = @floatFromInt(-minBounds),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	const rotatedPos = rotate(self.axis, self.sin, self.cos, samplePos);
	return self.child.generateFn(self.child.data, rotatedPos);
}
