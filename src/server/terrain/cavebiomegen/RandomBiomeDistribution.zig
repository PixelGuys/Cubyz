const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapFragment = terrain.CaveBiomeMap.CaveBiomeMapFragment;
const Biome = terrain.biomes.Biome;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:random_biome";

pub const priority = 1024;

pub const generatorSeed = 765893678349;

var caveBiomes: []const Biome = undefined;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
	caveBiomes = terrain.biomes.getCaveBiomes();
}

pub fn generate(map: *CaveBiomeMapFragment, worldSeed: u64) void {
	// Select all the biomes that are within the given height range.
	var validBiomes = main.ListUnmanaged(*const Biome).initCapacity(main.stackAllocator, caveBiomes.len);
	defer validBiomes.deinit(main.stackAllocator);
	const worldPos = CaveBiomeMapFragment.rotateInverse(.{map.pos.wx, map.pos.wy, map.pos.wz});
	const marginDiv = 1024;
	const marginMulPositive: comptime_int = comptime CaveBiomeMapFragment.rotateInverse(.{marginDiv, 0, marginDiv})[2];
	const marginMulNegative: comptime_int = comptime CaveBiomeMapFragment.rotateInverse(.{0, marginDiv, 0})[2];
	for(caveBiomes) |*biome| {
		if(biome.minHeight < worldPos[2] +% CaveBiomeMapFragment.caveBiomeMapSize*marginMulPositive/marginDiv and biome.maxHeight > worldPos[2] +% CaveBiomeMapFragment.caveBiomeMapSize*marginMulNegative/marginDiv) {
			validBiomes.appendAssumeCapacity(biome);
		}
	}
	if(validBiomes.items.len == 0) {
		std.log.err("Couldn't find any cave biome on height {}. Using biome {s} instead.", .{worldPos[2], caveBiomes[0].id});
		validBiomes.appendAssumeCapacity(&caveBiomes[0]);
	}

	var seed = random.initSeed3D(worldSeed, .{map.pos.wx, map.pos.wy, map.pos.wz});
	var z: u31 = 0;
	while(z < CaveBiomeMapFragment.caveBiomeMapSize) : (z += CaveBiomeMapFragment.caveBiomeSize) {
		// Sort all biomes to the start that fit into the height region of the given z plane:
		var totalChance: f64 = 0;
		for(validBiomes.items) |b| {
			totalChance += b.chance;
		}
		if(totalChance == 0) {
			totalChance = 1;
		}
		var x: u31 = 0;
		while(x < CaveBiomeMapFragment.caveBiomeMapSize) : (x += CaveBiomeMapFragment.caveBiomeSize) {
			var y: u31 = 0;
			while(y < CaveBiomeMapFragment.caveBiomeMapSize) : (y += CaveBiomeMapFragment.caveBiomeSize) {
				const biomeWorldPos = CaveBiomeMapFragment.rotateInverse(.{map.pos.wx + x, map.pos.wy + y, map.pos.wz + z});
				for(0..2) |_map| {
					while(true) {
						var randomValue = random.nextDouble(&seed)*totalChance;
						var biome: *const Biome = undefined;
						var i: usize = 0;
						while(true) {
							biome = validBiomes.items[i];
							i += 1;
							randomValue -= biome.chance;
							if(randomValue < 0) break;
						}
						const index = CaveBiomeMapFragment.getIndex(x, y, z);
						map.biomeMap[index][_map] = biome;
						if(biome.minHeight < biomeWorldPos[2] + CaveBiomeMapFragment.caveBiomeSize*marginMulPositive/marginDiv and biome.maxHeight > biomeWorldPos[2] + CaveBiomeMapFragment.caveBiomeSize*marginMulNegative/marginDiv) {
							break;
						}
					}
				}
			}
		}
	}
}
