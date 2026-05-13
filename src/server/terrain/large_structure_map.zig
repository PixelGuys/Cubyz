const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const ServerChunk = main.chunk.ServerChunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const terrain = @import("terrain.zig");
const GeneratorState = terrain.GeneratorState;
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;
const StructureInternal = terrain.StructureMap.StructureInternal;
const Structure = terrain.StructureMap.Structure;
const SdfInstance = terrain.sdf.SdfInstance;

pub const large_structure_map_generators = @import("large_structure_map_generators/_list.zig");

pub const LargeStructureMapFragment = struct { // MARK: LargeStructureMapFragment
	pub const size = terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeMapSize;
	pub const sizeMask = size - 1;
	pub const chunkShift = 7;
	pub const chunkSize = 1 << chunkShift;
	pub const chunkMask = chunkSize - 1;
	pub const chunkedSize = size/chunkSize;

	structureData: [chunkedSize*chunkedSize*chunkedSize][]StructureInternal = undefined,
	sdfData: [chunkedSize*chunkedSize*chunkedSize][]SdfInstance = undefined,

	pos: Vec3i,
	arena: main.heap.NeverFailingArenaAllocator,
	allocator: main.heap.NeverFailingAllocator,

	tempData: struct {
		const Entry = struct {main.ListUnmanaged(Structure), main.ListUnmanaged(SdfInstance)};
		lists: *[chunkedSize*chunkedSize*chunkedSize]Entry,
		allocator: NeverFailingAllocator,
	},

	pub fn init(self: *LargeStructureMapFragment, tempAllocator: NeverFailingAllocator, pos: Vec3i) void {
		self.* = .{
			.pos = pos,
			.arena = .init(main.globalAllocator),
			.allocator = self.arena.allocator(),
			.tempData = .{
				.lists = tempAllocator.create([chunkedSize*chunkedSize*chunkedSize]@TypeOf(self.tempData).Entry),
				.allocator = tempAllocator,
			},
		};
		@memset(self.tempData.lists, .{.{}, .{}});
	}

	fn privateDeinit(self: *LargeStructureMapFragment) void {
		self.arena.deinit();
		memoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *LargeStructureMapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.meta.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	fn finishGeneration(self: *LargeStructureMapFragment) void {
		for (0..self.structureData.len) |i| {
			std.sort.insertion(Structure, self.tempData.lists[i][0].items, {}, Structure.lessThan);
			self.structureData[i] = self.allocator.alloc(StructureInternal, self.tempData.lists[i][0].items.len);
			for (0..self.tempData.lists[i][0].items.len) |j| {
				self.structureData[i][j] = self.tempData.lists[i][0].items[j].internal;
			}

			self.sdfData[i] = self.allocator.alloc(SdfInstance, self.tempData.lists[i][1].items.len);
			for (0..self.tempData.lists[i][1].items.len) |j| {
				self.sdfData[i][j] = self.tempData.lists[i][1].items[j];
			}

			self.tempData.lists[i][0].deinit(self.tempData.allocator);
			self.tempData.lists[i][1].deinit(self.tempData.allocator);
			self.tempData.lists[i] = undefined;
		}
		self.tempData.allocator.destroy(self.tempData.lists);
		self.tempData = undefined;
		self.arena.shrinkAndFree();
	}

	fn getIndex(pos: Vec3i) usize {
		std.debug.assert(@reduce(.And, pos >= @as(Vec3i, @splat(0))) and @reduce(.And, pos < @as(Vec3i, @splat(size)))); // Coordinates out of range.
		return @intCast(((pos[0] >> chunkShift)*chunkedSize + (pos[1] >> chunkShift))*chunkedSize + (pos[2] >> chunkShift));
	}

	pub fn generateStructuresInChunk(self: *const LargeStructureMapFragment, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView) void {
		const index = self.getIndex(chunk.super.pos.wx - self.pos.wx, chunk.super.pos.wy - self.pos.wy, chunk.super.pos.wz - self.pos.wz);
		for (self.data[index]) |structure| {
			structure.generate(chunk, caveMap, biomeMap);
		}
	}

	pub fn getSdfs(self: *const LargeStructureMapFragment, pos: Vec3i) []const SdfInstance {
		const index = getIndex(pos -% self.pos);
		return self.sdfData[index];
	}

	pub fn addStructure(self: *LargeStructureMapFragment, structure: Structure, min: Vec3i, max: Vec3i) void {
		var x = min[0] & ~@as(i32, chunkShift);
		while (x < max[0]) : (x += chunkSize) {
			if (x < 0 or x >= size) continue;
			var y = min[1] & ~@as(i32, chunkMask);
			while (y < max[1]) : (y += chunkSize) {
				if (y < 0 or y >= size) continue;
				var z = min[2] & ~@as(i32, chunkMask);
				while (z < max[2]) : (z += chunkSize) {
					if (z < 0 or z >= size) continue;
					self.tempData.lists[self.getIndex(x, y, z)].append(self.tempData.allocator, structure);
				}
			}
		}
	}

	pub fn addSdf(self: *LargeStructureMapFragment, sdf: SdfInstance) void {
		const min = sdf.minBounds - @as(Vec3i, @splat(terrain.sdf.margin));
		const max = sdf.maxBounds + @as(Vec3i, @splat(terrain.sdf.margin));
		var x = min[0] & ~@as(i32, chunkMask);
		while (x < max[0]) : (x += chunkSize) {
			if (x < 0 or x >= size) continue;
			var y = min[1] & ~@as(i32, chunkMask);
			while (y < max[1]) : (y += chunkSize) {
				if (y < 0 or y >= size) continue;
				var z = min[2] & ~@as(i32, chunkMask);
				while (z < max[2]) : (z += chunkSize) {
					if (z < 0 or z >= size) continue;
					self.tempData.lists[getIndex(.{x, y, z})][1].append(self.tempData.allocator, sdf);
				}
			}
		}
	}
};

/// A generator for the structure map.
pub const LargeStructureMapGenerator = struct { // MARK: LargeStructureMapGenerator
	init: *const fn (parameters: ZonElement) void,
	generate: *const fn (map: *LargeStructureMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,
	defaultState: GeneratorState,

	const generatorRegistry: std.StaticStringMap(LargeStructureMapGenerator) = .initComptime(blk: {
		const decls = @typeInfo(large_structure_map_generators).@"struct".decls;
		var generators: [decls.len]struct { []const u8, LargeStructureMapGenerator } = undefined;
		for (0..decls.len) |i| {
			const Generator = @field(large_structure_map_generators, decls[i].name);
			generators[i] = .{Generator.id, .{
				.init = &Generator.init,
				.generate = &Generator.generate,
				.priority = Generator.priority,
				.generatorSeed = Generator.generatorSeed,
				.defaultState = Generator.defaultState,
			}};
		}
		break :blk generators;
	});

	pub fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: ZonElement) []LargeStructureMapGenerator {
		var list: main.ListUnmanaged(LargeStructureMapGenerator) = .initCapacity(allocator, generatorRegistry.values().len);
		for (generatorRegistry.keys(), generatorRegistry.values()) |id, generator| {
			const generatorSettings = settings.getChild(id);
			if (generatorSettings.get(GeneratorState, "state", generator.defaultState) == .disabled) continue;
			generator.init(generatorSettings);
			list.appendAssumeCapacity(generator);
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: LargeStructureMapGenerator, rhs: LargeStructureMapGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(LargeStructureMapGenerator, list.items, {}, lessThan);
		return list.toOwnedSlice(allocator);
	}
};

const cacheSize = 1 << 10; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: Cache(LargeStructureMapFragment, cacheSize, associativity, LargeStructureMapFragment.deferredDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

var memoryPool: main.heap.MemoryPool(LargeStructureMapFragment) = .init(main.globalArena);

const Compare = struct {
	pos: Vec3i,

	pub fn hashCode(self: Compare) u32 {
		const shift: u5 = @truncate(@min(@ctz(self.pos[0]), @ctz(self.pos[1]), @ctz(self.pos[2])));
		return ((@as(u32, @bitCast(self.pos[0])) >> shift)*%31 +% (@as(u32, @bitCast(self.pos[1])) >> shift))*%31 +% (@as(u32, @bitCast(self.pos[2])) >> shift); // TODO: Can I use one of zigs standard hash functions?
	}

	pub fn equals(self: Compare, other: ?*LargeStructureMapFragment) bool {
		if (other == null) return false;
		return @reduce(.And, self.pos == other.?.pos);
	}
};

fn cacheInit(pos: Compare) *LargeStructureMapFragment {
	const mapFragment = memoryPool.create();
	mapFragment.init(main.stackAllocator, pos.pos);
	for (profile.largeStructureMapGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	mapFragment.finishGeneration();
	return mapFragment;
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

pub fn getOrGenerateFragment(pos: Vec3i) *LargeStructureMapFragment {
	const compare: Compare = .{.pos = pos & @as(Vec3i, @splat(~@as(i32, LargeStructureMapFragment.sizeMask)))};
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}
