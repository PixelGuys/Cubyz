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

pub const id = "cubyz:sphere";

minRadius: f32,
maxRadius: f32,

const Instance = struct {
	radius: f32,
};

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	return result;
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const instance = arena.create(Instance);
	instance.* = .{
		.radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(seed),
	};
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = @splat(@floor(-instance.radius)),
		.maxBounds = @splat(@ceil(instance.radius)),
		.centerPosOffset = @splat(@ceil(instance.radius)),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	return vec.length(samplePos) - self.radius;
}
