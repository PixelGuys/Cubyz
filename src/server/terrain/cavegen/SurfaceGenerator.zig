const std = @import("std");
const sign = std.math.sign;

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const InterpolatableCaveBiomeMapView = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:surface";

pub const priority = 131072;

pub const generatorSeed = 0x7658930674389;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	_ = worldSeed;
	const width = CaveMapFragment.width*map.pos.voxelSize;
	const biomeMap = InterpolatableCaveBiomeMapView.init(main.stackAllocator, map.pos, width, 0);
	defer biomeMap.deinit();
	var x: u31 = 0;
	while(x < width) : (x += map.pos.voxelSize) {
		var y: u31 = 0;
		while(y < width) : (y += map.pos.voxelSize) {
			const height = biomeMap.getSurfaceHeight(map.pos.wx + x, map.pos.wy + y);
			const smallestHeight: i32 = @min(
				biomeMap.getSurfaceHeight(map.pos.wx +% x +% 1, map.pos.wy +% y),
				biomeMap.getSurfaceHeight(map.pos.wx +% x, map.pos.wy +% y +% 1),
				biomeMap.getSurfaceHeight(map.pos.wx +% x -% 1, map.pos.wy +% y),
				biomeMap.getSurfaceHeight(map.pos.wx +% x, map.pos.wy +% y -% 1),
				height,
			);
			const relativeHeight: i32 = height -% map.pos.wz;
			map.removeRange(x, y, relativeHeight, CaveMapFragment.height*map.pos.voxelSize);
			if(smallestHeight < 1) { // Seal off caves that intersect the ocean floor.
				map.addRange(x, y, smallestHeight -% 1 -% map.pos.wz, relativeHeight);
			}
		}
	}
}
