const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveBiomeMapFragment = terrain.CaveBiomeMap.CaveBiomeMapFragment;
const Biome = terrain.biomes.Biome;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:random_biome";

pub const priority = 1024;

pub const generatorSeed = 765893678349;

var caveBiomes: []const Biome = undefined;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
	caveBiomes = terrain.biomes.getCaveBiomes();
}

pub fn deinit() void {

}

pub fn generate(map: *CaveBiomeMapFragment, worldSeed: u64) void {
	// Select all the biomes that are within the given height range.
	var validBiomes = main.ListUnmanaged(*const Biome).initCapacity(main.stackAllocator, caveBiomes.len);
	defer validBiomes.deinit(main.stackAllocator);
	const worldPos = CaveBiomeMapFragment.rotateInverse(.{map.pos.wx, map.pos.wy, map.pos.wz});
	for(caveBiomes) |*biome| {
		if(biome.minHeight < worldPos[2] +% CaveBiomeMapFragment.caveBiomeMapSize and biome.maxHeight > worldPos[2]) {
			validBiomes.appendAssumeCapacity(biome);
		}
	}
	if(validBiomes.items.len == 0) {
		std.log.warn("Couldn't find any cave biome on height {}. Using biome {s} instead.", .{worldPos[2], caveBiomes[0].id});
		validBiomes.appendAssumeCapacity(&caveBiomes[0]);
	}

	var seed = random.initSeed3D(worldSeed, .{map.pos.wx, map.pos.wy, map.pos.wz});
	var z: u31 = 0;
	while(z < CaveBiomeMapFragment.caveBiomeMapSize) : (z += CaveBiomeMapFragment.caveBiomeSize) {
		// Sort all biomes to the start that fit into the height region of the given z plane:
		var totalChance: f64 = 0;
		var insertionIndex: usize = 0;
		var i: usize = 0;
		while(i < validBiomes.items.len) : (i += 1) {
			if(validBiomes.items[i].minHeight < worldPos[2] + z + (CaveBiomeMapFragment.caveBiomeSize - 1) and validBiomes.items[i].maxHeight > worldPos[2] + z) {
				if(insertionIndex != i) {
					const swap = validBiomes.items[i];
					validBiomes.items[i] = validBiomes.items[insertionIndex];
					validBiomes.items[insertionIndex] = swap;
				}
				totalChance += validBiomes.items[insertionIndex].chance;
				insertionIndex += 1;
			}
		}
		if(totalChance == 0) {
			totalChance = 1;
		}
		var x: u31 = 0;
		while(x < CaveBiomeMapFragment.caveBiomeMapSize) : (x += CaveBiomeMapFragment.caveBiomeSize) {
			var y: u31 = 0;
			while(y < CaveBiomeMapFragment.caveBiomeMapSize) : (y += CaveBiomeMapFragment.caveBiomeSize) {
				for(0..2) |_map| {
					var randomValue = random.nextDouble(&seed)*totalChance;
					var biome: *const Biome = undefined;
					i = 0;
					while(true) {
						biome = validBiomes.items[i];
						i += 1;
						randomValue -= biome.chance;
						if(randomValue < 0) break;
					}
					const index = CaveBiomeMapFragment.getIndex(x, y, z);
					map.biomeMap[index][_map] = biome;
				}
			}
		}
	}
}