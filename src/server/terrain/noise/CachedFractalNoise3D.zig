const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const ChunkPosition = main.chunk.ChunkPosition;

const CachedFractalNoise3D = @This();

pos: ChunkPosition,
cache: Array3D(f32),
voxelShift: u5,
scale: u31,
worldSeed: u64,

pub fn init(wx: i32, wy: i32, wz: i32, voxelSize: u31, size: u31, worldSeed: u64, scale: u31) CachedFractalNoise3D {
	const maxSize = size/voxelSize;
	const cacheWidth = maxSize + 1;
	var self = CachedFractalNoise3D{
		.pos = .{
			.wx = wx,
			.wy = wy,
			.wz = wz,
			.voxelSize = voxelSize,
		},
		.voxelShift = @ctz(voxelSize),
		.cache = Array3D(f32).init(main.globalAllocator, cacheWidth, cacheWidth, cacheWidth),
		.scale = scale,
		.worldSeed = worldSeed,
	};
	// Init the corners:
	@memset(self.cache.mem, 0);
	const reducedScale = scale/voxelSize;
	var x: u31 = 0;
	while(x <= maxSize) : (x += reducedScale) {
		var y: u31 = 0;
		while(y <= maxSize) : (y += reducedScale) {
			var z: u31 = 0;
			while(z <= maxSize) : (z += reducedScale) {
				self.cache.ptr(x, y, z).* = (@as(f32, @floatFromInt(reducedScale + 1 + scale))*self.getGridValue(x, y, z))*@as(f32, @floatFromInt(voxelSize));
			} //                                                    ↑ sacrifice some resolution to reserve the value 0, for determining if the value was initialized. This prevents an expensive array initialization.
		}
	}
	return self;
}

pub fn deinit(self: CachedFractalNoise3D) void {
	self.cache.deinit(main.globalAllocator);
}

pub fn getRandomValue(self: CachedFractalNoise3D, wx: i32, wy: i32, wz: i32) f32 {
	var seed: u64 = main.random.initSeed3D(self.worldSeed, .{wx, wy, wz});
	return main.random.nextFloat(&seed) - 0.5;
}

fn getGridValue(self: CachedFractalNoise3D, relX: u31, relY: u31, relZ: u31) f32 {
	return self.getRandomValue(self.pos.wx +% relX*%self.pos.voxelSize, self.pos.wy +% relY*%self.pos.voxelSize, self.pos.wz +% relZ*%self.pos.voxelSize);
}

fn generateRegion(self: CachedFractalNoise3D, _x: u31, _y: u31, _z: u31, voxelSize: u31) void {
	const x = _x & ~@as(u31, voxelSize - 1);
	const y = _y & ~@as(u31, voxelSize - 1);
	const z = _z & ~@as(u31, voxelSize - 1);
	// Make sure that all higher points are generated:
	_ = self._getValue(x | voxelSize, y | voxelSize, z | voxelSize);

	const xMid = x + @divExact(voxelSize, 2);
	const yMid = y + @divExact(voxelSize, 2);
	const zMid = z + @divExact(voxelSize, 2);
	const randomFactor: f32 = @floatFromInt(voxelSize*self.pos.voxelSize);

	const cache = self.cache;

	var a: u31 = 0;
	while(a <= voxelSize) : (a += voxelSize) { // 2 coordinates on the grid.
		var b: u31 = 0;
		while(b <= voxelSize) : (b += voxelSize) {
			// x-y
			cache.ptr(x + a, y + b, zMid).* = (cache.get(x + a, y + b, z) + cache.get(x + a, y + b, z + voxelSize))/2;
			cache.ptr(x + a, y + b, zMid).* += randomFactor*self.getGridValue(x + a, y + b, zMid);
			// x-z
			cache.ptr(x + a, yMid, z + b).* = (cache.get(x + a, y, z + b) + cache.get(x + a, y + voxelSize, z + b))/2;
			cache.ptr(x + a, yMid, z + b).* += randomFactor*self.getGridValue(x + a, yMid, z + b);
			// x-z
			cache.ptr(xMid, y + a, z + b).* = (cache.get(x, y + a, z + b) + cache.get(x + voxelSize, y + a, z + b))/2;
			cache.ptr(xMid, y + a, z + b).* += randomFactor*self.getGridValue(xMid, y + a, z + b);
		}
	}

	a = 0;
	while(a <= voxelSize) : (a += voxelSize) { // 1 coordinate on the grid.
		// x
		cache.ptr(x + a, yMid, zMid).* = (cache.get(x + a, yMid, z) + cache.get(x + a, yMid, z + voxelSize) + cache.get(x + a, y, zMid) + cache.get(x + a, y + voxelSize, zMid))/4 + randomFactor*self.getGridValue(x + a, yMid, zMid);
		// y
		cache.ptr(xMid, y + a, zMid).* = (cache.get(xMid, y + a, z) + cache.get(xMid, y + a, z + voxelSize) + cache.get(x, y + a, zMid) + cache.get(x + voxelSize, y + a, zMid))/4 + randomFactor*self.getGridValue(xMid, y + a, zMid);
		// z
		cache.ptr(xMid, yMid, z + a).* = (cache.get(xMid, y, z + a) + cache.get(xMid, y + voxelSize, z + a) + cache.get(x, yMid, z + a) + cache.get(x + voxelSize, yMid, z + a))/4 + randomFactor*self.getGridValue(xMid, yMid, z + a);
	}

	// Center point:
	cache.ptr(xMid, yMid, zMid).* = (cache.get(xMid, yMid, z) + cache.get(xMid, yMid, z + voxelSize) + cache.get(xMid, y, zMid) + cache.get(xMid, y + voxelSize, zMid) + cache.get(x, yMid, zMid) + cache.get(x + voxelSize, yMid, zMid))/6 + randomFactor*self.getGridValue(xMid, yMid, zMid);
}

fn _getValue(self: CachedFractalNoise3D, x: u31, y: u31, z: u31) f32 {
	const value = self.cache.get(x, y, z);
	if(value != 0) return value;
	// Need to actually generate stuff now.
	const minShift = @min(@ctz(x), @ctz(y), @ctz(z));
	self.generateRegion(x, y, z, @as(u31, 2) << @intCast(minShift));
	return self.cache.get(x, y, z);
}

pub fn getValue(self: CachedFractalNoise3D, wx: i32, wy: i32, wz: i32) f32 {
	const x: u31 = @intCast((wx -% self.pos.wx) >> self.voxelShift);
	const y: u31 = @intCast((wy -% self.pos.wy) >> self.voxelShift);
	const z: u31 = @intCast((wz -% self.pos.wz) >> self.voxelShift);
	return self._getValue(x, y, z) - @as(f32, @floatFromInt(self.scale));
}
