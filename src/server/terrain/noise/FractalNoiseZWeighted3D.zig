const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const ChunkPosition = main.chunk.ChunkPosition;
const random = main.random;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Vec3f = main.vec.Vec3f;

const FractalNoiseZWeighted3D = @This();


pos: ChunkPosition,
cache: Array3D(f32),
voxelShift: u5,
scale: u31,
worldSeed: u64,

pub fn generateAligned(allocator: NeverFailingAllocator, wx: i32, wy: i32, wz: i32, voxelSize: u31, width: u31, height: u31, depth: u31, worldSeed: u64, scale: u31, zWeight: f32) Array3D(f32) {
	std.debug.assert(wx & scale - 1 == 0 and wy & scale - 1 == 0 and wz & scale - 1 == 0); // Alignment;
	std.debug.assert(width - 1 & scale/voxelSize - 1 == 0 and height - 1 & scale/voxelSize - 1 == 0 and depth - 1 & scale/voxelSize - 1 == 0); // dimensions need to be of the form n*scale + 1 with n ∈ ℕ \ {0}
	std.debug.assert(width > 1 and height > 1 and depth > 1); // dimensions need to be of the form n*scale + 1 with n ∈ ℕ \ {0}
	const map = Array3D(f32).init(allocator, width, depth, height);

	const offset = @as(f32, @floatFromInt(scale))*@sqrt(@abs(zWeight*0.25))*std.math.sign(zWeight)*0.5;
	// Generate the corners:
	const scaledScale = scale/voxelSize;
	var x0: u31 = 0;
	while(x0 < width) : (x0 += scaledScale) {
		var y0: u31 = 0;
		while(y0 < depth) : (y0 += scaledScale) {
			var z0: u31 = 0;
			while(z0 < height) : (z0 += scaledScale) {
				var seed = random.initSeed3D(worldSeed, .{wx +% x0*voxelSize, wy +% y0*voxelSize, wz +% z0*voxelSize});
				map.ptr(x0, y0, z0).* = (random.nextFloat(&seed) - 0.5)*@as(f32, @floatFromInt(scale)) + offset;
			}
		}
	}

	generateInitializedFractalTerrain(wx, wy, wz, scaledScale, worldSeed, map, voxelSize, zWeight);

	return map;
}

fn averageWithWeight(a: f32, b: f32, startingScale: u31, maxResolution: u31, res: u31, weight: f32) f32 {
	const maxValue: f32 = @floatFromInt(startingScale*maxResolution);
	const fRes = @as(f32, @floatFromInt(res))/@as(f32, @floatFromInt(startingScale));
	const localWeight = -weight*(0.5 - a/maxValue*0.5)*fRes*4.0 + 0.5;
	return a*(1.0 - localWeight) + b*localWeight;
}

fn generateInitializedFractalTerrain(wx: i32, wy: i32, wz: i32, startingScale: u31, worldSeed: u64, bigMap: Array3D(f32), maxResolution: u31, zWeight: f32) void {
	// Basically an extension to 3D of the FractalNoise algorithm.
	var seed: u64 = undefined;
	var res: u31 = startingScale/2;
	while(res != 0) : (res /= 2) {
		const randomnessScale: f32 = @floatFromInt(res*maxResolution);
		// x and y coordinate on the grid:
		var x: u31 = 0;
		while(x < bigMap.width) : (x += 2*res) {
			var y: u31 = 0;
			while(y < bigMap.depth) : (y += 2*res) {
				var z: u31 = res;
				while(z + res < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = averageWithWeight(bigMap.get(x, y, z - res), bigMap.get(x, y, z + res), startingScale, maxResolution, res, zWeight);
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// x and z coordinate on the grid:
		x = 0;
		while(x < bigMap.width) : (x += 2*res) {
			var y: u31 = res;
			while(y + res < bigMap.depth) : (y += 2*res) {
				var z: u31 = 0;
				while(z < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x, y - res, z) + bigMap.get(x, y + res, z))/2;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// y and z coordinate on the grid:
		x = res;
		while(x + res < bigMap.width) : (x += 2*res) {
			var y: u31 = 0;
			while(y < bigMap.depth) : (y += 2*res) {
				var z: u31 = 0;
				while(z < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x - res, y, z) + bigMap.get(x + res, y, z))/2;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// x coordinate on the grid:
		x = 0;
		while(x < bigMap.width) : (x += 2*res) {
			var y: u31 = res;
			while(y + res < bigMap.depth) : (y += 2*res) {
				var z: u31 = res;
				while(z + res < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x, y - res, z) + bigMap.get(x, y + res, z))/4 + averageWithWeight(bigMap.get(x, y, z - res), bigMap.get(x, y, z + res), startingScale, maxResolution, res, zWeight)/2;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// y coordinate on the grid:
		x = res;
		while(x + res < bigMap.width) : (x += 2*res) {
			var y: u31 = 0;
			while(y < bigMap.depth) : (y += 2*res) {
				var z: u31 = res;
				while(z + res < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x - res, y, z) + bigMap.get(x + res, y, z))/4 + averageWithWeight(bigMap.get(x, y, z - res), bigMap.get(x, y, z + res), startingScale, maxResolution, res, zWeight)/2;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// z coordinate on the grid:
		x = res;
		while(x + res < bigMap.width) : (x += 2*res) {
			var y: u31 = res;
			while(y + res < bigMap.depth) : (y += 2*res) {
				var z: u31 = 0;
				while(z < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x - res, y, z) + bigMap.get(x + res, y, z) + bigMap.get(x, y - res, z) + bigMap.get(x, y + res, z))/4;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
		// No coordinate on the grid:
		x = res;
		while(x < bigMap.width) : (x += 2*res) {
			var y: u31 = res;
			while(y + res < bigMap.depth) : (y += 2*res) {
				var z: u31 = res;
				while(z + res < bigMap.height) : (z += 2*res) {
					seed = random.initSeed3D(worldSeed, .{x*maxResolution +% wx, y*maxResolution +% wy, z*maxResolution +% wz});
					bigMap.ptr(x, y, z).* = (bigMap.get(x - res, y, z) + bigMap.get(x + res, y, z) + bigMap.get(x, y - res, z) + bigMap.get(x, y + res, z))/6 + averageWithWeight(bigMap.get(x, y, z - res), bigMap.get(x, y, z + res), startingScale, maxResolution, res, zWeight)/3;
					bigMap.ptr(x, y, z).* += randomnessScale*(random.nextFloat(&seed) - 0.5);
				}
			}
		}
	}
}
