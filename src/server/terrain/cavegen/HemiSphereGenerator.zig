const std = @import("std");
const sign = std.math.sign;

const main = @import("main");
const Array3D = main.utils.Array3D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const InterpolatableCaveBiomeMapView = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView;
const FractalNoise3D = terrain.noise.FractalNoise3D;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:noise_cave";

pub const priority = 65536;

pub const generatorSeed = 0x76490367012869;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn deinit() void {}

const scale = 64;
const interpolatedPart = 4;

const perimeter = 32;

fn getValue(noise: Array3D(f32), outerSizeShift: u5, relX: u31, relY: u31, relZ: u31) f32 {
	return noise.get(relX >> outerSizeShift, relY >> outerSizeShift, relZ >> outerSizeShift);
}

fn sdfUnion(a: f32, b: f32) f32 {
	return @min(a + b, a, b);
}

fn sdfIntersection(a: f32, b: f32) f32 {
	return @max(a, b);
}

fn generateSphere(output: Array3D(f32), rx: i32, ry: i32, rz: i32, radius: i32, voxelSize: u31, voxelSizeShift: u5) void {
	const minX = @max(0, rx - radius - perimeter) & ~(voxelSize - 1);
	const maxX = @min(output.width*voxelSize, rx + radius + perimeter);
	var x = minX;
	while (x < maxX) : (x += voxelSize) {
		const minY = @max(0, ry - radius - perimeter) & ~(voxelSize - 1);
		const maxY = @min(output.depth*voxelSize, ry + radius + perimeter);
		var y = minY;
		while (y < maxY) : (y += voxelSize) {
			const minZ = @max(0, rz - radius - perimeter) & ~(voxelSize - 1);
			const maxZ = @min(output.height*voxelSize, rz + radius + perimeter);
			var z = minZ;
			while (z < maxZ) : (z += voxelSize) {
				const distanceSquare = (x - rx)*(x - rx) + (y - ry)*(y - ry) + (z - rz)*(z - rz);
				if (distanceSquare > (radius + perimeter)*(radius + perimeter)) continue;
				if (rz - z < -perimeter) continue;
				const signedDistanceSquare: f32 = sdfIntersection(@floatFromInt(distanceSquare - radius*radius), @floatFromInt(std.math.sign(rz - z)*(rz - z)*(rz - z)));

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);

				out.* = sdfUnion(signedDistanceSquare, out.*);
			}
		}
	}
}

fn generateHalfCones(map: *const CaveMapFragment, output: Array3D(f32), voxelSize: u31, voxelSizeShift: u5) void {
	const maxRadius = 16;
	var wx: i32 = map.pos.wx -% maxRadius & ~@as(i32, maxRadius - 1);
	while (wx < map.pos.wx +% (@as(i32, CaveMapFragment.width) << map.voxelShift) +% 2*maxRadius) : (wx +%= maxRadius) {
		var wy: i32 = map.pos.wy -% maxRadius & ~@as(i32, maxRadius - 1);
		while (wy < map.pos.wy +% (@as(i32, CaveMapFragment.width) << map.voxelShift) +% 2*maxRadius) : (wy +%= maxRadius) {
			var wz: i32 = map.pos.wz -% maxRadius & ~@as(i32, maxRadius - 1);
			while (wz < map.pos.wz +% (@as(i32, CaveMapFragment.height) << map.voxelShift) +% 2*maxRadius) : (wz +%= maxRadius) {
				var seed = main.random.initSeed3D(532856, .{wx, wy, wz});
				for (0..1) |_| {
					if (main.random.nextFloat(&seed) > 0.01) break;
					const rx = main.random.nextIntBounded(i32, &seed, maxRadius) +% wx -% map.pos.wx;
					const ry = main.random.nextIntBounded(i32, &seed, maxRadius) +% wy -% map.pos.wy;
					const rz = main.random.nextIntBounded(i32, &seed, maxRadius) +% wz -% map.pos.wz;

					generateSphere(output, rx, ry, rz, main.random.nextIntBounded(i32, &seed, maxRadius/2) + maxRadius/2, voxelSize, voxelSizeShift);
				}
			}
		}
	}
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	if (map.pos.voxelSize > 2) return;
	const biomeMap = InterpolatableCaveBiomeMapView.init(main.stackAllocator, map.pos, CaveMapFragment.width*map.pos.voxelSize, 0);
	defer biomeMap.deinit();
	const outerSize = @max(map.pos.voxelSize, interpolatedPart);
	const outerSizeShift = std.math.log2_int(u31, outerSize);
	const outerSizeFloat: f32 = @floatFromInt(outerSize);
	const noise = FractalNoise3D.generateAligned(main.stackAllocator, map.pos.wx, map.pos.wy, map.pos.wz, outerSize, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, CaveMapFragment.height*map.pos.voxelSize/outerSize + 1, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, worldSeed ^ 4329561871, scale);
	defer noise.deinit(main.stackAllocator);
	for (noise.mem) |*val| {
		val.* = 1000;
	}
	generateHalfCones(map, noise, outerSize, outerSizeShift);

	// TODO: biomeMap.bulkInterpolateValue("caves", map.pos.wx, map.pos.wy, map.pos.wz, outerSize, noise, .addToMap, scale);
	var x: u31 = 0;
	while (x < map.pos.voxelSize*CaveMapFragment.width) : (x += outerSize) {
		var y: u31 = 0;
		while (y < map.pos.voxelSize*CaveMapFragment.width) : (y += outerSize) {
			var z: u31 = 0;
			while (z < map.pos.voxelSize*CaveMapFragment.height) : (z += outerSize) {
				const val000 = getValue(noise, outerSizeShift, x, y, z);
				const val001 = getValue(noise, outerSizeShift, x, y, z + outerSize);
				const val010 = getValue(noise, outerSizeShift, x, y + outerSize, z);
				const val011 = getValue(noise, outerSizeShift, x, y + outerSize, z + outerSize);
				const val100 = getValue(noise, outerSizeShift, x + outerSize, y, z);
				const val101 = getValue(noise, outerSizeShift, x + outerSize, y, z + outerSize);
				const val110 = getValue(noise, outerSizeShift, x + outerSize, y + outerSize, z);
				const val111 = getValue(noise, outerSizeShift, x + outerSize, y + outerSize, z + outerSize);
				// Test if they are all inside or all outside the cave to skip these cases:
				const measureForEquality = sign(val000) + sign(val001) + sign(val010) + sign(val011) + sign(val100) + sign(val101) + sign(val110) + sign(val111);
				if (measureForEquality == 8) {
					// No cave in here :)
					continue;
				}
				if (measureForEquality == -8) {
					// All cave in here :)
					var dx: u31 = 0;
					while (dx < outerSize) : (dx += map.pos.voxelSize) {
						var dy: u31 = 0;
						while (dy < outerSize) : (dy += map.pos.voxelSize) {
							map.removeRange(x + dx, y + dy, z, z + outerSize);
						}
					}
				} else {
					// Uses trilinear interpolation for the details.
					// Luckily due to the blocky nature of the game there is no visible artifacts from it.
					var dx: u31 = 0;
					while (dx < outerSize) : (dx += map.pos.voxelSize) {
						var dy: u31 = 0;
						while (dy < outerSize) : (dy += map.pos.voxelSize) {
							const ix = @as(f32, @floatFromInt(dx))/outerSizeFloat;
							const iy = @as(f32, @floatFromInt(dy))/outerSizeFloat;
							const lowerVal = ((1 - ix)*(1 - iy)*val000 + (1 - ix)*iy*val010 + ix*(1 - iy)*val100 + ix*iy*val110);
							const upperVal = ((1 - ix)*(1 - iy)*val001 + (1 - ix)*iy*val011 + ix*(1 - iy)*val101 + ix*iy*val111);
							// TODO: Determine the range that needs to be removed, and remove it in one go.
							if (upperVal*lowerVal > 0) { // All z values have the same sign → the entire column is the same.
								if (upperVal < 0) {
									// All cave in here :)
									map.removeRange(x + dx, y + dy, z, z + outerSize);
								} else {
									// No cave in here :)
								}
							} else {
								// Could be more efficient, but I'm lazy right now and I'll just go through the entire range:
								var dz: u31 = 0;
								while (dz < outerSize) : (dz += map.pos.voxelSize) {
									const iz = @as(f32, @floatFromInt(dz))/outerSizeFloat;
									const val = (1 - iz)*lowerVal + iz*upperVal;
									if (val < 0)
										map.removeRange(x + dx, y + dy, z + dz, z + dz + map.pos.voxelSize);
								}
							}
						}
					}
				}
			}
		}
	}
}
