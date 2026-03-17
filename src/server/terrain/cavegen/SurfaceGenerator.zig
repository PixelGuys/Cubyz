const std = @import("std");
const sign = std.math.sign;

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:surface";

pub const priority = 32768;

pub const generatorSeed = 0x7658930674389;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	_ = worldSeed;
	const width = CaveMapFragment.width*map.pos.voxelSize;
	const biomeMap = CaveBiomeMapView.init(main.stackAllocator, map.pos, width, 0);
	defer biomeMap.deinit();
	var x: u31 = 0;
	while(x < width) : (x += map.pos.voxelSize) {
		var y: u31 = 0;
		while(y < width) : (y += map.pos.voxelSize) {
			const height = biomeMap.getSurfaceHeight(map.pos.wx + x, map.pos.wy + y);
			const relativeHeight: i32 = height -% map.pos.wz;
			map.removeRange(x, y, relativeHeight, CaveMapFragment.height*map.pos.voxelSize);
		}
	}
}
