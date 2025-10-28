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
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;

const StructureInternal = struct {
	generateFn: *const fn(self: *const anyopaque, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView) void,
	data: *const anyopaque,

	pub fn generate(self: StructureInternal, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView) void {
		self.generateFn(self.data, chunk, caveMap, biomeMap);
	}
};

pub const Structure = struct {
	internal: StructureInternal,
	priority: f32,

	fn lessThan(_: void, lhs: Structure, rhs: Structure) bool {
		return lhs.priority < rhs.priority;
	}
};

pub const StructureMapFragment = struct {
	pub const size = 1 << 7;
	pub const sizeMask = size - 1;
	pub const chunkedSize = size >> main.chunk.chunkShift;

	data: [chunkedSize*chunkedSize*chunkedSize][]StructureInternal = undefined,

	pos: ChunkPosition,
	voxelShift: u5,
	arena: main.heap.NeverFailingArenaAllocator,
	allocator: main.heap.NeverFailingAllocator,

	tempData: struct {
		lists: *[chunkedSize*chunkedSize*chunkedSize]main.ListUnmanaged(Structure),
		allocator: NeverFailingAllocator,
	},

	pub fn init(self: *StructureMapFragment, tempAllocator: NeverFailingAllocator, wx: i32, wy: i32, wz: i32, voxelSize: u31) void {
		self.* = .{
			.pos = .{
				.wx = wx,
				.wy = wy,
				.wz = wz,
				.voxelSize = voxelSize,
			},
			.voxelShift = @ctz(voxelSize),
			.arena = .init(main.globalAllocator),
			.allocator = self.arena.allocator(),
			.tempData = .{
				.lists = tempAllocator.create([chunkedSize*chunkedSize*chunkedSize]main.ListUnmanaged(Structure)),
				.allocator = tempAllocator,
			},
		};
		@memset(self.tempData.lists, .{});
	}

	fn privateDeinit(self: *StructureMapFragment) void {
		self.arena.deinit();
		memoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *StructureMapFragment) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	fn finishGeneration(self: *StructureMapFragment) void {
		for(0..self.data.len) |i| {
			std.sort.insertion(Structure, self.tempData.lists[i].items, {}, Structure.lessThan);
			self.data[i] = self.allocator.alloc(StructureInternal, self.tempData.lists[i].items.len);
			for(0..self.tempData.lists[i].items.len) |j| {
				self.data[i][j] = self.tempData.lists[i].items[j].internal;
			}
			self.tempData.lists[i].deinit(self.tempData.allocator);
			self.tempData.lists[i] = undefined;
		}
		self.tempData.allocator.destroy(self.tempData.lists);
		self.tempData = undefined;
		self.arena.shrinkAndFree();
	}

	fn getIndex(self: *const StructureMapFragment, x: i32, y: i32, z: i32) usize {
		std.debug.assert(x >= 0 and x < size*self.pos.voxelSize and y >= 0 and y < size*self.pos.voxelSize and z >= 0 and z < size*self.pos.voxelSize); // Coordinates out of range.
		return @intCast(((x >> main.chunk.chunkShift + self.voxelShift)*chunkedSize + (y >> main.chunk.chunkShift + self.voxelShift))*chunkedSize + (z >> main.chunk.chunkShift + self.voxelShift));
	}

	pub fn generateStructuresInChunk(self: *const StructureMapFragment, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView) void {
		const index = self.getIndex(chunk.super.pos.wx - self.pos.wx, chunk.super.pos.wy - self.pos.wy, chunk.super.pos.wz - self.pos.wz);
		for(self.data[index]) |structure| {
			structure.generate(chunk, caveMap, biomeMap);
		}
	}

	pub fn addStructure(self: *StructureMapFragment, structure: Structure, min: Vec3i, max: Vec3i) void {
		var x = min[0] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize - 1);
		while(x < max[0]) : (x += main.chunk.chunkSize << self.voxelShift) {
			if(x < 0 or x >= size*self.pos.voxelSize) continue;
			var y = min[1] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize - 1);
			while(y < max[1]) : (y += main.chunk.chunkSize << self.voxelShift) {
				if(y < 0 or y >= size*self.pos.voxelSize) continue;
				var z = min[2] & ~@as(i32, main.chunk.chunkMask << self.voxelShift | self.pos.voxelSize - 1);
				while(z < max[2]) : (z += main.chunk.chunkSize << self.voxelShift) {
					if(z < 0 or z >= size*self.pos.voxelSize) continue;
					self.tempData.lists[self.getIndex(x, y, z)].append(self.tempData.allocator, structure);
				}
			}
		}
	}
};

/// A generator for the cave map.
pub const StructureMapGenerator = struct {
	init: *const fn(parameters: ZonElement) void,
	generate: *const fn(map: *StructureMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,

	var generatorRegistry: std.StringHashMapUnmanaged(StructureMapGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = StructureMapGenerator{
			.init = &Generator.init,
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
var cache: Cache(StructureMapFragment, cacheSize, associativity, StructureMapFragment.deferredDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

var memoryPool: main.heap.MemoryPool(StructureMapFragment) = undefined;

fn cacheInit(pos: ChunkPosition) *StructureMapFragment {
	const mapFragment = memoryPool.create();
	mapFragment.init(main.stackAllocator, pos.wx, pos.wy, pos.wz, pos.voxelSize);
	for(profile.structureMapGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	mapFragment.finishGeneration();
	return mapFragment;
}

pub fn globalInit() void {
	const list = @import("structuremapgen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		StructureMapGenerator.registerGenerator(@field(list, decl.name));
	}
	memoryPool = .init(main.globalAllocator);
}

pub fn globalDeinit() void {
	StructureMapGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
	memoryPool.deinit();
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

pub fn getOrGenerateFragment(wx: i32, wy: i32, wz: i32, voxelSize: u31) *StructureMapFragment {
	const compare = ChunkPosition{
		.wx = wx & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize - 1),
		.wy = wy & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize - 1),
		.wz = wz & ~@as(i32, StructureMapFragment.sizeMask*voxelSize | voxelSize - 1),
		.voxelSize = voxelSize,
	};
	const result = cache.findOrCreate(compare, cacheInit, null);
	return result;
}
