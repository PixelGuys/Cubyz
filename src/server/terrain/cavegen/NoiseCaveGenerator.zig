const std = @import("std");
const Allocator = std.mem.Allocator;
const sign = std.math.sign;

const main = @import("root");
const Array3D = main.utils.Array3D;
const random = main.random;
const JsonElement = main.JsonElement;
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

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

const scale = 64;
const interpolatedPart = 4;

fn getValue(noise: Array3D(f32), outerSizeShift: u5, relX: u31, relY: u31, relZ: u31) f32 {
	return noise.get(relX >> outerSizeShift, relY >> outerSizeShift, relZ >> outerSizeShift);
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) Allocator.Error!void {
	if(map.pos.voxelSize > 2) return;
	const biomeMap = try InterpolatableCaveBiomeMapView.init(map.pos, CaveMapFragment.width*map.pos.voxelSize);
	defer biomeMap.deinit();
	const outerSize = @max(map.pos.voxelSize, interpolatedPart);
	const outerSizeShift = std.math.log2_int(u31, outerSize);
	const outerSizeFloat: f32 = @floatFromInt(outerSize);
	var noise = try FractalNoise3D.generateAligned(main.threadAllocator, map.pos.wx, map.pos.wy, map.pos.wz, outerSize, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, CaveMapFragment.height*map.pos.voxelSize/outerSize + 1, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, worldSeed, scale);//try Cached3DFractalNoise.init(map.pos.wx, map.pos.wy & ~@as(i32, CaveMapFragment.width*map.pos.voxelSize - 1), map.pos.wz, outerSize, map.pos.voxelSize*CaveMapFragment.width, worldSeed, scale);
	defer noise.deinit(main.threadAllocator);
	biomeMap.bulkInterpolateValue("caves", map.pos.wx, map.pos.wy, map.pos.wz, outerSize, noise, .addToMap, scale);
	var x: u31 = 0;
	while(x < map.pos.voxelSize*CaveMapFragment.width) : (x += outerSize) {
		var y: u31 = 0;
		while(y < map.pos.voxelSize*CaveMapFragment.height) : (y += outerSize) {
			var z: u31 = 0;
			while(z < map.pos.voxelSize*CaveMapFragment.width) : (z += outerSize) {
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
				if(measureForEquality == -8) {
					// No cave in here :)
					continue;
				}
				if(measureForEquality == 8) {
					// All cave in here :)
					var dx: u31 = 0;
					while(dx < outerSize) : (dx += map.pos.voxelSize) {
						var dz: u31 = 0;
						while(dz < outerSize) : (dz += map.pos.voxelSize) {
							map.removeRange(x + dx, z + dz, y, y + outerSize);
						}
					}
				} else {
					// Uses trilinear interpolation for the details.
					// Luckily due to the blocky nature of the game there is no visible artifacts from it.
					var dx: u31 = 0;
					while(dx < outerSize) : (dx += map.pos.voxelSize) {
						var dz: u31 = 0;
						while(dz < outerSize) : (dz += map.pos.voxelSize) {
							const ix = @as(f32, @floatFromInt(dx))/outerSizeFloat;
							const iz = @as(f32, @floatFromInt(dz))/outerSizeFloat;
							const lowerVal = (
								(1 - ix)*(1 - iz)*val000
								+ (1 - ix)*iz*val001
								+ ix*(1 - iz)*val100
								+ ix*iz*val101
							);
							const upperVal = (
								(1 - ix)*(1 - iz)*val010
								+ (1 - ix)*iz*val011
								+ ix*(1 - iz)*val110
								+ ix*iz*val111
							);
							// TODO: Determine the range that needs to be removed, and remove it in one go.
							if(upperVal*lowerVal > 0) { // All y values have the same sign → the entire column is the same.
								if(upperVal > 0) {
									// All cave in here :)
									map.removeRange(x + dx, z + dz, y, y + outerSize);
								} else {
									// No cave in here :)
								}
							} else {
								// Could be more efficient, but I'm lazy right now and I'll just go through the entire range:
								var dy: u31 = 0;
								while(dy < outerSize) : (dy += map.pos.voxelSize) {
									const iy = @as(f32, @floatFromInt(dy))/outerSizeFloat;
									const val = (1 - iy)*lowerVal + iy*upperVal;
									if(val > 0)
										map.removeRange(x + dx, z + dz, y + dy, y + dy + map.pos.voxelSize);
								}
							}
						}
					}
				}
			}
		}
	}
}