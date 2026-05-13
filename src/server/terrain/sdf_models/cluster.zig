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

pub fn initAndGetExtend(zon: ZonElement) sdf.SdfModel.InitResult {
	var list: main.List(Entry) = .init(main.stackAllocator);
	defer list.deinit();

	var maxExtend: vec.Boxi = .{
		.min = @splat(-1e9),
		.max = @splat(1e9),
	};

	for (zon.getChild("children").toSlice()) |child| {
		const childModelAndExtend = sdf.SdfModel.initModel(child) orelse return null;
		const childEntry: Entry = .{
			.model = childModelAndExtend.model,
			.positionOffset = child.get(Vec3f, "positionOffset", @splat(0)),
			.randomOffset = child.get(Vec3f, "randomOffset", @splat(0)),
		};
		maxExtend.min = @min(maxExtend.min, @as(Vec3i, @floor(@as(Vec3f, @floatFromInt(childModelAndExtend.maxExtend.min)) + childEntry.positionOffset - childEntry.randomOffset)));
		maxExtend.max = @max(maxExtend.max, @as(Vec3i, @ceil(@as(Vec3f, @floatFromInt(childModelAndExtend.maxExtend.max)) + childEntry.positionOffset + childEntry.randomOffset)));
		list.append(childEntry);
	}

	if (list.items.len == 0) {
		std.log.err("cubyz:cluster SDF expected at last one child SDF.", .{});
		return null;
	}

	const self = main.worldArena.create(@This());
	self.children = main.worldArena.dupe(Entry, list.items);
	self.smoothness = zon.get(f32, "smothness", 4);
	return .{.model = self, .maxExtend = maxExtend};
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
