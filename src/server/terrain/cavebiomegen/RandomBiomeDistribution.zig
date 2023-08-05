const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn generate(map: *CaveBiomeMapFragment, worldSeed: u64) Allocator.Error!void {
	// Select all the biomes that are within the given height range.
	var validBiomes = try std.ArrayListUnmanaged(*const Biome).initCapacity(main.threadAllocator, caveBiomes.len);
	defer validBiomes.deinit(main.threadAllocator);
	for(caveBiomes) |*biome| {
		if(biome.minHeight < map.pos.wy +% CaveBiomeMapFragment.caveBiomeMapSize and biome.maxHeight > map.pos.wy) {
			validBiomes.appendAssumeCapacity(biome);
		}
	}
	if(validBiomes.items.len == 0) {
		std.log.warn("Couldn't find any cave biome on height {}. Using biome {s} instead.", .{map.pos.wy, caveBiomes[0].id});
		validBiomes.appendAssumeCapacity(&caveBiomes[0]);
	}

	var seed = random.initSeed3D(worldSeed, .{map.pos.wx, map.pos.wy, map.pos.wz});
	var y: u31 = 0;
	while(y < CaveBiomeMapFragment.caveBiomeMapSize) : (y += CaveBiomeMapFragment.caveBiomeSize) {
		// Sort all biomes to the start that fit into the height region of the given y plane:
		var totalChance: f64 = 0;
		var insertionIndex: usize = 0;
		var i: usize = 0;
		while(i < validBiomes.items.len) : (i += 1) {
			if(validBiomes.items[i].minHeight < map.pos.wy +% y +% CaveBiomeMapFragment.caveBiomeSize and validBiomes.items[i].maxHeight > map.pos.wy +% y) {
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
			var z: u31 = 0;
			while(z < CaveBiomeMapFragment.caveBiomeMapSize) : (z += CaveBiomeMapFragment.caveBiomeSize) {
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
					var index = CaveBiomeMapFragment.getIndex(x, y, z);
					map.biomeMap[index][_map] = biome;
				}
			}
		}
	}
}