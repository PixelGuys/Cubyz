const std = @import("std");

const main = @import("root");
const ChunkPosition = main.chunk.ChunkPosition;

const Cached3dFractalNoise = @This();

pos: ChunkPosition,
cache: []f32,
cacheWidth: u32,
voxelShift: u5,
scale: u31,
worldSeed: u64,

fn getIndex(cacheWidth: u32, x: anytype, y: @TypeOf(x), z: @TypeOf(x)) u32 {
	return (@intCast(u32, x)*cacheWidth + @intCast(u32, y))*cacheWidth + @intCast(u32, z);
}

pub fn init(wx: i32, wy: i32, wz: i32, voxelSize: u31, size: u31, worldSeed: u64, scale: u31) !Cached3dFractalNoise {
	const maxSize = size/voxelSize;
	const cacheWidth = maxSize + 1;
	var self = Cached3dFractalNoise {
		.pos = .{
			.wx = wx, .wy = wy, .wz = wz,
			.voxelSize = voxelSize,
		},
		.voxelShift = @ctz(voxelSize),
		.cache = try main.globalAllocator.alloc(f32, cacheWidth*cacheWidth*cacheWidth),
		.cacheWidth = cacheWidth,
		.scale = scale,
		.worldSeed = worldSeed,
	};
	// Init the corners:
	std.mem.set(f32, self.cache, 0);
	const reducedScale = scale/voxelSize;
	var x: u31 = 0;
	while(x <= maxSize) : (x += reducedScale) {
		var y: u31 = 0;
		while(y <= maxSize) : (y += reducedScale) {
			var z: u31 = 0;
			while(z <= maxSize) : (z += reducedScale) {
				self.cache[getIndex(cacheWidth, x, y, z)] = (@intToFloat(f32, reducedScale + 1 + scale)*self.getGridValue(x, y, z))*@intToFloat(f32, voxelSize);
			}//                                               ↑ sacrifice some resolution to reserve the value 0, for determining if the value was initialized. This prevents an expensive array initialization.
		}
	}
	return self;
}

pub fn deinit(self: Cached3dFractalNoise) void {
	main.globalAllocator.free(self.cache);
}

pub fn getRandomValue(self: Cached3dFractalNoise, wx: i32, wy: i32, wz: i32) f32 {
	var seed: u64 = main.random.initSeed3D(self.worldSeed, .{wx, wy, wz});
	return main.random.nextFloat(&seed) - 0.5;
}

fn getGridValue(self: Cached3dFractalNoise, relX: i32, relY: i32, relZ: i32) f32 {
	return self.getRandomValue(self.pos.wx +% relX*%self.pos.voxelSize, self.pos.wy +% relY*%self.pos.voxelSize, self.pos.wz +% relZ*%self.pos.voxelSize);
}

fn generateRegion(self: Cached3dFractalNoise, _x: i32, _y: i32, _z: i32, voxelSize: u31) void {
	const x = _x & ~@as(i32, voxelSize-1);
	const y = _y & ~@as(i32, voxelSize-1);
	const z = _z & ~@as(i32, voxelSize-1);
	// Make sure that all higher points are generated:
	_ = self._getValue(x | voxelSize, y | voxelSize, z | voxelSize);

	const xMid = x + @divExact(voxelSize, 2);
	const yMid = y + @divExact(voxelSize, 2);
	const zMid = z + @divExact(voxelSize, 2);
	const randomFactor = @intToFloat(f32, voxelSize*self.pos.voxelSize);

	const cache = self.cache;
	const cacheWidth = self.cacheWidth;

	var a: u31 = 0;
	while(a <= voxelSize) : (a += voxelSize) { // 2 coordinates on the grid.
		var b: u31 = 0;
		while(b <= voxelSize) : (b += voxelSize) {
			// x-y
			cache[getIndex(cacheWidth, x + a, y + b, zMid)] = (cache[getIndex(cacheWidth, x + a, y + b, z)] + cache[getIndex(cacheWidth, x + a, y + b, z + voxelSize)])/2;
			cache[getIndex(cacheWidth, x + a, y + b, zMid)] += randomFactor*self.getGridValue(x + a, y + b, zMid);
			// x-z
			cache[getIndex(cacheWidth, x + a, yMid, z + b)] = (cache[getIndex(cacheWidth, x + a, y, z + b)] + cache[getIndex(cacheWidth, x + a, y + voxelSize, z + b)])/2;
			cache[getIndex(cacheWidth, x + a, yMid, z + b)] += randomFactor*self.getGridValue(x + a, yMid, z + b);
			// x-z
			cache[getIndex(cacheWidth, xMid, y + a, z + b)] = (cache[getIndex(cacheWidth, x, y + a, z + b)] + cache[getIndex(cacheWidth, x + voxelSize, y + a, z + b)])/2;
			cache[getIndex(cacheWidth, xMid, y + a, z + b)] += randomFactor*self.getGridValue(xMid, y + a, z + b);
		}
	}

	a = 0;
	while(a <= voxelSize) : (a += voxelSize) { // 1 coordinate on the grid.
		// x
		cache[getIndex(cacheWidth, x + a, yMid, zMid)] = (
			cache[getIndex(cacheWidth, x + a, yMid, z)] + cache[getIndex(cacheWidth, x + a, yMid, z + voxelSize)]
			+ cache[getIndex(cacheWidth, x + a, y, zMid)] + cache[getIndex(cacheWidth, x + a, y + voxelSize, zMid)]
		)/4 + randomFactor*self.getGridValue(x + a, yMid, zMid);
		// y
		cache[getIndex(cacheWidth, xMid, y + a, zMid)] = (
			cache[getIndex(cacheWidth, xMid, y + a, z)] + cache[getIndex(cacheWidth, xMid, y + a, z + voxelSize)]
			+ cache[getIndex(cacheWidth, x, y + a, zMid)] + cache[getIndex(cacheWidth, x + voxelSize, y + a, zMid)]
		)/4 + randomFactor*self.getGridValue(xMid, y + a, zMid);
		// z
		cache[getIndex(cacheWidth, xMid, yMid, z + a)] = (
			cache[getIndex(cacheWidth, xMid, y, z + a)] + cache[getIndex(cacheWidth, xMid, y + voxelSize, z + a)]
			+ cache[getIndex(cacheWidth, x, yMid, z + a)] + cache[getIndex(cacheWidth, x + voxelSize, yMid, z + a)]
		)/4 + randomFactor*self.getGridValue(xMid, yMid, z + a);
	}

	// Center point:
	cache[getIndex(cacheWidth, xMid, yMid, zMid)] = (
		cache[getIndex(cacheWidth, xMid, yMid, z)] + cache[getIndex(cacheWidth, xMid, yMid, z + voxelSize)]
		+ cache[getIndex(cacheWidth, xMid, y, zMid)] + cache[getIndex(cacheWidth, xMid, y + voxelSize, zMid)]
		+ cache[getIndex(cacheWidth, x, yMid, zMid)] + cache[getIndex(cacheWidth, x + voxelSize, yMid, zMid)]
	)/6 + randomFactor*self.getGridValue(xMid, yMid, zMid);
}

fn _getValue(self: Cached3dFractalNoise, x: i32, y: i32, z: i32) f32 {
	const value = self.cache[getIndex(self.cacheWidth, x, y, z)];
	if(value != 0) return value;
	// Need to actually generate stuff now.
	const minShift = @min(@ctz(x), @min(@ctz(y), @ctz(z)));
	self.generateRegion(x, y, z, @as(u31, 2) << @intCast(u5, minShift));
	return self.cache[getIndex(self.cacheWidth, x, y, z)];
}

pub fn getValue(self: Cached3dFractalNoise, wx: i32, wy: i32, wz: i32) f32 {
	const x = (wx - self.pos.wx) >> self.voxelShift;
	const y = (wy - self.pos.wy) >> self.voxelShift;
	const z = (wz - self.pos.wz) >> self.voxelShift;
	return self._getValue(x, y, z) - @intToFloat(f32, self.scale);
}