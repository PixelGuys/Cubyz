const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const SdfModel = struct { // MARK: SdfModel
	data: *anyopaque,
	instantiateFn: *const fn (self: *anyopaque, arena: NeverFailingAllocator, seed: *u64) SdfInstance,
	maxBiomeCenterDistance: f32,
	minAmount: f32,
	maxAmount: f32,
	mode: enum { additive, subtractive },

	pub const InitResult = ?struct { model: *anyopaque, maxExtend: vec.Boxi };

	const VTable = struct {
		initAndGetExtend: *const fn (parameters: ZonElement) InitResult,
		instantiate: *const fn (self: *anyopaque, arena: NeverFailingAllocator, seed: *u64) SdfInstance,
	};

	pub fn initModel(parameters: ZonElement) ?struct { model: SdfModel, maxExtend: vec.Boxi } {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find SDF model with id {s}", .{id});
			return null;
		};
		const result = vtable.initAndGetExtend(parameters) orelse {
			std.log.err("Error occurred while loading SDF model with id '{s}'. Dropping SDF from biome.", .{id});
			return null;
		};
		return .{
			.model = .{
				.data = result.model,
				.instantiateFn = vtable.instantiate,
				.maxBiomeCenterDistance = std.math.clamp(parameters.get(f32, "maxBiomeCenterDistance", terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize/2), 0, terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize/2),
				.minAmount = parameters.get(f32, "minAmount", 1),
				.maxAmount = parameters.get(f32, "maxAmount", parameters.get(f32, "minAmount", 1)),
				.mode = parameters.get(@TypeOf(@as(SdfModel, undefined).mode), "mode", .subtractive),
			},
			.maxExtend = result.maxExtend,
		};
	}

	pub fn generate(self: SdfModel, sdf: main.utils.Array3D(f32), biomeMap: *const CaveBiomeMapView, interpolationSmoothness: main.utils.Array3D(f32), sdfPos: Vec3i, biomePos: Vec3i, seed: *u64, perimeter: comptime_int, voxelSize: u31, voxelSizeShift: u5) void {
		const amount: usize = @floor(self.minAmount + main.random.nextFloat(seed)*(self.maxAmount - self.minAmount) + main.random.nextFloat(seed));
		for (0..amount) |_| {
			const arena = main.stackAllocator.createArena();
			defer main.stackAllocator.destroyArena(arena);
			const offsetDir = blk: while (true) {
				const offset = main.random.nextFloatVectorSigned(3, seed);
				if (vec.lengthSquare(offset) < 1) break :blk offset;
			};
			var pos = biomePos +% @as(Vec3i, @trunc(offsetDir*@as(Vec3f, @splat(self.maxBiomeCenterDistance))));
			pos[2] +%= biomeMap.getCaveBiomeOffset(pos[0], pos[1]);
			var instance = self.instantiateFn(self.data, arena, seed);
			instance.minBounds +%= pos -% sdfPos;
			instance.maxBounds +%= pos -% sdfPos;
			instance.generate(sdf, interpolationSmoothness, perimeter, voxelSize, voxelSizeShift);
		}
	}

	pub fn instantiate(self: SdfModel, arena: NeverFailingAllocator, seed: *u64) SdfInstance {
		return self.instantiateFn(self.data, arena, seed);
	}

	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		var self: VTable = undefined;
		self.initAndGetExtend = Generator.initAndGetExtend;
		self.instantiate = main.meta.castFunctionSelfToAnyopaque(Generator.instantiate);
		modelRegistry.put(main.globalArena.allocator, Generator.id, self) catch unreachable;
	}
};

pub const SdfInstance = struct { // MARK: SdfInstance
	data: *anyopaque,
	generateFn: *const fn (self: *anyopaque, samplePos: Vec3f) f32,
	minBounds: Vec3i,
	maxBounds: Vec3i,
	centerPosOffset: Vec3f,

	pub fn generate(self: SdfInstance, sdf: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), perimeter: comptime_int, voxelSize: u31, voxelSizeShift: u5) void {
		const dimVector: Vec3i = @intCast(@Vector(3, u32){sdf.width*voxelSize, sdf.depth*voxelSize, sdf.height*voxelSize});
		const mask: @Vector(3, u31) = @splat(voxelSize - 1);
		const min = @max(Vec3i{0, 0, 0}, self.minBounds -% @as(Vec3i, @splat(perimeter))) & ~mask;
		const max = @min(dimVector, self.maxBounds +% @as(Vec3i, @splat(perimeter))) + mask & ~@as(Vec3i, mask);
		if (@reduce(.Or, max <= min)) return;

		var x = min[0] & ~(voxelSize - 1);
		while (x != max[0]) : (x += voxelSize) {
			var y = min[1] & ~(voxelSize - 1);
			while (y != max[1]) : (y += voxelSize) {
				var z = min[2] & ~(voxelSize - 1);
				while (z < max[2]) : (z += voxelSize) {
					const pos = @as(Vec3f, @floatFromInt(Vec3i{x, y, z} -% self.minBounds)) - self.centerPosOffset;
					const sdfSample = self.generateFn(self.data, pos);
					if (sdfSample > perimeter) continue;

					const out = sdf.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
					out.* = smoothUnion(sdfSample, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
				}
			}
		}
	}
};

pub fn smoothUnion(a: f32, b: f32, smoothness: f32) f32 { // https://iquilezles.org/articles/smin/ quadratic polynomial
	const k = 4*smoothness;
	const h = @max(k - @abs(a - b), 0.0)/k;
	return @min(a, b) - h*h*smoothness;
}

pub fn intersection(a: f32, b: f32) f32 {
	return @max(a, b);
}
