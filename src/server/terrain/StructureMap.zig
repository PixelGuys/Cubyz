const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const ServerChunk = main.chunk.ServerChunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;

pub const Structure = struct {
	generateFn: *const fn(self: *const anyopaque, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView) void,
	data: *const anyopaque,

	pub fn generate(self: Structure, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView) void {
		self.generateFn(self.data, chunk, caveMap);
	}
};

pub const StructureMapFragment = struct {
	pub const size = 1 << 7;
	pub const sizeMask = size - 1;
	pub const chunkedSize = size >> main.chunk.chunkShift;

	data: [chunkedSize*chunkedSize*chunkedSize]main.ListUnmanaged(Structure) = undefined,

	pos: ChunkPosition,
	voxelShift: u5,
	refCount: Atomic(u16) = .init(0),
	arena: main.utils.NeverFailingArenaAllocator,
	allocator: main.utils.NeverFailingAllocator,


	pub fn init(self: *StructureMapFragment, wx: i32, wy: i32, wz: i32, voxelSize: u31) void {
		self.* = .{
			.pos = .{
				.wx = wx, .wy = wy, .wz = wz,
				.voxelSize = voxelSize,
			},
			.voxelShift = @ctz(voxelSize),
			.arena = .init(main.globalAllocator),
			.allocator = self.arena.allocator(),
		};
		@memset(&self.data, .{});
	}

	pub fn deinit(self: *StructureMapFragment) void {
		self.arena.deinit();
		main.globalAllocator.destroy(self);
	}

	fn getIndex(self: *const StructureMapFragment, x: i32, y: i32, z: i32) usize {
		std.debug.assert(x >= 0 and x < size*self.pos.voxelSize and y >= 0 and y < size*self.pos.voxelSize and z >= 0 and z < size*self.pos.voxelSize); // Coordinates out of range.
		return @intCast(((x >> main.chunk.chunkShift+self.voxelShift)*chunkedSize + (y >> main.chunk.chunkShift+self.voxelShift))*chunkedSize + (z >> main.chunk.chunkShift+self.voxelShift));
	}

	pub fn increaseRefCount(self: *StructureMapFragment) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *StructureMapFragment) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			self.deinit();
		}
	}

	pub fn generateStructuresInChunk(self: *const StructureMapFragment, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView) void {
		const index = self.getIndex(chunk.super.pos.wx - self.pos.wx, chunk.super.pos.wy - self.pos.wy, chunk.super.pos.wz - self.pos.wz);
		for(self.data[index].items) |structure| {
			structure.generate(chunk, caveMap);
		}
	}

	pub fn addStructure(self: *StructureMapFragment, structure: Structure, min: Vec3i, max: Vec3i) void {
		var x = min[0] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize-1);
		while(x < max[0]) : (x += main.chunk.chunkSize << self.voxelShift) {
			if(x < 0 or x >= size*self.pos.voxelSize) continue;
			var y = min[1] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize-1);
			while(y < max[1]) : (y += main.chunk.chunkSize << self.voxelShift) {
				if(y < 0 or y >= size*self.pos.voxelSize) continue;
				var z = min[2] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize-1);
				while(z < max[2]) : (z += main.chunk.chunkSize << self.voxelShift) {
					if(z < 0 or z >= size*self.pos.voxelSize) continue;
					self.data[self.getIndex(x, y, z)].append(self.allocator, structure);
				}
			}
		}
	}
};

/// A generator for the cave map.
pub const StructureMapGenerator = struct {
	init: *const fn(parameters: ZonElement) void,
	deinit: *const fn() void,
	generate: *const fn(map: *StructureMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(StructureMapGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = StructureMapGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: ZonElement) []StructureMapGenerator {
		const list = allocator.alloc(StructureMapGenerator, generatorRegistry.size);
		var iterator = generatorRegistry.iterator();
		var i: usize = 0;
		while(iterator.next()) |generator| {
			list[i] = generator.value_ptr.*;
			list[i].init(settings.getChild(generator.key_ptr.*));
			i += 1;
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: StructureMapGenerator, rhs: StructureMapGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(StructureMapGenerator, list, {}, lessThan);
		return list;
	}
};

const cacheSize = 1 << 10; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8;
var cache: Cache(StructureMapFragment, cacheSize, associativity, StructureMapFragment.decreaseRefCount) = .{};
var profile: TerrainGenerationProfile = undefined;

fn cacheInit(pos: ChunkPosition) *StructureMapFragment {
	const mapFragment = main.globalAllocator.create(StructureMapFragment);
	mapFragment.init(pos.wx, pos.wy, pos.wz, pos.voxelSize);
	for(profile.structureMapGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	_ = @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .monotonic);
	return mapFragment;
}

pub fn initGenerators() void {
	const list = @import("structuremapgen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		StructureMapGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	StructureMapGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

pub fn getOrGenerateFragmentAndIncreaseRefCount(wx: i32, wy: i32, wz: i32, voxelSize: u31) *StructureMapFragment {
	const compare = ChunkPosition {
		.wx = wx & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize-1),
		.wy = wy & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize-1),
		.wz = wz & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize-1),
		.voxelSize = voxelSize,
	};
	const result = cache.findOrCreate(compare, cacheInit, StructureMapFragment.increaseRefCount);
	return result;
}