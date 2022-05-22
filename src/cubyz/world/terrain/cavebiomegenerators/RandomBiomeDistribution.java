package cubyz.world.terrain.cavebiomegenerators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.utils.Logger;
import cubyz.utils.datastructures.RandomList;
import cubyz.utils.datastructures.SimpleList;
import cubyz.world.terrain.CaveBiomeMapFragment;
import cubyz.world.terrain.biomes.Biome;
import pixelguys.json.JsonObject;

public class RandomBiomeDistribution implements CaveBiomeGenerator {
	private RandomList<Biome> caveBiomes;

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:random_biome");
	}

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		caveBiomes = registries.biomeRegistry.byTypeBiomes.get(Biome.Type.CAVE);
	}

	@Override
	public int getPriority() {
		return 1024;
	}

	@Override
	public long getGeneratorSeed() {
		return 765893678349L;
	}

	@Override
	public void generate(long seed, CaveBiomeMapFragment map) {
		// Select all the biomes that are within the given height range.
		SimpleList<Biome> validBiomes = new SimpleList<>(new Biome[caveBiomes.size()]);
		caveBiomes.forEach((biome) -> {
			if(biome.minHeight < map.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE && biome.maxHeight > map.wy) {
				validBiomes.add(biome);
			}
		});
		if(validBiomes.size == 0) {
			Logger.warning("Couldn't find any cave biome on height " + map.wy);
			validBiomes.add(caveBiomes.get(0));
		}

		FastRandom rand = new FastRandom(seed);
		long rand1 = rand.nextLong() | 1;
		long rand2 = rand.nextLong() | 1;
		long rand3 = rand.nextLong() | 1;
		rand.setSeed(map.wx*rand1 ^ map.wy*rand2 ^ map.wz*rand3);
		for(int y = 0; y < CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE; y += CaveBiomeMapFragment.CAVE_BIOME_SIZE) {
			// Sort all biomes to the start that fit into the height region of the given y plane:
			long totalChance = 0;
			int insertionIndex = 0;
			for(int i = 0; i < validBiomes.size; i++) {
				if(validBiomes.array[i].minHeight < map.wy + y + CaveBiomeMapFragment.CAVE_BIOME_SIZE && validBiomes.array[i].maxHeight > map.wy + y) {
					if(insertionIndex != i) {
						Biome swap = validBiomes.array[i];
						validBiomes.array[i] = validBiomes.array[insertionIndex];
						validBiomes.array[insertionIndex] = swap;
					}
					totalChance += validBiomes.array[insertionIndex].chance;
					insertionIndex++;
				}
			}
			if(totalChance == 0) {
				totalChance = 1;
			}

			for(int x = 0; x < CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE; x += CaveBiomeMapFragment.CAVE_BIOME_SIZE) {
				for(int z = 0; z < CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE; z += CaveBiomeMapFragment.CAVE_BIOME_SIZE) {
					int index = CaveBiomeMapFragment.getIndex(x, y, z);
					long randomValue = RandomList.rangedRandomLong(rand, totalChance);
					Biome biome;
					int i = 0;
					do {
						biome = validBiomes.array[i++];
						randomValue -= biome.chance;
					} while(randomValue >= 0);
					map.biomeMap[index] = biome;
				}
			}
		}
	}
}
