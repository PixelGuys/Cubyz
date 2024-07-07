const std = @import("std");

const main = @import("root");
const Array3D = main.utils.Array3D;
const Cache = main.utils.Cache;
const ServerChunk = main.chunk.ServerChunk;
const ChunkPosition = main.chunk.ChunkPosition;
const JsonElement = main.JsonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const MapFragment = terrain.SurfaceMap.MapFragment;
const Biome = terrain.biomes.Biome;
const SurfaceMap = terrain.SurfaceMap;

/// Cave biome data from a big chunk of the world.
pub const CaveBiomeMapFragment = struct {
	pub const caveBiomeShift = 7;
	pub const caveBiomeSize = 1 << caveBiomeShift;
	pub const caveBiomeMask = caveBiomeSize - 1;
	pub const caveBiomeMapShift = 11;
	pub const caveBiomeMapSize = 1 << caveBiomeMapShift;
	pub const caveBiomeMapMask = caveBiomeMapSize - 1;

	pos: main.chunk.ChunkPosition,
	biomeMap: [1 << 3*(caveBiomeMapShift - caveBiomeShift)][2]*const Biome = undefined,
	refCount: std.atomic.Value(u16) = std.atomic.Value(u16).init(0),

	pub fn init(self: *CaveBiomeMapFragment, wx: i32, wy: i32, wz: i32) void {
		self.* = .{
			.pos = main.chunk.ChunkPosition {
				.wx = wx, .wy = wy, .wz = wz,
				.voxelSize = caveBiomeSize
			},
		};
	}

	pub fn getIndex(_relX: u31, _relY: u31, _relZ: u31) usize {
		var relX: usize = _relX;
		var relY: usize = _relY;
		var relZ: usize = _relZ;
		std.debug.assert(relX < caveBiomeMapSize);
		std.debug.assert(relY < caveBiomeMapSize);
		std.debug.assert(relZ < caveBiomeMapSize);
		relX >>= caveBiomeShift;
		relY >>= caveBiomeShift;
		relZ >>= caveBiomeShift;
		return relX << 2*(caveBiomeMapShift - caveBiomeShift) | relY << caveBiomeMapShift-caveBiomeShift | relZ;
	}

	pub fn increaseRefCount(self: *CaveBiomeMapFragment) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *CaveBiomeMapFragment) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			main.globalAllocator.destroy(self);
		}
	}
};

/// A generator for the cave biome map.
pub const CaveBiomeGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generate: *const fn(map: *CaveBiomeMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(CaveBiomeGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = CaveBiomeGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: JsonElement) []CaveBiomeGenerator {
		const list = allocator.alloc(CaveBiomeGenerator, generatorRegistry.size);
		var iterator = generatorRegistry.iterator();
		var i: usize = 0;
		while(iterator.next()) |generator| {
			list[i] = generator.value_ptr.*;
			list[i].init(settings.getChild(generator.key_ptr.*));
			i += 1;
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: CaveBiomeGenerator, rhs: CaveBiomeGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(CaveBiomeGenerator, list, {}, lessThan);
		return list;
	}
};

/// Doesn't allow getting the biome at one point and instead is only useful for interpolating values between biomes.
pub const InterpolatableCaveBiomeMapView = struct {
	fragments: [8]*CaveBiomeMapFragment,
	surfaceFragments: [4]*MapFragment,
	pos: ChunkPosition,
	width: i32,

	pub fn init(pos: ChunkPosition, width: i32) InterpolatableCaveBiomeMapView {
		return InterpolatableCaveBiomeMapView {
			.fragments = [_]*CaveBiomeMapFragment {
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz -% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz +% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz -% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz +% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz -% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy -% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz +% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz -% CaveBiomeMapFragment.caveBiomeMapSize/2),
				getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wy +% CaveBiomeMapFragment.caveBiomeMapSize/2, pos.wz +% CaveBiomeMapFragment.caveBiomeMapSize/2),
			},
			.surfaceFragments = [_]*MapFragment {
				SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% 32, pos.wy -% 32, pos.voxelSize),
				SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(pos.wx -% 32, pos.wy +% width +% 32, pos.voxelSize),
				SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% width +% 32, pos.wy -% 32, pos.voxelSize),
				SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(pos.wx +% width +% 32, pos.wy +% width +% 32, pos.voxelSize),
			},
			.pos = pos,
			.width = width,
		};
	}

	pub fn deinit(self: InterpolatableCaveBiomeMapView) void {
		for(self.fragments) |mapFragment| {
			mapFragment.decreaseRefCount();
		}
		for(self.surfaceFragments) |mapFragment| {
			mapFragment.decreaseRefCount();
		}
	}

	fn rotate231(in: Vec3i) Vec3i {
		return @shuffle(i32, in, undefined, Vec3i{1, 2, 0});
	}
	fn rotate312(in: Vec3i) Vec3i {
		return @shuffle(i32, in, undefined, Vec3i{2, 0, 1});
	}
	fn argMaxDistance0(distance: Vec3i) @Vector(3, bool) {
		const absDistance = @abs(distance);
		if(absDistance[0] > absDistance[1]) {
			if(absDistance[0] > absDistance[2]) {
				return .{true, false, false};
			} else {
				return .{false, false, true};
			}
		} else {
			if(absDistance[1] > absDistance[2]) {
				return .{false, true, false};
			} else {
				return .{false, false, true};
			}
		}
	}
	fn argMaxDistance1(distance: Vec3i) @Vector(3, bool) {
		const absDistance = @abs(distance);
		if(absDistance[0] >= absDistance[1]) {
			if(absDistance[0] >= absDistance[2]) {
				return .{true, false, false};
			} else {
				return .{false, false, true};
			}
		} else {
			if(absDistance[1] >= absDistance[2]) {
				return .{false, true, false};
			} else {
				return .{false, false, true};
			}
		}
	}

	/// Return either +1 or -1 depending on the sign of the input number.
	fn nonZeroSign(in: Vec3i) Vec3i {
		return @select(i32, in >= Vec3i{0, 0, 0}, Vec3i{1, 1, 1}, Vec3i{-1, -1, -1});
	}

	pub fn bulkInterpolateValue(self: InterpolatableCaveBiomeMapView, comptime field: []const u8, wx: i32, wy: i32, wz: i32, voxelSize: u31, map: Array3D(f32), comptime mode: enum{addToMap}, comptime scale: f32) void {
		var x: u31 = 0;
		while(x < map.width) : (x += 1) {
			var y: u31 = 0;
			while(y < map.height) : (y += 1) {
				var z: u31 = 0;
				while(z < map.depth) : (z += 1) {
					switch (mode) {
						.addToMap => {
							// TODO: Do a tetrahedron voxelization here, so parts of the tetrahedral barycentric coordinates can be precomputed.
							map.ptr(x, y, z).* += scale*interpolateValue(self, wx +% x*voxelSize, wy +% y*voxelSize, wz +% z*voxelSize, field);
						}
					}
				}
			}
		}
	}

	pub noinline fn interpolateValue(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, comptime field: []const u8) f32 {
		const worldPos = Vec3i{wx, wy, wz};
		const closestGridpoint0 = (worldPos +% @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2))) & @as(Vec3i, @splat(~@as(i32, CaveBiomeMapFragment.caveBiomeMask)));
		const distance0 = worldPos -% closestGridpoint0;
		const step0 = @select(i32, argMaxDistance0(distance0), @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize)), @as(Vec3i, @splat(0)));
		const secondGridPoint0 = closestGridpoint0 +% step0*nonZeroSign(distance0);

		const closestGridpoint1 = (worldPos & @as(Vec3i, @splat(~@as(i32, CaveBiomeMapFragment.caveBiomeMask)))) +% @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2));
		const distance1 = worldPos -% closestGridpoint1;
		const step1 = @select(i32, argMaxDistance1(distance1), @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize)), @as(Vec3i, @splat(0)));
		const secondGridPoint1 = closestGridpoint1 +% step1*nonZeroSign(distance1);

		const @"r⃗₄" = closestGridpoint0;
		const @"r⃗₃" = secondGridPoint0;
		const @"r⃗₂" = closestGridpoint1;
		const @"r⃗₁" = secondGridPoint1;
		// Doing tetrahedral interpolation between the given points.
		// Barycentric coordinates for tetrahedra:
		// λ₄ = 1 - λ₁ - λ₂ - λ₃
		// ┌                       ┐   ┌  ┐   ┌      ┐
		// | x₁-x₄   x₂-x₄   x₃-x₄ |   |λ₁|   | x-x₄ |
		// | y₁-y₄   y₂-y₄   y₃-y₄ | · |λ₂| = | y-y₄ | =: d⃗
		// | z₁-z₄   z₂-z₄   z₃-z₄ |   |λ₃|   | z-z₄ |
		// └                       ┘   └  ┘   └      ┘
		//  \_________  __________/
		//            \/
		//           =: A
		const @"d⃗" = distance0;
		const @"d⃗₁" = @"r⃗₁" -% @"r⃗₄";
		const @"d⃗₂" = @"r⃗₂" -% @"r⃗₄";
		const @"d⃗₃" = @"r⃗₃" -% @"r⃗₄";
		// With some renamings we get:
		//     ┌            ┐
		// A = | d⃗₁  d⃗₂  d⃗₃ |
		//     └            ┘

		// The inverse of a 3×3 matrix is given by:
		//     ┌               ┐
		//     | a₁₁  a₁₂  a₁₃ |
		// A = | a₂₁  a₂₂  a₂₃ |
		//     | a₃₁  a₃₂  a₃₃ |
		//     └               ┘
		//           ┌                               ┐
		//           | |a₂₂ a₂₃| |a₁₃ a₁₂| |a₁₂ a₁₃| |
		//           | |a₃₂ a₃₃| |a₃₃ a₃₂| |a₂₂ a₂₃| |
		//        1  |                               |
		// A⁻¹ = ––– | |a₂₃ a₂₁| |a₁₁ a₁₃| |a₁₃ a₁₁| |
		//       |A| | |a₃₃ a₃₁| |a₃₁ a₃₃| |a₂₃ a₂₁| |
		//           |                               |
		//           | |a₂₁ a₂₂| |a₁₂ a₁₁| |a₁₁ a₁₂| |
		//           | |a₃₁ a₃₂| |a₃₂ a₃₁| |a₂₁ a₂₂| |
		//           └                               ┘
		// Resolving the determinants gives:
		//           ┌                                                               ┐
		//           | a₂₂·a₃₃ - a₂₃·a₃₂     a₁₃·a₃₂ - a₁₂·a₃₃     a₁₂·a₂₃ - a₁₃·a₂₂ |
		//        1  |                                                               |
		// A⁻¹ = ––– | a₂₃·a₃₁ - a₂₁·a₃₃     a₁₁·a₃₃ - a₁₃·a₃₁     a₁₃·a₂₁ - a₁₁·a₂₃ |
		//       |A| |                                                               |
		//           | a₂₁·a₃₂ - a₂₂·a₃₁     a₁₂·a₃₁ - a₁₁·a₃₂     a₁₁·a₂₂ - a₁₂·a₂₁ |
		//           └                                                               ┘
		// Notice how each column represents a rotated row of the original matrix.
		const row1 = Vec3i{@"d⃗₁"[0], @"d⃗₂"[0], @"d⃗₃"[0]};
		const row2 = Vec3i{@"d⃗₁"[1], @"d⃗₂"[1], @"d⃗₃"[1]};
		const row3 = Vec3i{@"d⃗₁"[2], @"d⃗₂"[2], @"d⃗₃"[2]};
		const determinantCol1 = rotate231(row2)*rotate312(row3) - rotate312(row2)*rotate231(row3);
		const determinantCol2 = rotate312(row1)*rotate231(row3) - rotate231(row1)*rotate312(row3);
		const determinantCol3 = rotate231(row1)*rotate312(row2) - rotate312(row1)*rotate231(row2);
		// Notice that the determinant |A| can be expressed as dot(row1, determinantCol1)
		const determinantA = vec.dot(determinantCol1, row1);
		const invDeterminantA = 1.0/@as(f32, @floatFromInt(determinantA));
		// Now we change the memory layout use rows instead of columns to make matrix-vector multiplication easier later.
		const determinantRow1 = Vec3i{determinantCol1[0], determinantCol2[0], determinantCol3[0]};
		const determinantRow2 = Vec3i{determinantCol1[1], determinantCol2[1], determinantCol3[1]};
		const determinantRow3 = Vec3i{determinantCol1[2], determinantCol2[2], determinantCol3[2]};

		const @"unscaledλ123" = Vec3i{vec.dot(determinantRow1, @"d⃗"), vec.dot(determinantRow2, @"d⃗"), vec.dot(determinantRow3, @"d⃗")};
		const @"λ1" = @as(f32, @floatFromInt(@"unscaledλ123"[0]))*invDeterminantA;
		const @"λ2" = @as(f32, @floatFromInt(@"unscaledλ123"[1]))*invDeterminantA;
		const @"λ3" = @as(f32, @floatFromInt(@"unscaledλ123"[2]))*invDeterminantA;
		const @"λ4" = 1 - @"λ1" - @"λ2" - @"λ3";
		// TODO: I wonder if there are some optimizations possible, given that
		// per construction |x₁ - x₄| = |x₂ - x₄| = ... = |z₂ - z₄| = ±caveBiomeSize/2
		// And |r⃗₃ - r⃗₄| = caveBiomeSize, where 2 elements are 0

		// Now after all this math we can finally do what we actually want: Interpolate the damn thing.
		const biome4 = self._getBiome(closestGridpoint0[0], closestGridpoint0[1], closestGridpoint0[2], 0);
		const biome3 = self._getBiome(secondGridPoint0[0], secondGridPoint0[1], secondGridPoint0[2], 0);
		const biome2 = self._getBiome(closestGridpoint1[0], closestGridpoint1[1], closestGridpoint1[2], 1);
		const biome1 = self._getBiome(secondGridPoint1[0], secondGridPoint1[1], secondGridPoint1[2], 1);
		return @field(biome1, field)*@"λ1" + @field(biome2, field)*@"λ2" + @field(biome3, field)*@"λ3" + @field(biome4, field)*@"λ4";
	}

	fn checkSurfaceBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32) ?*const Biome {
		var index: u8 = 0;
		if(wx -% self.surfaceFragments[0].pos.wx >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 2;
		}
		if(wy -% self.surfaceFragments[0].pos.wy >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 1;
		}
		const height: i32 = self.surfaceFragments[index].getHeight(wx, wy);
		if(wz < height - 32*self.pos.voxelSize or wz > height + 128 + self.pos.voxelSize) return null;
		return self.surfaceFragments[index].getBiome(wx, wy);
	}

	pub fn getSurfaceHeight(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32) i32 {
		var index: u8 = 0;
		if(wx -% self.surfaceFragments[0].pos.wx >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 2;
		}
		if(wy -% self.surfaceFragments[0].pos.wy >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 1;
		}
		return self.surfaceFragments[index].getHeight(wx, wy);
	}

	noinline fn _getBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, map: u1) *const Biome {
		var index: u8 = 0;
		if(wx -% self.fragments[0].pos.wx >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 4;
		}
		if(wy -% self.fragments[0].pos.wy >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 2;
		}
		if(wz -% self.fragments[0].pos.wz >= CaveBiomeMapFragment.caveBiomeMapSize) {
			index += 1;
		}
		const relX: u31 = @intCast(wx - self.fragments[index].pos.wx);
		const relY: u31 = @intCast(wy - self.fragments[index].pos.wy);
		const relZ: u31 = @intCast(wz - self.fragments[index].pos.wz);
		const indexInArray = CaveBiomeMapFragment.getIndex(relX, relY, relZ);
		return self.fragments[index].biomeMap[indexInArray][map];
	}

	/// Useful when the rough biome location is enough, for example for music.
	pub noinline fn getRoughBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, comptime getSeed: bool, seed: *u64, comptime _checkSurfaceBiome: bool) *const Biome {
		if(_checkSurfaceBiome) {
			if(self.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
				return surfaceBiome;
			}
		}
		var gridPointX = (wx +% CaveBiomeMapFragment.caveBiomeSize/2) & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		var gridPointY = (wy +% CaveBiomeMapFragment.caveBiomeSize/2) & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		var gridPointZ = (wz +% CaveBiomeMapFragment.caveBiomeSize/2) & ~@as(i32, CaveBiomeMapFragment.caveBiomeMask);
		var map: u1 = 0;
		const distanceX = wx -% gridPointX;
		const distanceY = wy -% gridPointY;
		const distanceZ = wz -% gridPointZ;
		const totalDistance = @abs(distanceX) + @abs(distanceY) + @abs(distanceZ);
		if(totalDistance > CaveBiomeMapFragment.caveBiomeSize*3/4) {
			// Or with 1 to prevent errors if the value is 0.
			gridPointX +%= (std.math.sign(distanceX | 1) - 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			gridPointY +%= (std.math.sign(distanceY | 1) - 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			gridPointZ +%= (std.math.sign(distanceZ | 1) - 1)*(CaveBiomeMapFragment.caveBiomeSize/2);
			map = 1;
		}

		if(getSeed) {
			// A good old "I don't know what I'm doing" hash (TODO: Use some standard hash maybe):
			seed.* = @as(u64, @bitCast(@as(i64, gridPointX) << 48 ^ @as(i64, gridPointY) << 23 ^ @as(i64, gridPointZ) << 11 ^ @as(i64, gridPointX) >> 5 ^ @as(i64, gridPointY) << 3 ^ @as(i64, gridPointZ) ^ @as(i64, map)*5427642781)) ^ main.server.world.?.seed;
		}

		return self._getBiome(gridPointX, gridPointY, gridPointZ, map);
	}
};

pub const CaveBiomeMapView = struct {
	const CachedFractalNoise3D = terrain.noise.CachedFractalNoise3D;

	super: InterpolatableCaveBiomeMapView,
	noiseX: ?CachedFractalNoise3D = null,
	noiseY: ?CachedFractalNoise3D = null,
	noiseZ: ?CachedFractalNoise3D = null,

	pub fn init(chunk: *ServerChunk) CaveBiomeMapView {
		const pos = chunk.super.pos;
		const width = chunk.super.width;
		var self = CaveBiomeMapView {
			.super = InterpolatableCaveBiomeMapView.init(pos, width),
		};
		if(pos.voxelSize < 8) {
			const startX = (pos.wx -% 32) & ~@as(i32, 63);
			const startY = (pos.wy -% 32) & ~@as(i32, 63);
			const startZ = (pos.wz -% 32) & ~@as(i32, 63);
			self.noiseX = CachedFractalNoise3D.init(startX, startY, startZ, pos.voxelSize*4, width + 128, main.server.world.?.seed ^ 0x764923684396, 64);
			self.noiseY = CachedFractalNoise3D.init(startX, startY, startZ, pos.voxelSize*4, width + 128, main.server.world.?.seed ^ 0x6547835649265429, 64);
			self.noiseZ = CachedFractalNoise3D.init(startX, startY, startZ, pos.voxelSize*4, width + 128, main.server.world.?.seed ^ 0x56789365396783, 64);
		}
		return self;
	}

	pub fn deinit(self: CaveBiomeMapView) void {
		self.super.deinit();
		if(self.noiseX) |noiseX| {
			noiseX.deinit();
		}
		if(self.noiseY) |noiseY| {
			noiseY.deinit();
		}
		if(self.noiseZ) |noiseZ| {
			noiseZ.deinit();
		}
	}

	pub fn getSurfaceHeight(self: CaveBiomeMapView, wx: i32, wy: i32) i32 {
		return self.super.getSurfaceHeight(wx, wy);
	}

	pub fn getBiome(self: CaveBiomeMapView, relX: i32, relY: i32, relZ: i32) *const Biome {
		return self.getBiomeAndSeed(relX, relY, relZ, false, undefined);
	}

	/// Also returns a seed that is unique for the corresponding biome position.
	pub noinline fn getBiomeAndSeed(self: CaveBiomeMapView, relX: i32, relY: i32, relZ: i32, comptime getSeed: bool, seed: *u64) *const Biome {
		std.debug.assert(relX >= -32 and relX < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relY >= -32 and relY < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relZ >= -32 and relZ < self.super.width + 32); // coordinate out of bounds
		var wx = relX +% self.super.pos.wx;
		var wy = relY +% self.super.pos.wy;
		var wz = relZ +% self.super.pos.wz;
		if(self.super.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
			return surfaceBiome;
		}
		if(self.noiseX) |noiseX| if(self.noiseY) |noiseY| if(self.noiseZ) |noiseZ| {
			//                                                  ↓ intentionally cycled the noises to get different seeds.
			const valueX = noiseX.getValue(wx, wy, wz)*0.5 + noiseY.getRandomValue(wx, wy, wz)*8;
			const valueY = noiseY.getValue(wx, wy, wz)*0.5 + noiseZ.getRandomValue(wx, wy, wz)*8;
			const valueZ = noiseZ.getValue(wx, wy, wz)*0.5 + noiseX.getRandomValue(wx, wy, wz)*8;
			wx +%= @intFromFloat(valueX);
			wy +%= @intFromFloat(valueY);
			wz +%= @intFromFloat(valueZ);
		};

		return self.super.getRoughBiome(wx, wy, wz, getSeed, seed, false);
	}
};

const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: Cache(CaveBiomeMapFragment, cacheSize, associativity, CaveBiomeMapFragment.decreaseRefCount) = .{};

var profile: TerrainGenerationProfile = undefined;

pub fn initGenerators() void {
	const list = @import("cavebiomegen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		CaveBiomeGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	CaveBiomeGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

fn cacheInit(pos: ChunkPosition) *CaveBiomeMapFragment {
	const mapFragment = main.globalAllocator.create(CaveBiomeMapFragment);
	mapFragment.init(pos.wx, pos.wy, pos.wz);
	for(profile.caveBiomeGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	_= @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .monotonic);
	return mapFragment;
}

fn getOrGenerateFragmentAndIncreaseRefCount(_wx: i32, _wy: i32, _wz: i32) *CaveBiomeMapFragment {
	const wx = _wx & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wy = _wy & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wz = _wz & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const compare = ChunkPosition {
		.wx = wx, .wy = wy, .wz = wz,
		.voxelSize = CaveBiomeMapFragment.caveBiomeSize,
	};
	const result = cache.findOrCreate(compare, cacheInit, CaveBiomeMapFragment.increaseRefCount);
	return result;
}