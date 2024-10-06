const std = @import("std");

const main = @import("root");
const Array2D = main.utils.Array2D;

fn setSeed(x: i32, y: i32, offsetX: i32, offsetY: i32, seed: *u64, worldSeed: u64, scale: u31, maxResolution: u31) void {
	seed.* = main.random.initSeed2D(worldSeed*%(scale*maxResolution | 1), .{(offsetX +% x)*%maxResolution, (offsetY +% y)*%maxResolution});
}

pub fn generateFractalTerrain(wx: i32, wy: i32, x0: u31, y0: u31, width: u32, height: u32, scale: u31, worldSeed: u64, map: Array2D(f32), maxResolution: u31) void {
	const max = scale + 1;
	const mask: i32 = scale - 1;
	const bigMap = Array2D(f32).init(main.stackAllocator, max, max);
	defer bigMap.deinit(main.stackAllocator);
	const offsetX = wx & ~mask;
	const offsetY = wy & ~mask;
	var seed: u64 = undefined;
	// Generate the 4 corner points of this map using a coordinate-depending seed:
	setSeed(0, 0, offsetX, offsetY, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(0, 0).* = main.random.nextFloat(&seed);
	setSeed(0, scale, offsetX, offsetY, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(0, scale).* = main.random.nextFloat(&seed);
	setSeed(scale, 0, offsetX, offsetY, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(scale, 0).* = main.random.nextFloat(&seed);
	setSeed(scale, scale, offsetX, offsetY, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(scale, scale).* = main.random.nextFloat(&seed);
	generateInitializedFractalTerrain(offsetX, offsetY, scale, scale, worldSeed, bigMap, maxResolution);
	var px: u31 = 0;
	while(px < width) : (px += 1) {
		@memcpy(map.getRow(x0 + px)[y0..][0..height], bigMap.getRow(@intCast((wx & mask) + px))[@intCast((wy & mask))..][0..height]);
	}
}

pub fn generateInitializedFractalTerrain(offsetX: i32, offsetY: i32, scale: u31, startingScale: u31, worldSeed: u64, bigMap: Array2D(f32), maxResolution: u31) void {
	// Increase the "grid" of points with already known heights in each round by a factor of 2×2, like so(# marks the gridpoints of the first grid, * the points of the second grid and + the points of the third grid(and so on…)):
	//
	//  #+*+#
	//  +++++
	//  *+*+*
	//  +++++
	//  #+*+#
	//
	// Each new gridpoint gets the interpolated height value of the surrounding known grid points using random weights. Afterwards this value gets offset by a random value.
	// Here is a visual representation of this process(with random starting values):
	//
	//█░▒▓                      small                           small
	//  █???█   grid    █?█?█   random  █?▓?█   grid    ██▓▓█   random  ██▓▓█
	//  ?????   resize  ?????   change  ?????   resize  █▓▓▓▒   change  █▓█▓▒
	//  ?????   →→→→    ▓?▓?▒   →→→→    ▒?█?▒   →→→→    ▒▒██▒   →→→→    ▒▒██▒
	//  ?????           ?????   of new  ?????           ░▒░▒▒   of new  ░▒░▒░
	//  ???▒            ? ?▒   values   ?░?▒             ░░▒   values    ░░▒
	//
	// Another important thing to note is that the side length of the grid has to be 2^n + 1 because every new gridpoint needs a new neighbor.
	// So the rightmost column and the bottom row are already part of the next map piece.
	// One other important thing in the implementation of this algorithm is that the relative height change has to decrease in every iteration. Otherwise the terrain would look noisy.
	const max = startingScale + 1;
	var seed: u64 = undefined;
	var res: u31 = startingScale/2;
	while(res != 0) : (res /= 2) {
		const randomnessScale = @as(f32, @floatFromInt(res))/@as(f32, @floatFromInt(scale))/2;
		// x coordinate on the grid:
		var x: u31 = 0;
		while(x < max) : (x += 2*res) {
			var y: u31 = res;
			while(y+res < max) : (y += 2*res) {
				setSeed(x, y, offsetX, offsetY, &seed, worldSeed, res, maxResolution);
				const w = main.random.nextFloat(&seed);
				bigMap.ptr(x, y).* = bigMap.get(x, y-res)*(1-w)+bigMap.get(x, y+res)*w + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, y).* = bigMap.get(x, y);
			}
		}
		// y coordinate on the grid:
		x = res;
		while(x+res < max) : (x += 2*res) {
			var y: u31 = 0;
			while(y < max) : (y += 2*res) {
				setSeed(x, y, offsetX, offsetY, &seed, worldSeed, res, maxResolution);
				const w = main.random.nextFloat(&seed);
				bigMap.ptr(x, y).* = bigMap.get(x-res, y)*(1-w)+bigMap.get(x+res, y)*w + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, y).* = bigMap.get(x, y);
			}
		}
		// No coordinate on the grid:
		x = res;
		while(x+res < max) : (x += 2*res) {
			var y: u31 = res;
			while(y+res < max) : (y += 2*res) {
				setSeed(x, y, offsetX, offsetY, &seed, worldSeed, res, maxResolution);
				const w1 = main.random.nextFloat(&seed);
				const w2 = main.random.nextFloat(&seed);
				bigMap.ptr(x, y).* = (bigMap.get(x-res, y-res)*(1-w1) + bigMap.get(x-res, y+res)*w1)*(1-w2) + (bigMap.get(x+res, y-res)*(1-w1) + bigMap.get(x+res, y+res)*w1)*w2 + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, y).* = bigMap.get(x, y);
			}
		}
	}
}

/// Same as `generateFractalTerrain`, but it generates only a reduced resolution version of the map.
pub fn generateSparseFractalTerrain(wx: i32, wy: i32, scale: u31, worldSeed: u64, map: Array2D(f32), maxResolution: u31) void {
	const scaledWx = @divFloor(wx, maxResolution);
	const scaledWy = @divFloor(wy, maxResolution);
	const scaledScale = scale/maxResolution;
	var x0: u31 = 0;
	while(x0 < map.width) : (x0 += scaledScale) {
		var y0: u31 = 0;
		while(y0 < map.height) : (y0 += scaledScale) {
			generateFractalTerrain(scaledWx +% x0, scaledWy +% y0, x0, y0, @min(map.width-x0, scaledScale), @min(map.height-y0, scaledScale), scaledScale, worldSeed, map, maxResolution);
		}
	}
}