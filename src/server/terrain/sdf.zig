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
	generateFn: *const fn (self: *anyopaque, sdf: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void,
	maxBiomeCenterDistance: f32,
	minAmount: f32,
	maxAmount: f32,
	mode: enum { additive, subtractive },

	const VTable = struct {
		init: *const fn (parameters: ZonElement) ?*anyopaque,
		generate: *const fn (self: *anyopaque, sdf: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void,
	};

	pub fn initModel(parameters: ZonElement) ?SdfModel {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find SDF model with id {s}", .{id});
			return null;
		};
		const vtableModel = vtable.init(parameters) orelse {
			std.log.err("Error occurred while loading SDF model with id '{s}'. Dropping SDF from biome.", .{id});
			return null;
		};
		return .{
			.data = vtableModel,
			.generateFn = vtable.generate,
			.maxBiomeCenterDistance = std.math.clamp(parameters.get(f32, "maxBiomeCenterDistance", terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize/2), 0, terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize/2),
			.minAmount = parameters.get(f32, "minAmount", 1),
			.maxAmount = parameters.get(f32, "maxAmount", parameters.get(f32, "minAmount", 1)),
			.mode = parameters.get(@TypeOf(@as(SdfModel, undefined).mode), "mode", .subtractive),
		};
	}

	pub fn generate(self: SdfModel, sdf: main.utils.Array3D(f32), biomeMap: *const CaveBiomeMapView, interpolationSmoothness: main.utils.Array3D(f32), sdfPos: Vec3i, biomePos: Vec3i, seed: *u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
		const amount: usize = @intFromFloat(@floor(self.minAmount + main.random.nextFloat(seed)*(self.maxAmount - self.minAmount) + main.random.nextFloat(seed)));
		for (0..amount) |_| {
			const offsetDir = blk: while (true) {
				const offset = main.random.nextFloatVectorSigned(3, seed);
				if (vec.lengthSquare(offset) < 1) break :blk offset;
			};
			var pos = biomePos +% @as(Vec3i, @intFromFloat(offsetDir*@as(Vec3f, @splat(self.maxBiomeCenterDistance))));
			pos[2] +%= biomeMap.getCaveBiomeOffset(pos[0], pos[1]);
			self.generateFn(self.data, sdf, interpolationSmoothness, pos -% sdfPos, seed.*, perimeter, voxelSize, voxelSizeShift);
		}
	}

	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		var self: VTable = undefined;
		self.init = main.meta.castFunctionReturnToOptionalAnyopaque(Generator.init);
		self.generate = main.meta.castFunctionSelfToAnyopaque(Generator.generate);
		modelRegistry.put(main.globalArena.allocator, Generator.id, self) catch unreachable;
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
