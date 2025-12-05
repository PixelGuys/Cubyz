const std = @import("std");

const main = @import("main");

fn setSeed(x: i32, offsetX: i32, seed: *u64, worldSeed: u64, scale: u31) void {
	seed.* = main.random.initSeed2D(worldSeed, .{offsetX +% x, scale});
}

pub fn generateFractalTerrain(wx: i32, x0: u31, width: u32, scale: u31, worldSeed: u64, map: []f32) void {
	const max = scale + 1;
	const mask: i32 = scale - 1;
	const bigMap = main.stackAllocator.alloc(f32, max);
	defer main.stackAllocator.free(bigMap);
	const offset = wx & ~mask;
	var seed: u64 = undefined;
	// Generate the 4 corner points of this map using a coordinate-depending seed:
	setSeed(0, offset, &seed, worldSeed, scale);
	bigMap[0] = main.random.nextFloat(&seed);
	setSeed(scale, offset, &seed, worldSeed, scale);
	bigMap[scale] = main.random.nextFloat(&seed);
	generateInitializedFractalTerrain(offset, scale, scale, worldSeed, bigMap, 0, 0.9999);
	@memcpy(map[x0..][0..width], bigMap[@intCast((wx & mask))..][0..width]);
}

pub fn generateInitializedFractalTerrain(offset: i32, scale: u31, startingScale: u31, worldSeed: u64, bigMap: []f32, lowerLimit: f32, upperLimit: f32) void {
	const max = startingScale + 1;
	var seed: u64 = undefined;
	var res: u31 = startingScale/2;
	while(res != 0) : (res /= 2) {
		const randomnessScale = @as(f32, @floatFromInt(res))/@as(f32, @floatFromInt(scale))/2;
		// No coordinate on the grid:
		var x = res;
		while(x + res < max) : (x += 2*res) {
			setSeed(x, offset, &seed, worldSeed, res);
			bigMap[x] = (bigMap[x - res] + bigMap[x + res])/2 + main.random.nextFloatSigned(&seed)*randomnessScale;
			bigMap[x] = @min(upperLimit, @max(lowerLimit, bigMap[x]));
		}
	}
}

pub fn generateSparseFractalTerrain(wx: i32, scale: u31, worldSeed: u64, map: []f32) void {
	var x0: u31 = 0;
	while(x0 < map.len) : (x0 += scale) {
		generateFractalTerrain(wx +% x0, x0, @min(map.len - x0, scale), scale, worldSeed, map);
	}
}
