const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const Cache = main.utils.Cache;
const ServerChunk = main.chunk.ServerChunk;
const ChunkPosition = main.chunk.ChunkPosition;
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const MapFragment = terrain.SurfaceMap.MapFragment;
const Biome = terrain.biomes.Biome;
const SurfaceMap = terrain.SurfaceMap;

/// Cave biome data from a big chunk of the world.
pub const CaveBiomeMapFragment = struct { // MARK: caveBiomeMapFragment
	pub const caveBiomeShift = 7;
	pub const caveBiomeSize = 1 << caveBiomeShift;
	pub const caveBiomeMask = caveBiomeSize - 1;
	pub const caveBiomeMapShift = 11;
	pub const caveBiomeMapSize = 1 << caveBiomeMapShift;
	pub const caveBiomeMapMask = caveBiomeMapSize - 1;

	pos: main.chunk.ChunkPosition,
	biomeMap: [1 << 3*(caveBiomeMapShift - caveBiomeShift)][2]*const Biome = undefined,

	pub fn init(self: *CaveBiomeMapFragment, wx: i32, wy: i32, wz: i32) void {
		self.* = .{
			.pos = main.chunk.ChunkPosition{
				.wx = wx,
				.wy = wy,
				.wz = wz,
				.voxelSize = caveBiomeSize,
			},
		};
	}

	fn privateDeinit(self: *CaveBiomeMapFragment) void {
		memoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *CaveBiomeMapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	const rotationMatrixShift = 30;
	const fac: comptime_int = @intFromFloat(@as(comptime_float, 1 << rotationMatrixShift)/25.0);
	const rotationMatrix = .{
		@Vector(3, i64){20*fac, 0*fac, 15*fac},
		@Vector(3, i64){9*fac, 20*fac, -12*fac},
		@Vector(3, i64){-12*fac, 15*fac, 16*fac},
	}; // divide result by shift to do a proper rotation

	const transposeRotationMatrix = .{
		@Vector(3, i64){20*fac, 9*fac, -12*fac},
		@Vector(3, i64){0*fac, 20*fac, 15*fac},
		@Vector(3, i64){15*fac, -12*fac, 16*fac},
	}; // divide result by shift to do a proper rotation

	pub fn rotate(in: Vec3i) Vec3i {
		return @truncate(@Vector(3, i64){
			vec.dot(rotationMatrix[0], in) >> rotationMatrixShift,
			vec.dot(rotationMatrix[1], in) >> rotationMatrixShift,
			vec.dot(rotationMatrix[2], in) >> rotationMatrixShift,
		});
	}

	pub fn rotateInverse(in: Vec3i) Vec3i {
		return @truncate(@Vector(3, i64){
			vec.dot(transposeRotationMatrix[0], in) >> rotationMatrixShift,
			vec.dot(transposeRotationMatrix[1], in) >> rotationMatrixShift,
			vec.dot(transposeRotationMatrix[2], in) >> rotationMatrixShift,
		});
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
		return relX << 2*(caveBiomeMapShift - caveBiomeShift) | relY << caveBiomeMapShift - caveBiomeShift | relZ;
	}
};

/// A generator for the cave biome map.
pub const CaveBiomeGenerator = struct { // MARK: CaveBiomeGenerator
	init: *const fn(parameters: ZonElement) void,
	generate: *const fn(map: *CaveBiomeMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,

	var generatorRegistry: std.StringHashMapUnmanaged(CaveBiomeGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = CaveBiomeGenerator{
			.init = &Generator.init,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: ZonElement) []CaveBiomeGenerator {
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
pub const InterpolatableCaveBiomeMapView = struct { // MARK: InterpolatableCaveBiomeMapView
	fragments: Array3D(*CaveBiomeMapFragment),
	surfaceFragments: [4]*MapFragment,
	pos: ChunkPosition,
	width: i32,
	allocator: NeverFailingAllocator,

	pub fn init(allocator: main.heap.NeverFailingAllocator, pos: ChunkPosition, width: u31, margin: u31) InterpolatableCaveBiomeMapView {
		const center = Vec3i{
			pos.wx +% width/2,
			pos.wy +% width/2,
			pos.wz +% width/2,
		};
		const rotatedCenter = CaveBiomeMapFragment.rotate(center);
		const marginDiv = 1024;
		const marginMul: comptime_int = @reduce(.Max, @abs(comptime CaveBiomeMapFragment.rotate(.{marginDiv, marginDiv, marginDiv})));
		const caveBiomeFragmentWidth = 1 + (width + margin + CaveBiomeMapFragment.caveBiomeMapSize)*marginMul/marginDiv/CaveBiomeMapFragment.caveBiomeMapSize;
		var result = InterpolatableCaveBiomeMapView{
			.fragments = Array3D(*CaveBiomeMapFragment).init(allocator, caveBiomeFragmentWidth, caveBiomeFragmentWidth, caveBiomeFragmentWidth),
			.surfaceFragments = [_]*MapFragment{
				SurfaceMap.getOrGenerateFragment(center[0] -% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, center[1] -% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, pos.voxelSize),
				SurfaceMap.getOrGenerateFragment(center[0] -% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, center[1] +% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, pos.voxelSize),
				SurfaceMap.getOrGenerateFragment(center[0] +% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, center[1] -% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, pos.voxelSize),
				SurfaceMap.getOrGenerateFragment(center[0] +% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, center[1] +% SurfaceMap.MapFragment.mapSize/2*pos.voxelSize, pos.voxelSize),
			},
			.pos = pos,
			.width = width,
			.allocator = allocator,
		};
		const startX = rotatedCenter[0] -% CaveBiomeMapFragment.caveBiomeMapSize/2*(caveBiomeFragmentWidth - 1);
		const startY = rotatedCenter[1] -% CaveBiomeMapFragment.caveBiomeMapSize/2*(caveBiomeFragmentWidth - 1);
		const startZ = rotatedCenter[2] -% CaveBiomeMapFragment.caveBiomeMapSize/2*(caveBiomeFragmentWidth - 1);
		for(0..caveBiomeFragmentWidth) |x| {
			for(0..caveBiomeFragmentWidth) |y| {
				for(0..caveBiomeFragmentWidth) |z| {
					result.fragments.set(x, y, z, getOrGenerateFragment(
						startX +% CaveBiomeMapFragment.caveBiomeMapSize*@as(i32, @intCast(x)),
						startY +% CaveBiomeMapFragment.caveBiomeMapSize*@as(i32, @intCast(y)),
						startZ +% CaveBiomeMapFragment.caveBiomeMapSize*@as(i32, @intCast(z)),
					));
				}
			}
		}
		return result;
	}

	pub fn deinit(self: InterpolatableCaveBiomeMapView) void {
		self.fragments.deinit(self.allocator);
	}

	fn rotate231(in: Vec3i) Vec3i {
		return @shuffle(i32, in, undefined, Vec3i{1, 2, 0});
	}
	fn rotate312(in: Vec3i) Vec3i {
		return @shuffle(i32, in, undefined, Vec3i{2, 0, 1});
	}
	fn argMaxDistance0(distance: Vec3i) u2 {
		const absDistance = @abs(distance);
		if(absDistance[0] > absDistance[1]) {
			if(absDistance[0] > absDistance[2]) {
				return 0;
			} else {
				return 2;
			}
		} else {
			if(absDistance[1] > absDistance[2]) {
				return 1;
			} else {
				return 2;
			}
		}
	}
	fn argMaxDistance1(distance: Vec3i) u2 {
		const absDistance = @abs(distance);
		if(absDistance[0] >= absDistance[1]) {
			if(absDistance[0] >= absDistance[2]) {
				return 0;
			} else {
				return 2;
			}
		} else {
			if(absDistance[1] >= absDistance[2]) {
				return 1;
			} else {
				return 2;
			}
		}
	}
	fn vectorElement(val: Vec3i, i: u2) i32 {
		return switch(i) {
			0 => val[0],
			1 => val[1],
			2 => val[2],
			else => unreachable,
		};
	}
	fn indexToBool(i: u2) @Vector(3, bool) {
		return switch(i) {
			0 => .{true, false, false},
			1 => .{false, true, false},
			2 => .{false, false, true},
			else => unreachable,
		};
	}

	/// Return either +1 or -1 depending on the sign of the input number.
	fn nonZeroSign(in: Vec3i) Vec3i {
		return @select(i32, in >= Vec3i{0, 0, 0}, Vec3i{1, 1, 1}, Vec3i{-1, -1, -1});
	}

	pub fn bulkInterpolateValue(self: InterpolatableCaveBiomeMapView, comptime field: []const u8, wx: i32, wy: i32, wz: i32, voxelSize: u31, map: Array3D(f32), comptime mode: enum {addToMap}, comptime scale: f32) void {
		var x: u31 = 0;
		while(x < map.width) : (x += 1) {
			var y: u31 = 0;
			while(y < map.height) : (y += 1) {
				var z: u31 = 0;
				while(z < map.depth) : (z += 1) {
					switch(mode) {
						.addToMap => {
							// TODO: Do a tetrahedron voxelization here, so parts of the tetrahedral barycentric coordinates can be precomputed.
							map.ptr(x, y, z).* += scale*interpolateValue(self, wx +% x*voxelSize, wy +% y*voxelSize, wz +% z*voxelSize, field);
						},
					}
				}
			}
		}
	}

	pub noinline fn interpolateValue(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, comptime field: []const u8) f32 {
		const worldPos = CaveBiomeMapFragment.rotate(.{wx, wy, wz});
		const closestGridpoint0 = (worldPos +% @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2))) & @as(Vec3i, @splat(~@as(i32, CaveBiomeMapFragment.caveBiomeMask)));
		const distance0 = worldPos -% closestGridpoint0;
		const coordinate0 = argMaxDistance0(distance0);
		const step0 = @select(i32, indexToBool(coordinate0), @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize)), @as(Vec3i, @splat(0)));
		const secondGridPoint0 = closestGridpoint0 +% step0*nonZeroSign(distance0);

		const closestGridpoint1 = (worldPos & @as(Vec3i, @splat(~@as(i32, CaveBiomeMapFragment.caveBiomeMask)))) +% @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2));
		const distance1 = worldPos -% closestGridpoint1;
		const coordinate1 = argMaxDistance1(distance1);
		const step1 = @select(i32, indexToBool(coordinate1), @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize)), @as(Vec3i, @splat(0)));
		const secondGridPoint1 = closestGridpoint1 +% step1*nonZeroSign(distance1);

		const coordinateFinal = 3 ^ coordinate0 ^ coordinate1;
		const interpFinal = @abs(0.5 + @as(f32, @floatFromInt(vectorElement(distance0, coordinateFinal))))*2/CaveBiomeMapFragment.caveBiomeSize;

		const interp0 = 0.5 + (@abs(@as(f32, @floatFromInt(vectorElement(distance0, coordinate0))))/CaveBiomeMapFragment.caveBiomeSize - 0.5)/(1 - interpFinal);
		const interp1 = 0.5 + (@abs(@as(f32, @floatFromInt(vectorElement(distance1, coordinate1))))/CaveBiomeMapFragment.caveBiomeSize - 0.5)/interpFinal;

		const biome00 = self._getBiome(closestGridpoint0[0], closestGridpoint0[1], closestGridpoint0[2], 0);
		const biome01 = self._getBiome(secondGridPoint0[0], secondGridPoint0[1], secondGridPoint0[2], 0);
		const biome10 = self._getBiome(closestGridpoint1[0], closestGridpoint1[1], closestGridpoint1[2], 1);
		const biome11 = self._getBiome(secondGridPoint1[0], secondGridPoint1[1], secondGridPoint1[2], 1);
		const val0 = @field(biome00, field)*(1 - interp0) + @field(biome01, field)*interp0;
		const val1 = @field(biome10, field)*(1 - interp1) + @field(biome11, field)*interp1;
		return val0*(1 - interpFinal) + val1*interpFinal;
	}

	/// On failure returnHeight contains the lower border of the terrain height.
	fn checkSurfaceBiomeWithHeight(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, returnHeight: *i32) ?*const Biome {
		var index: u8 = 0;
		if(wx -% self.surfaceFragments[0].pos.wx >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 2;
		}
		if(wy -% self.surfaceFragments[0].pos.wy >= MapFragment.mapSize*self.pos.voxelSize) {
			index += 1;
		}
		const height: i32 = self.surfaceFragments[index].getHeight(wx, wy);
		if(wz < height - 32*self.pos.voxelSize or wz >= height + 128 + self.pos.voxelSize) {
			const len = height - 32*self.pos.voxelSize -% wz;
			if(len > 0) returnHeight.* = @min(returnHeight.*, len);
			return null;
		}
		returnHeight.* = height + 128 + self.pos.voxelSize - wz;
		return self.surfaceFragments[index].getBiome(wx, wy);
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
		const indexX: usize = @intCast((wx -% self.fragments.mem[0].pos.wx) >> CaveBiomeMapFragment.caveBiomeMapShift);
		const indexY: usize = @intCast((wy -% self.fragments.mem[0].pos.wy) >> CaveBiomeMapFragment.caveBiomeMapShift);
		const indexZ: usize = @intCast((wz -% self.fragments.mem[0].pos.wz) >> CaveBiomeMapFragment.caveBiomeMapShift);
		const frag = self.fragments.get(indexX, indexY, indexZ);
		const relX: u31 = @intCast(wx - frag.pos.wx);
		const relY: u31 = @intCast(wy - frag.pos.wy);
		const relZ: u31 = @intCast(wz - frag.pos.wz);
		const indexInArray = CaveBiomeMapFragment.getIndex(relX, relY, relZ);
		return frag.biomeMap[indexInArray][map];
	}

	fn getGridPointFromPrerotated(rotatedPos: Vec3i, map: *u1) Vec3i {
		var gridPoint = rotatedPos +% @as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2)) & @as(Vec3i, @splat(~@as(i32, CaveBiomeMapFragment.caveBiomeMask)));

		const distance = rotatedPos -% gridPoint;
		const totalDistance = @reduce(.Add, @abs(distance));
		if(totalDistance > CaveBiomeMapFragment.caveBiomeSize*3/4) {
			// Or with 1 to prevent errors if the value is 0.
			gridPoint +%= std.math.sign(distance)*@as(Vec3i, @splat(CaveBiomeMapFragment.caveBiomeSize/2));
			map.* = 1;
		} else {
			map.* = 0;
		}
		return gridPoint;
	}

	fn getGridPoint(pos: Vec3i, map: *u1) Vec3i {
		const rotatedPos = CaveBiomeMapFragment.rotate(pos);
		return getGridPointFromPrerotated(rotatedPos, map);
	}

	fn getGridPointAndHeight(pos: Vec3i, map: *u1, returnHeight: *i32, voxelSize: u31) Vec3i {
		const preRotatedPos = @Vector(3, i64){
			vec.dot(CaveBiomeMapFragment.rotationMatrix[0], pos),
			vec.dot(CaveBiomeMapFragment.rotationMatrix[1], pos),
			vec.dot(CaveBiomeMapFragment.rotationMatrix[2], pos),
		};
		var startMap: u1 = undefined;
		const gridPoint = getGridPointFromPrerotated(@truncate(preRotatedPos >> @splat(CaveBiomeMapFragment.rotationMatrixShift)), &startMap);

		var start: i32 = 0;
		var end = @min(returnHeight.*, @as(comptime_int, @intFromFloat(@ceil(CaveBiomeMapFragment.caveBiomeSize*@sqrt(5.0)/2.0)))) & ~@as(i32, voxelSize - 1);
		{
			var otherMap: u1 = undefined;
			const nextGridPoint = getGridPointFromPrerotated(@truncate(preRotatedPos +% CaveBiomeMapFragment.transposeRotationMatrix[2]*@as(Vec3i, @splat(end)) >> @splat(CaveBiomeMapFragment.rotationMatrixShift)), &otherMap);
			if(@reduce(.And, nextGridPoint == gridPoint) and otherMap == startMap) start = end;
		}
		while(start + voxelSize < end) {
			const mid = start +% @divTrunc(end -% start, 2) & ~@as(i32, voxelSize - 1);
			var otherMap: u1 = undefined;
			const nextGridPoint = getGridPointFromPrerotated(@truncate(preRotatedPos +% CaveBiomeMapFragment.transposeRotationMatrix[2]*@as(Vec3i, @splat(mid)) >> @splat(CaveBiomeMapFragment.rotationMatrixShift)), &otherMap);
			if(@reduce(.Or, nextGridPoint != gridPoint) or otherMap != startMap) {
				end = mid;
			} else {
				start = mid;
			}
		}
		returnHeight.* = end;
		map.* = startMap;
		return gridPoint;
	}

	/// Useful when the rough biome location is enough, for example for music.
	pub noinline fn getRoughBiome(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, comptime getSeed: bool, seed: *u64, comptime _checkSurfaceBiome: bool) *const Biome {
		if(_checkSurfaceBiome) {
			if(self.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
				return surfaceBiome;
			}
		}
		var map: u1 = undefined;
		const gridPoint = getGridPoint(.{wx, wy, wz}, &map);

		if(getSeed) {
			// A good old "I don't know what I'm doing" hash (TODO: Use some standard hash maybe):
			seed.* = @as(u64, @bitCast(@as(i64, gridPoint[0]) << 48 ^ @as(i64, gridPoint[1]) << 23 ^ @as(i64, gridPoint[2]) << 11 ^ @as(i64, gridPoint[0]) >> 5 ^ @as(i64, gridPoint[1]) << 3 ^ @as(i64, gridPoint[2]) ^ @as(i64, map)*5427642781)) ^ main.server.world.?.seed;
		}

		return self._getBiome(gridPoint[0], gridPoint[1], gridPoint[2], map);
	}

	/// returnHeight should contain an upper estimate for the biome size.
	fn getRoughBiomeAndHeight(self: InterpolatableCaveBiomeMapView, wx: i32, wy: i32, wz: i32, comptime getSeed: bool, seed: *u64, comptime _checkSurfaceBiome: bool, returnHeight: *i32) *const Biome {
		if(_checkSurfaceBiome) {
			if(self.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
				return surfaceBiome;
			}
		}
		var map: u1 = undefined;
		const gridPoint = getGridPointAndHeight(.{wx, wy, wz}, &map, returnHeight, self.pos.voxelSize);

		if(getSeed) {
			// A good old "I don't know what I'm doing" hash (TODO: Use some standard hash maybe):
			seed.* = @as(u64, @bitCast(@as(i64, gridPoint[0]) << 48 ^ @as(i64, gridPoint[1]) << 23 ^ @as(i64, gridPoint[2]) << 11 ^ @as(i64, gridPoint[0]) >> 5 ^ @as(i64, gridPoint[1]) << 3 ^ @as(i64, gridPoint[2]) ^ @as(i64, map)*5427642781)) ^ main.server.world.?.seed;
		}

		return self._getBiome(gridPoint[0], gridPoint[1], gridPoint[2], map);
	}
};

pub const CaveBiomeMapView = struct { // MARK: CaveBiomeMapView
	const CachedFractalNoise = terrain.noise.CachedFractalNoise;

	super: InterpolatableCaveBiomeMapView,
	noise: ?CachedFractalNoise = null,

	pub fn init(allocator: NeverFailingAllocator, pos: ChunkPosition, width: u31, margin: u31) CaveBiomeMapView {
		var self = CaveBiomeMapView{
			.super = InterpolatableCaveBiomeMapView.init(allocator, pos, width, margin),
		};
		if(pos.voxelSize < 8) {
			const startX = (pos.wx -% margin) & ~@as(i32, 63);
			const startY = (pos.wy -% margin) & ~@as(i32, 63);
			self.noise = CachedFractalNoise.init(startX, startY, pos.voxelSize, width + 64 + 2*margin, main.server.world.?.seed ^ 0x764923684396, 64);
		}
		return self;
	}

	pub fn deinit(self: CaveBiomeMapView) void {
		self.super.deinit();
		if(self.noise) |noise| {
			noise.deinit();
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
		const wx = relX +% self.super.pos.wx;
		const wy = relY +% self.super.pos.wy;
		var wz = relZ +% self.super.pos.wz;
		if(self.super.checkSurfaceBiome(wx, wy, wz)) |surfaceBiome| {
			return surfaceBiome;
		}
		if(self.noise) |noise| {
			const value = noise.getValue(wx, wy);
			wz +%= @intFromFloat(value);
		}

		return self.super.getRoughBiome(wx, wy, wz, getSeed, seed, false);
	}

	/// Also returns a seed that is unique for the corresponding biome position.
	/// returnHeight should contain an upper estimate for the biome size.
	pub noinline fn getBiomeColumnAndSeed(self: CaveBiomeMapView, relX: i32, relY: i32, relZ: i32, comptime getSeed: bool, seed: *u64, returnHeight: *i32) *const Biome {
		std.debug.assert(relX >= -32 and relX < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relY >= -32 and relY < self.super.width + 32); // coordinate out of bounds
		std.debug.assert(relZ >= -32 and relZ < self.super.width + 32); // coordinate out of bounds
		const wx = relX +% self.super.pos.wx;
		const wy = relY +% self.super.pos.wy;
		var wz = relZ +% self.super.pos.wz;
		if(self.super.checkSurfaceBiomeWithHeight(wx, wy, wz, returnHeight)) |surfaceBiome| {
			return surfaceBiome;
		}
		if(self.noise) |noise| {
			const value = noise.getValue(wx, wy);
			wz +%= @intFromFloat(value);
		}

		return self.super.getRoughBiomeAndHeight(wx, wy, wz, getSeed, seed, false, returnHeight);
	}
};

// MARK: cache
const cacheSize = 1 << 8; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // 128 MiB
var cache: Cache(CaveBiomeMapFragment, cacheSize, associativity, CaveBiomeMapFragment.deferredDeinit) = .{};

var profile: TerrainGenerationProfile = undefined;

var memoryPool: main.heap.MemoryPool(CaveBiomeMapFragment) = undefined;

pub fn globalInit() void {
	const list = @import("cavebiomegen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		CaveBiomeGenerator.registerGenerator(@field(list, decl.name));
	}
	memoryPool = .init(main.globalAllocator);
}

pub fn globalDeinit() void {
	CaveBiomeGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
	memoryPool.deinit();
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

fn cacheInit(pos: ChunkPosition) *CaveBiomeMapFragment {
	const mapFragment = memoryPool.create();
	mapFragment.init(pos.wx, pos.wy, pos.wz);
	for(profile.caveBiomeGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	return mapFragment;
}

fn getOrGenerateFragment(_wx: i32, _wy: i32, _wz: i32) *CaveBiomeMapFragment {
	const wx = _wx & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wy = _wy & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const wz = _wz & ~@as(i32, CaveBiomeMapFragment.caveBiomeMapMask);
	const compare = ChunkPosition{
		.wx = wx,
		.wy = wy,
		.wz = wz,
		.voxelSize = CaveBiomeMapFragment.caveBiomeSize,
	};
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}
