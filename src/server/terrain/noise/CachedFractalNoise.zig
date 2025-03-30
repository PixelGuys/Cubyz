const std = @import("std");

const main = @import("main");
const Array2D = main.utils.Array2D;
const MapFragmentPosition = main.server.terrain.SurfaceMap.MapFragmentPosition;

const CachedFractalNoise = @This();

pos: MapFragmentPosition,
cache: Array2D(f32),
scale: u31,
worldSeed: u64,

pub fn init(wx: i32, wy: i32, voxelSize: u31, size: u31, worldSeed: u64, scale: u31) CachedFractalNoise {
	const maxSize = size/voxelSize;
	const cacheWidth = maxSize + 1;
	var self = CachedFractalNoise{
		.pos = .{
			.wx = wx,
			.wy = wy,
			.voxelSize = voxelSize,
			.voxelSizeShift = @ctz(voxelSize),
		},
		.cache = .init(main.globalAllocator, cacheWidth, cacheWidth),
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
			self.cache.ptr(x, y).* = (@as(f32, @floatFromInt(reducedScale + 1 + scale))*self.getGridValue(x, y))*@as(f32, @floatFromInt(voxelSize));
		} //                                                 ↑ sacrifice some resolution to reserve the value 0, for determining if the value was initialized. This prevents an expensive array initialization.
	}
	return self;
}

pub fn deinit(self: CachedFractalNoise) void {
	self.cache.deinit(main.globalAllocator);
}

pub fn getRandomValue(self: CachedFractalNoise, wx: i32, wy: i32) f32 {
	var seed: u64 = main.random.initSeed2D(self.worldSeed, .{wx, wy});
	return main.random.nextFloat(&seed) - 0.5;
}

fn getGridValue(self: CachedFractalNoise, relX: u31, relY: u31) f32 {
	return self.getRandomValue(self.pos.wx +% relX*%self.pos.voxelSize, self.pos.wy +% relY*%self.pos.voxelSize);
}

fn generateRegion(self: CachedFractalNoise, _x: u31, _y: u31, voxelSize: u31) void {
	const x = _x & ~@as(u31, voxelSize - 1);
	const y = _y & ~@as(u31, voxelSize - 1);
	// Make sure that all higher points are generated:
	_ = self._getValue(x | voxelSize, y | voxelSize);

	const xMid = x + @divExact(voxelSize, 2);
	const yMid = y + @divExact(voxelSize, 2);
	const randomFactor: f32 = @floatFromInt(voxelSize*self.pos.voxelSize);

	const cache = self.cache;

	var a: u31 = 0;
	while(a <= voxelSize) : (a += voxelSize) { // 1 coordinate on the grid.
		// x
		cache.ptr(x + a, yMid).* = (cache.get(x + a, y) + cache.get(x + a, y + voxelSize))/2;
		cache.ptr(x + a, yMid).* += randomFactor*self.getGridValue(x + a, yMid);
		// y
		cache.ptr(xMid, y + a).* = (cache.get(x, y + a) + cache.get(x + voxelSize, y + a))/2;
		cache.ptr(xMid, y + a).* += randomFactor*self.getGridValue(xMid, y + a);
	}

	// Center point:
	cache.ptr(xMid, yMid).* = (cache.get(xMid, y) + cache.get(xMid, y + voxelSize) + cache.get(x, yMid) + cache.get(x + voxelSize, yMid))/4 + randomFactor*self.getGridValue(xMid, yMid);
}

fn _getValue(self: CachedFractalNoise, x: u31, y: u31) f32 {
	const value = self.cache.get(x, y);
	if(value != 0) return value;
	// Need to actually generate stuff now.
	const minShift = @min(@ctz(x), @ctz(y));
	self.generateRegion(x, y, @as(u31, 2) << @intCast(minShift));
	return self.cache.get(x, y);
}

pub fn getValue(self: CachedFractalNoise, wx: i32, wy: i32) f32 {
	const x: u31 = @intCast((wx -% self.pos.wx) >> self.pos.voxelSizeShift);
	const y: u31 = @intCast((wy -% self.pos.wy) >> self.pos.voxelSizeShift);
	return self._getValue(x, y) - @as(f32, @floatFromInt(self.scale));
}
