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

pub const id = "cubyz:rectangular_cuboid";

minRadii: Vec3f,
maxRadii: Vec3f,

const Instance = struct {
	radii: Vec3f,
};

pub fn initAndGetExtend(zon: ZonElement) sdf.SdfModel.InitResult {
	const self = main.worldArena.create(@This());
	self.minRadii = zon.get(Vec3f, "minSideLengths", @splat(32))/@as(Vec3f, @splat(2));
	self.maxRadii = zon.get(Vec3f, "maxSideLengths", self.minRadii*@as(Vec3f, @splat(2)))/@as(Vec3f, @splat(2));

	return .{.model = self, .maxExtend = .{
		.min = @floor(-self.maxRadii),
		.max = @ceil(self.maxRadii),
	}};
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const instance = arena.create(Instance);
	instance.* = .{
		.radii = self.minRadii + (self.maxRadii - self.minRadii)*main.random.nextFloatVector(3, seed),
	};
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = @floor(-instance.radii),
		.maxBounds = @ceil(instance.radii),
		.centerPosOffset = @ceil(instance.radii),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	const dimensionalSdf: Vec3f = @abs(samplePos) - self.radii;
	return vec.length(@max(dimensionalSdf, @as(Vec3f, @splat(0)))) + @min(0, @max(dimensionalSdf[0], dimensionalSdf[1], dimensionalSdf[2]));
}
