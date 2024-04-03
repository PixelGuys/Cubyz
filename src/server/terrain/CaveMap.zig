const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const terrain = @import("terrain.zig");
const TerrainGenerationProfile = terrain.TerrainGenerationProfile;

/// Cave data represented in a 1-Bit per block format, where 0 means empty and 1 means not empty.
pub const CaveMapFragment = struct {
	pub const width = 1 << 6;
	pub const widthMask = width - 1;
	pub const height = 64; // Size of u64
	pub const heightMask = height - 1;

	data: [width*width]u64 = undefined,
	pos: ChunkPosition,
	voxelShift: u5,
	refCount: Atomic(u16) = Atomic(u16).init(0),


	pub fn init(self: *CaveMapFragment, wx: i32, wy: i32, wz: i32, voxelSize: u31) void {
		self.* = .{
			.pos = .{
				.wx = wx, .wy = wy, .wz = wz,
				.voxelSize = voxelSize,
			},
			.voxelShift = @ctz(voxelSize),
		};
		@memset(&self.data, std.math.maxInt(u64));
	}

	fn getIndex(x: i32, y: i32) usize {
		std.debug.assert(x >= 0 and x < width and y >= 0 and y < width); // Coordinates out of range.
		return @intCast(x*width + y);
	}

	/// for example 3,11 would create the mask ...111_11111100_00000011
	/// start inclusive
	/// end exclusive
	fn getMask(start: i32, end: i32) u64 {
		const maskLower = if(start <= 0) (
			0
		) else if(start >= 64) (
			std.math.maxInt(u64)
		) else (
			@as(u64, std.math.maxInt(u64)) >> @intCast(64 - start)
		);
		const maskUpper = if(end <= 0) (
			std.math.maxInt(u64)
		) else if(end >= 64) (
			0
		) else (
			@as(u64, std.math.maxInt(u64)) << @intCast(end)
		);
		return maskLower | maskUpper;
	}

	pub fn addRange(self: *CaveMapFragment, _relX: i32, _relY: i32, _start: i32, _end: i32) void {
		const relX = _relX >> self.voxelShift;
		const relY = _relY >> self.voxelShift;
		const start = _start >> self.voxelShift;
		const end = _end >> self.voxelShift;
		self.data[getIndex(relX, relY)] |= ~getMask(start, end);
	}

	pub fn removeRange(self: *CaveMapFragment, _relX: i32, _relY: i32, _start: i32, _end: i32) void {
		const relX = _relX >> self.voxelShift;
		const relY = _relY >> self.voxelShift;
		const start = _start >> self.voxelShift;
		const end = _end >> self.voxelShift;
		self.data[getIndex(relX, relY)] &= getMask(start, end);
	}

	pub fn getColumnData(self: *CaveMapFragment, _relX: i32, _relY: i32) u64 {
		const relX = _relX >> self.voxelShift;
		const relY = _relY >> self.voxelShift;
		return (&self.data)[getIndex(relX, relY)]; // TODO: #13938
	}
};

/// A generator for the cave map.
pub const CaveGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generate: *const fn(map: *CaveMapFragment, seed: u64) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(CaveGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		const self = CaveGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		generatorRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	pub fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: JsonElement) []CaveGenerator {
		const list = allocator.alloc(CaveGenerator, generatorRegistry.size);
		var iterator = generatorRegistry.iterator();
		var i: usize = 0;
		while(iterator.next()) |generator| {
			list[i] = generator.value_ptr.*;
			list[i].init(settings.getChild(generator.key_ptr.*));
			i += 1;
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: CaveGenerator, rhs: CaveGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(CaveGenerator, list, {}, lessThan);
		return list;
	}
};

pub const CaveMapView = struct {
	reference: *Chunk,
	fragments: [8]*CaveMapFragment,

	pub fn init(chunk: *Chunk) CaveMapView {
		return CaveMapView {
			.reference = chunk,
			.fragments = [_]*CaveMapFragment {
				getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
			},
		};
	}

	pub fn deinit(self: CaveMapView) void {
		for(self.fragments) |mapFragment| {
			mapFragmentDeinit(mapFragment);
		}
	}

	pub fn isSolid(self: CaveMapView, relX: i32, relY: i32, relZ: i32) bool {
		const wx = relX +% self.reference.pos.wx;
		const wy = relY +% self.reference.pos.wy;
		const wz = relZ +% self.reference.pos.wz;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wy - self.fragments[0].pos.wy >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 2;
		}
		if(wz - self.fragments[0].pos.wz >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 1;
		}
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelY = wy - self.fragments[index].pos.wy;
		const fragmentRelZ = @divFloor(wz - self.fragments[index].pos.wz, self.reference.pos.voxelSize);
		const height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelY);
		return (height & @as(u64, 1)<<@intCast(fragmentRelZ)) != 0;
	}

	pub fn getHeightData(self: CaveMapView, relX: i32, relY: i32) u32 {
		const wx = relX + self.reference.pos.wx;
		const wy = relY + self.reference.pos.wy;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wy - self.fragments[0].pos.wy >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 2;
		}
		var deltaZ = self.reference.pos.wz - self.fragments[0].pos.wz;
		if(deltaZ >= CaveMapFragment.height*self.reference.pos.voxelSize) {
			index += 1;
			deltaZ -= CaveMapFragment.height*self.reference.pos.voxelSize;
		}
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelY = wy - self.fragments[index].pos.wy;
		const height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelY);
		if(deltaZ == 0) {
			return @truncate(height);
		} else {
			return @intCast(height >> 32);
		}
	}

	pub fn findTerrainChangeAbove(self: CaveMapView, relX: i32, relY: i32, z: i32) i32 {
		const wx = relX + self.reference.pos.wx;
		const wy = relY + self.reference.pos.wy;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wy - self.fragments[0].pos.wy >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 2;
		}
		var relativeZ = @divFloor(z + self.reference.pos.wz - self.fragments[0].pos.wz, self.reference.pos.voxelSize);
		std.debug.assert(relativeZ >= 0 and relativeZ < 2*CaveMapFragment.height);
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelY = wy - self.fragments[index].pos.wy;
		var height: u64 = 0;
		var result: i32 = relativeZ;
		if(relativeZ < CaveMapFragment.height) {
			// Check the lower part first.
			height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelY) >> @intCast(relativeZ);
			const startFilled = (height & 1) != 0;
			if(relativeZ != 0) {
				height |= self.fragments[index+1].getColumnData(fragmentRelX, fragmentRelY) << @intCast(64 - relativeZ);
			}
			if(startFilled) {
				height = ~height;
			}
		} else {
			// Check only the upper part:
			result = @max(CaveMapFragment.height, result);
			relativeZ -= CaveMapFragment.height;
			height = self.fragments[index+1].getColumnData(fragmentRelX, fragmentRelY);
			height >>= @intCast(relativeZ);
			const startFilled = (height & 1) != 0;
			if(startFilled) {
				height = ~height;
			}
		}
		result += @ctz(height);
		return result*self.reference.pos.voxelSize + self.fragments[0].pos.wz - self.reference.pos.wz;
	}

	pub fn findTerrainChangeBelow(self: CaveMapView, relX: i32, relY: i32, z: i32) i32 {
		const wx = relX + self.reference.pos.wx;
		const wy = relY + self.reference.pos.wy;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wy - self.fragments[0].pos.wy >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 2;
		}
		var relativeZ = @divFloor(z + self.reference.pos.wz - self.fragments[0].pos.wz, self.reference.pos.voxelSize);
		std.debug.assert(relativeZ >= 0 and relativeZ < 2*CaveMapFragment.height);
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelY = wy - self.fragments[index].pos.wy;
		var height: u64 = 0;
		var result: i32 = relativeZ;
		if(relativeZ >= CaveMapFragment.height) {
			relativeZ -= CaveMapFragment.height;
			// Check the upper part first.
			height = self.fragments[index+1].getColumnData(fragmentRelX, fragmentRelY) << (63 - @as(u6, @intCast(relativeZ)));
			const startFilled = height & 1<<63 != 0;
			if(relativeZ != CaveMapFragment.height - 1) {
				height |= self.fragments[index].getColumnData(fragmentRelX, fragmentRelY) >> @as(u6, @intCast(relativeZ + 1));
			}
			if(startFilled) {
				height = ~height;
			}
		} else {
			// Check only the lower part:
			result = @min(CaveMapFragment.height - 1, result);
			height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelY);
			height <<= @intCast(63 - relativeZ);
			const startFilled = (height & 1<<63) != 0;
			if(startFilled) {
				height = ~height;
			}
		}
		result -= @clz(height);
		return result*self.reference.pos.voxelSize + self.fragments[0].pos.wz - self.reference.pos.wz;
	}
};

const cacheSize = 1 << 9; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // 512 MiB Cache size
var cache: Cache(CaveMapFragment, cacheSize, associativity, mapFragmentDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

fn mapFragmentDeinit(mapFragment: *CaveMapFragment) void {
	if(@atomicRmw(u16, &mapFragment.refCount.raw, .Sub, 1, .monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: ChunkPosition) *CaveMapFragment {
	const mapFragment = main.globalAllocator.create(CaveMapFragment);
	mapFragment.init(pos.wx, pos.wy, pos.wz, pos.voxelSize);
	for(profile.caveGenerators) |generator| {
		generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	_ = @atomicRmw(u16, &mapFragment.refCount.raw, .Add, 1, .monotonic);
	return mapFragment;
}

pub fn initGenerators() void {
	const list = @import("cavegen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		CaveGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	CaveGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

fn getOrGenerateFragment(wx: i32, wy: i32, wz: i32, voxelSize: u31) *CaveMapFragment {
	const compare = ChunkPosition {
		.wx = wx & ~@as(i32, CaveMapFragment.widthMask*voxelSize | voxelSize-1),
		.wy = wy & ~@as(i32, CaveMapFragment.widthMask*voxelSize | voxelSize-1),
		.wz = wz & ~@as(i32, CaveMapFragment.heightMask*voxelSize | voxelSize-1),
		.voxelSize = voxelSize,
	};
	const result = cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.raw, .Add, 1, .monotonic) != 0);
	return result;
}