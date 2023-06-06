const std = @import("std");
const Atomic = std.atomic.Atomic;
const Allocator = std.mem.Allocator;

const main = @import("root");
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const Cache = main.utils.Cache;
const JsonElement = main.JsonElement;

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


	pub fn init(self: *CaveMapFragment, wx: i32, wy: i32, wz: i32, voxelSize: u31) !void {
		self.* = .{
			.pos = .{
				.wx = wx, .wy = wy, .wz = wz,
				.voxelSize = voxelSize,
			},
			.voxelShift = @ctz(voxelSize),
		};
		@memset(&self.data, 0);
	}

	fn getIndex(x: i32, z: i32) usize {
		std.debug.assert(x >= 0 and x < width and z >= 0 and z < width); // Coordinates out of range.
		return @intCast(usize, x*width + z);
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
			@as(u64, std.math.maxInt(u64)) >> @intCast(u6, 64 - start)
		);
		const maskUpper = if(end <= 0) (
			std.math.maxInt(u64)
		) else if(end >= 64) (
			0
		) else (
			@as(u64, std.math.maxInt(u64)) << @intCast(u6, end)
		);
		return maskLower | maskUpper;
	}

	pub fn addRange(self: *CaveMapFragment, _relX: i32, _relZ: i32, _start: i32, _end: i32) void {
		const relX = _relX >> self.voxelShift;
		const relZ = _relZ >> self.voxelShift;
		const start = _start >> self.voxelShift;
		const end = _end >> self.voxelShift;
		(&self.data)[getIndex(relX, relZ)] |= ~getMask(start, end); // TODO: #13938
	}

	pub fn removeRange(self: *CaveMapFragment, _relX: i32, _relZ: i32, _start: i32, _end: i32) void {
		const relX = _relX >> self.voxelShift;
		const relZ = _relZ >> self.voxelShift;
		const start = _start >> self.voxelShift;
		const end = _end >> self.voxelShift;
		(&self.data)[getIndex(relX, relZ)] &= getMask(start, end); // TODO: #13938
	}

	pub fn getColumnData(self: *CaveMapFragment, _relX: i32, _relZ: i32) u64 {
		const relX = _relX >> self.voxelShift;
		const relZ = _relZ >> self.voxelShift;
		return (&self.data)[getIndex(relX, relZ)]; // TODO: #13938
	}
};

/// A generator for the cave map.
pub const CaveGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generate: *const fn(map: *CaveMapFragment, seed: u64) Allocator.Error!void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(CaveGenerator) = .{};

	pub fn registerGenerator(comptime Generator: type) !void {
		var self = CaveGenerator {
			.init = &Generator.init,
			.deinit = &Generator.deinit,
			.generate = &Generator.generate,
			.priority = Generator.priority,
			.generatorSeed = Generator.generatorSeed,
		};
		try generatorRegistry.put(main.globalAllocator, Generator.id, self);
	}

	pub fn getAndInitGenerators(allocator: std.mem.Allocator, settings: JsonElement) ![]CaveGenerator {
		const list = try allocator.alloc(CaveGenerator, generatorRegistry.size);
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

	pub fn init(chunk: *Chunk) !CaveMapView {
		return CaveMapView {
			.reference = chunk,
			.fragments = [_]*CaveMapFragment {
				try getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx - chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy - chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz - chunk.width, chunk.pos.voxelSize),
				try getOrGenerateFragment(chunk.pos.wx + chunk.width, chunk.pos.wy + chunk.width, chunk.pos.wz + chunk.width, chunk.pos.voxelSize),
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
		const fragmentRelY = @divFloor(wy - self.fragments[index].pos.wy, self.reference.pos.voxelSize);
		const fragmentRelZ = wz - self.fragments[index].pos.wz;
		const height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelZ);
		return (height & @as(u64, 1)<<@intCast(u6, fragmentRelY)) != 0;
	}

	pub fn getHeightData(self: CaveMapView, relX: i32, relZ: i32) u32 {
		const wx = relX + self.reference.pos.wx;
		const wz = relZ + self.reference.pos.wz;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wz - self.fragments[0].pos.wz >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 1;
		}
		var deltaY = self.reference.pos.wy - self.fragments[0].pos.wy;
		if(deltaY >= CaveMapFragment.height*self.reference.pos.voxelSize) {
			index += 2;
			deltaY -= CaveMapFragment.height*self.reference.pos.voxelSize;
		}
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelZ = wz - self.fragments[index].pos.wz;
		const height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelZ);
		if(deltaY == 0) {
			return @truncate(u32, height);
		} else {
			return @intCast(u32, height >> 32);
		}
	}

	pub fn findTerrainChangeAbove(self: CaveMapView, relX: i32, relZ: i32, y: i32) i32 {
		const wx = relX + self.reference.pos.wx;
		const wz = relZ + self.reference.pos.wz;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wz - self.fragments[0].pos.wz >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 1;
		}
		var relativeY = @divFloor(y + self.reference.pos.wy - self.fragments[0].pos.wy, self.reference.pos.voxelSize);
		std.debug.assert(relativeY >= 0 and relativeY < 2*CaveMapFragment.height);
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelZ = wz - self.fragments[index].pos.wz;
		var height: u64 = 0;
		var result: i32 = relativeY;
		if(relativeY < CaveMapFragment.height) {
			// Check the lower part first.
			height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelZ) >> @intCast(u6, relativeY);
			const startFilled = (height & 1) != 0;
			if(relativeY != 0) {
				height |= self.fragments[index+2].getColumnData(fragmentRelX, fragmentRelZ) << @intCast(u6, 64 - relativeY);
			}
			if(startFilled) {
				height = ~height;
			}
		} else {
			// Check only the upper part:
			result = @max(CaveMapFragment.height, result);
			relativeY -= CaveMapFragment.height;
			height = self.fragments[index+2].getColumnData(fragmentRelX, fragmentRelZ);
			height >>= @intCast(u6, relativeY);
			const startFilled = (height & 1) != 0;
			if(startFilled) {
				height = ~height;
			}
		}
		result += @ctz(height);
		return result*self.reference.pos.voxelSize + self.fragments[0].pos.wy - self.reference.pos.wy;
	}

	pub fn findTerrainChangeBelow(self: CaveMapView, relX: i32, relZ: i32, y: i32) i32 {
		const wx = relX + self.reference.pos.wx;
		const wz = relZ + self.reference.pos.wz;
		var index: u8 = 0;
		if(wx - self.fragments[0].pos.wx >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 4;
		}
		if(wz - self.fragments[0].pos.wz >= CaveMapFragment.width*self.reference.pos.voxelSize) {
			index += 1;
		}
		var relativeY = @divFloor(y + self.reference.pos.wy - self.fragments[0].pos.wy, self.reference.pos.voxelSize);
		std.debug.assert(relativeY >= 0 and relativeY < 2*CaveMapFragment.height);
		const fragmentRelX = wx - self.fragments[index].pos.wx;
		const fragmentRelZ = wz - self.fragments[index].pos.wz;
		var height: u64 = 0;
		var result: i32 = relativeY;
		if(relativeY >= CaveMapFragment.height) {
			relativeY -= CaveMapFragment.height;
			// Check the upper part first.
			height = self.fragments[index+2].getColumnData(fragmentRelX, fragmentRelZ) << (63 - @intCast(u6, relativeY));
			const startFilled = height & 1<<63 != 0;
			if(relativeY != CaveMapFragment.height - 1) {
				height |= self.fragments[index].getColumnData(fragmentRelX, fragmentRelZ) >> @intCast(u6, relativeY + 1);
			}
			if(startFilled) {
				height = ~height;
			}
		} else {
			// Check only the lower part:
			result = @min(CaveMapFragment.height - 1, result);
			height = self.fragments[index].getColumnData(fragmentRelX, fragmentRelZ);
			height <<= @intCast(u6, 63 - relativeY);
			const startFilled = (height & 1<<63) != 0;
			if(startFilled) {
				height = ~height;
			}
		}
		result -= @clz(height);
		return result*self.reference.pos.voxelSize + self.fragments[0].pos.wy - self.reference.pos.wy;
	}
};

const cacheSize = 1 << 9; // Must be a power of 2!
const cacheMask = cacheSize - 1;
const associativity = 8; // 512 MiB Cache size
var cache: Cache(CaveMapFragment, cacheSize, associativity, mapFragmentDeinit) = .{};
var profile: TerrainGenerationProfile = undefined;

fn mapFragmentDeinit(mapFragment: *CaveMapFragment) void {
	if(@atomicRmw(u16, &mapFragment.refCount.value, .Sub, 1, .Monotonic) == 1) {
		main.globalAllocator.destroy(mapFragment);
	}
}

fn cacheInit(pos: ChunkPosition) !*CaveMapFragment {
	const mapFragment = try main.globalAllocator.create(CaveMapFragment);
	try mapFragment.init(pos.wx, pos.wy, pos.wz, pos.voxelSize);
	for(profile.caveGenerators) |generator| {
		try generator.generate(mapFragment, profile.seed ^ generator.generatorSeed);
	}
	_ = @atomicRmw(u16, &mapFragment.refCount.value, .Add, 1, .Monotonic);
	return mapFragment;
}

pub fn initGenerators() !void {
	const list = @import("cavegen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try CaveGenerator.registerGenerator(@field(list, decl.name));
	}
}

pub fn deinitGenerators() void {
	CaveGenerator.generatorRegistry.clearAndFree(main.globalAllocator);
}

pub fn init(_profile: TerrainGenerationProfile) void {
	profile = _profile;
}

pub fn deinit() void {
	cache.clear();
}

fn getOrGenerateFragment(wx: i32, wy: i32, wz: i32, voxelSize: u31) !*CaveMapFragment {
	const compare = ChunkPosition {
		.wx = wx & ~@as(i32, CaveMapFragment.widthMask*voxelSize | voxelSize-1),
		.wy = wy & ~@as(i32, CaveMapFragment.heightMask*voxelSize | voxelSize-1),
		.wz = wz & ~@as(i32, CaveMapFragment.widthMask*voxelSize | voxelSize-1),
		.voxelSize = voxelSize,
	};
	const result = try cache.findOrCreate(compare, cacheInit);
	std.debug.assert(@atomicRmw(u16, &result.refCount.value, .Add, 1, .Monotonic) != 0);
	return result;
}