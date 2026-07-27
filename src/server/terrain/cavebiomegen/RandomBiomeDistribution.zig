const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapFragment = terrain.CaveBiomeMap.CaveBiomeMapFragment;
const Biome = terrain.biomes.Biome;
const Vec3i = main.vec.Vec3i;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:random_biome";

pub const priority = 1024;

pub const generatorSeed = 765893678349;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generate(map: *CaveBiomeMapFragment, worldSeed: u64) void {
	const marginDiv = 1024;
	const marginMulPositive: comptime_int = comptime CaveBiomeMapFragment.rotateInverse(.{marginDiv, 0, marginDiv})[2];
	const marginMulNegative: comptime_int = comptime CaveBiomeMapFragment.rotateInverse(.{0, marginDiv, 0})[2];

	var seed = random.initSeed3D(worldSeed, .{map.pos.wx, map.pos.wy, map.pos.wz});
	var z: u31 = 0;
	while (z < CaveBiomeMapFragment.caveBiomeMapSize) : (z += CaveBiomeMapFragment.caveBiomeSize) {
		var x: u31 = 0;
		while (x < CaveBiomeMapFragment.caveBiomeMapSize) : (x += CaveBiomeMapFragment.caveBiomeSize) {
			var y: u31 = 0;
			while (y < CaveBiomeMapFragment.caveBiomeMapSize) : (y += CaveBiomeMapFragment.caveBiomeSize) {
				const pos: main.vec.Vec3i = .{map.pos.wx + x, map.pos.wy + y, map.pos.wz + z};
				for (0..2) |_map| {
					const offset: Vec3i = @splat(if (_map == 0) 0 else CaveBiomeMapFragment.caveBiomeSize/2);
					const biomeWorldPos = CaveBiomeMapFragment.rotateInverse(pos + offset);
					const caveLayer = terrain.cave_layers.getLayer(biomeWorldPos[2]);
					while (true) {
						const biome = caveLayer.biomes.sample(&seed).*;
						if (biome.minHeight < biomeWorldPos[2] + CaveBiomeMapFragment.caveBiomeSize*marginMulPositive/marginDiv and biome.maxHeight > biomeWorldPos[2] + CaveBiomeMapFragment.caveBiomeSize*marginMulNegative/marginDiv) {
							const index = CaveBiomeMapFragment.getIndex(x, y, z);
							map.biomeMap[index][_map] = biome;
							break;
						}
					}
				}
			}
		}
	}
}
