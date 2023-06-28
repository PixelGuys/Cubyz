const std = @import("std");

const main = @import("root");
const Array2D = main.utils.Array2D;

fn setSeed(x: i32, z: i32, offsetX: i32, offsetZ: i32, seed: *u64, worldSeed: u64, scale: u31, maxResolution: u31) void {
	seed.* = worldSeed*%(scale*maxResolution | 1);
	main.random.scrambleSeed(seed);
	const l1 = main.random.nextInt(i64, seed);
	const l2 = main.random.nextInt(i64, seed);
	seed.* = @as(u64, @bitCast(((offsetX +% x)*%maxResolution*%l1) ^ ((offsetZ +% z)*%maxResolution*%l2))) ^ worldSeed; // TODO: Use random.initSeed2D();
	main.random.scrambleSeed(seed);
}

pub fn generateFractalTerrain(wx: i32, wz: i32, x0: u31, z0: u31, width: u32, height: u32, scale: u31, worldSeed: u64, map: Array2D(f32), maxResolution: u31) !void {
	const max = scale + 1;
	const mask: i32 = scale - 1;
	const bigMap = try Array2D(f32).init(main.threadAllocator, max, max);
	defer bigMap.deinit(main.threadAllocator);
	const offsetX = wx & ~mask;
	const offsetZ = wz & ~mask;
	var seed: u64 = undefined;
	// Generate the 4 corner points of this map using a coordinate-depending seed:
	setSeed(0, 0, offsetX, offsetZ, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(0, 0).* = main.random.nextFloat(&seed);
	setSeed(0, scale, offsetX, offsetZ, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(0, scale).* = main.random.nextFloat(&seed);
	setSeed(scale, 0, offsetX, offsetZ, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(scale, 0).* = main.random.nextFloat(&seed);
	setSeed(scale, scale, offsetX, offsetZ, &seed, worldSeed, scale, maxResolution);
	bigMap.ptr(scale, scale).* = main.random.nextFloat(&seed);
	generateInitializedFractalTerrain(offsetX, offsetZ, scale, scale, worldSeed, bigMap, 0, 0.9999, maxResolution);
	var px: u31 = 0;
	while(px < width) : (px += 1) {
		@memcpy(map.getRow(x0 + px)[z0..][0..height], bigMap.getRow(@intCast((wx & mask) + px))[@intCast((wz & mask))..][0..height]);
	}
}

pub fn generateInitializedFractalTerrain(offsetX: i32, offsetZ: i32, scale: u31, startingScale: u31, worldSeed: u64, bigMap: Array2D(f32), lowerLimit: f32, upperLimit: f32, maxResolution: u31) void {
	// Increase the "grid" of points with already known heights in each round by a factor of 2×2, like so(# marks the gridpoints of the first grid, * the points of the second grid and + the points of the third grid(and so on…)):
	//
	//	#+*+#
	//	+++++
	//	*+*+*
	//	+++++
	//	#+*+#
	//
	// Each new gridpoint gets the average height value of the surrounding known grid points which is afterwards offset by a random value. Here is a visual representation of this process(with random starting values):
	//
	//█░▒▓						small							small
	//	█???█   grid    █?█?█   random	█?▓?█   grid	██▓██   random	██▓██
	//	?????   resize  ?????   change	?????   resize	▓▓▒▓█   change	▒▒▒▓█
	//	?????   →→→→    ▒?▒?▓   →→→→	▒?░?▓   →→→→	▒▒░▒▓   →→→→	▒░░▒▓
	//	?????           ?????   of new	?????   		░░░▒▓   of new	░░▒▓█
	//	 ???▒            ?░?▒   values	 ?░?▒   		 ░░▒▒   values	 ░░▒▒
	//	 
	//	 Another important thing to note is that the side length of the grid has to be 2^n + 1 because every new gridpoint needs a new neighbor. So the rightmost column and the bottom row are already part of the next map piece.
	//	 One other important thing in the implementation of this algorithm is that the relative height change has to decrease the in every iteration. Otherwise the terrain would look really noisy.
	const max = startingScale + 1;
	var seed: u64 = undefined;
	var res: u31 = startingScale/2;
	while(res != 0) : (res /= 2) {
		const randomnessScale = @as(f32, @floatFromInt(res))/@as(f32, @floatFromInt(scale))/2;
		// x coordinate on the grid:
		var x: u31 = 0;
		while(x < max) : (x += 2*res) {
			var z: u31 = res;
			while(z+res < max) : (z += 2*res) {
				setSeed(x, z, offsetX, offsetZ, &seed, worldSeed, res, maxResolution);
				bigMap.ptr(x, z).* = (bigMap.get(x, z-res)+bigMap.get(x, z+res))/2 + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, z).* = @min(upperLimit, @max(lowerLimit, bigMap.get(x, z)));
			}
		}
		// y coordinate on the grid:
		x = res;
		while(x+res < max) : (x += 2*res) {
			var z: u31 = 0;
			while(z < max) : (z += 2*res) {
				setSeed(x, z, offsetX, offsetZ, &seed, worldSeed, res, maxResolution);
				bigMap.ptr(x, z).* = (bigMap.get(x-res, z)+bigMap.get(x+res, z))/2 + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, z).* = @min(upperLimit, @max(lowerLimit, bigMap.get(x, z)));
			}
		}
		// No coordinate on the grid:
		x = res;
		while(x+res < max) : (x += 2*res) {
			var z: u31 = res;
			while(z+res < max) : (z += 2*res) {
				setSeed(x, z, offsetX, offsetZ, &seed, worldSeed, res, maxResolution);
				bigMap.ptr(x, z).* = (bigMap.get(x-res, z-res)+bigMap.get(x-res, z+res)+bigMap.get(x+res, z-res)+bigMap.get(x+res, z+res))/4 + main.random.nextFloatSigned(&seed)*randomnessScale;
				bigMap.ptr(x, z).* = @min(upperLimit, @max(lowerLimit, bigMap.get(x, z)));
			}
		}
	}
}

/// Same as `generateFractalTerrain`, but it generates only a reduced resolution version of the map.
pub fn generateSparseFractalTerrain(wx: i32, wz: i32, scale: u31, worldSeed: u64, map: Array2D(f32), maxResolution: u31) !void {
	const scaledWx = @divFloor(wx, maxResolution);
	const scaledWz = @divFloor(wz, maxResolution);
	const scaledScale = scale/maxResolution;
	var x0: u31 = 0;
	while(x0 < map.width) : (x0 += scaledScale) {
		var z0: u31 = 0;
		while(z0 < map.height) : (z0 += scaledScale) {
			try generateFractalTerrain(scaledWx +% x0, scaledWz +% z0, x0, z0, @min(map.width-x0, scaledScale), @min(map.height-z0, scaledScale), scaledScale, worldSeed, map, maxResolution);
		}
	}
}