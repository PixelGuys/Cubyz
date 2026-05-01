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

pub const id = "cubyz:torus";

minRadius: f32,
maxRadius: f32,
minThickness: f32,
maxThickness: f32,

const Instance = struct {
	radius: f32,
	thickness: f32,
};

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	result.minThickness = zon.get(f32, "minThickness", result.minRadius/2);
	result.maxThickness = zon.get(f32, "maxThickness", result.minThickness);
	return result;
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const instance = arena.create(Instance);
	instance.* = .{
		.radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(seed),
		.thickness = self.minThickness + (self.maxThickness - self.minThickness)*main.random.nextFloat(seed),
	};
	const bounds: Vec3f = .{instance.radius + instance.thickness, instance.radius + instance.thickness, instance.thickness};
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = @floor(-bounds),
		.maxBounds = @ceil(bounds),
		.centerPosOffset = @ceil(bounds),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	const radialDistance: f32 = @sqrt(samplePos[0]*samplePos[0] + samplePos[1]*samplePos[1]);
	const adjustedDistance: f32 = radialDistance - self.radius;
	return @sqrt(adjustedDistance*adjustedDistance + samplePos[2]*samplePos[2]) - self.thickness;
}
