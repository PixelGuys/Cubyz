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

pub const id = "cubyz:partial_sphere";

minRadius: f32,
maxRadius: f32,
cutPercentage: f32,
cutDirection: Vec3f,
cutDirectionRandomness: f32,

const Instance = struct {
	radius: f32,
	cutPercentage: f32,
	cutDirection: Vec3f,
};

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	result.cutPercentage = zon.get(f32, "cutPercentage", 0.5);
	result.cutDirection = vec.normalize(zon.get(Vec3f, "cutDirection", .{0, 0, -1}));
	result.cutDirectionRandomness = zon.get(f32, "cutDirectionRandomness", 0);
	return result;
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const instance = arena.create(Instance);
	instance.* = .{.radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(seed), .cutDirection = vec.normalize(self.cutDirection + main.random.nextFloatVectorSigned(3, seed)*@as(Vec3f, @splat(self.cutDirectionRandomness))), .cutPercentage = self.cutPercentage};
	const bounds: Vec3f = @splat(instance.radius); // TODO: Could be tighter
	const offset: Vec3f = @splat(0); // TODO: Offset it to do the thing
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = @floor(-bounds + offset),
		.maxBounds = @ceil(bounds + offset),
		.centerPosOffset = @ceil(bounds + offset),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	const sphereSdf = vec.length(samplePos) - self.radius;
	const planeSdf = vec.dot(self.cutDirection, samplePos) - self.radius + self.cutPercentage*self.radius*2;
	return sdf.intersection(sphereSdf, planeSdf);
}
