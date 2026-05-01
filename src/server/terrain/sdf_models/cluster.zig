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

pub const id = "cubyz:cluster";

const Entry = struct {
	model: sdf.SdfModel,
	positionOffset: Vec3f,
	randomOffset: Vec3f,
};

children: []const Entry,
smoothness: f32,

const Instance = struct {
	children: []SdfInstance,
	smoothness: f32,
};

pub fn init(zon: ZonElement) ?*@This() {
	var list: main.List(Entry) = .init(main.stackAllocator);
	defer list.deinit();
	for (zon.getChild("children").toSlice()) |child| {
		list.append(.{
			.model = sdf.SdfModel.initModel(child) orelse return null,
			.positionOffset = child.get(Vec3f, "positionOffset", @splat(0)),
			.randomOffset = child.get(Vec3f, "randomOffset", @splat(0)),
		});
	}
	const result = main.worldArena.create(@This());
	result.children = main.worldArena.dupe(Entry, list.items);
	result.smoothness = zon.get(f32, "smothness", 4);
	return result;
}

pub fn instantiate(self: *@This(), arena: NeverFailingAllocator, seed: *u64) SdfInstance {
	const instance = arena.create(Instance);
	instance.* = .{
		.children = arena.alloc(SdfInstance, self.children.len),
		.smoothness = self.smoothness,
	};
	var minPos: Vec3i = @splat(1e9);
	var maxPos: Vec3i = @splat(-1e9);
	for (self.children, instance.children) |entry, *result| {
		result.* = entry.model.instantiate(arena, seed);
		result.minBounds +%= @trunc(entry.positionOffset + entry.randomOffset*main.random.nextFloatVectorSigned(3, seed));
		result.maxBounds +%= @trunc(entry.positionOffset + entry.randomOffset*main.random.nextFloatVectorSigned(3, seed));
		minPos = @min(minPos, result.minBounds);
		maxPos = @max(maxPos, result.maxBounds);
	}
	return .{
		.data = instance,
		.generateFn = main.meta.castFunctionSelfToAnyopaque(generate),
		.minBounds = minPos,
		.maxBounds = maxPos,
		.centerPosOffset = @floatFromInt(-minPos),
	};
}

pub fn generate(self: *Instance, samplePos: Vec3f) f32 {
	var fullSdf: f32 = 1e9;
	for (self.children) |child| {
		const pos = samplePos - @as(Vec3f, @floatFromInt(child.minBounds)) - child.centerPosOffset;
		fullSdf = sdf.smoothUnion(fullSdf, child.generateFn(child.data, pos), self.smoothness);
	}
	return fullSdf;
}
