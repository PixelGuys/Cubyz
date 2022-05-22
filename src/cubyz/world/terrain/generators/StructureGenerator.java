package cubyz.world.terrain.generators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.terrain.CaveBiomeMap;
import cubyz.world.terrain.CaveMap;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.biomes.StructureModel;
import cubyz.world.terrain.noise.StaticBlueNoise;
import pixelguys.json.JsonObject;

/**
 * Used for small structures only.
 * Other structures(like rivers, caves, crystal caverns, …) should be created seperately.
 */

public class StructureGenerator implements Generator {

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "vegetation");
	}
	
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, CaveMap caveMap, CaveBiomeMap biomeMap) {
		FastRandom rand = new FastRandom(seed + 3*(seed + 1 & Integer.MAX_VALUE));
		long rand1 = rand.nextInt() | 1;
		long rand2 = rand.nextInt() | 1;
		long rand3 = rand.nextInt() | 1;
		int stepSize = chunk.voxelSize;
		if (stepSize < 4) {
			// Uses a blue noise pattern for all structure that shouldn't touch.
			int[] blueNoise = StaticBlueNoise.getRegionData(chunk.wx - 8, chunk.wz - 8, chunk.getWidth() + 16, chunk.getWidth() + 16);
			for(int coordinatePair : blueNoise) {
				int px = (coordinatePair >>> 16) - 8;
				int pz = (coordinatePair & 0xffff) - 8;
				int wpx = px + wx;
				int wpz = pz + wz;

				for(int py = -32; py <= chunk.getWidth(); py += 32) {
					int wpy = py + wy;
					rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ wpy*rand3 ^ seed);
					int relY = py + 16;

					if(caveMap.isSolid(px, relY, pz)) {
						relY = caveMap.findTerrainChangeAbove(px, pz, relY);
					} else {
						relY = caveMap.findTerrainChangeBelow(px, pz, relY) + chunk.voxelSize;
					}
					if(relY < py || relY >= py + 32) continue;
					Biome biome = biomeMap.getBiome(px, relY, pz);
					float randomValue = rand.nextFloat();
					for(StructureModel model : biome.vegetationModels) {
						float adaptedChance = model.getChance() * 16;
						if (adaptedChance > randomValue) {
							model.generate(px, pz, relY, chunk, caveMap, rand);
							break;
						} else {
							// Make sure that after the first one was considered all others get the correct chances.
							randomValue = (randomValue - adaptedChance)/(1 - adaptedChance);
						}
					}
				}
			}
		} else { // TODO: Make this case work with cave-structures. Low priority because caves aren't even generated this far out.
			for(int px = 0; px < chunk.getWidth() + 16; px += stepSize) {
				for(int pz = 0; pz < chunk.getWidth() + 16; pz += stepSize) {
					int wpx = px - 8 + wx;
					int wpz = pz - 8 + wz;
					// Make sure the coordinates are inside the resolution grid of the Regions internal array:
					wpx = wpx & ~(chunk.voxelSize - 1);
					wpz = wpz & ~(chunk.voxelSize - 1);

					int relY = (int)biomeMap.getSurfaceHeight(wpx, wpz) - wy;
					if(relY < -32 || relY >= chunk.getWidth() + 32) continue;
					
					rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
					float randomValue = rand.nextFloat();
					Biome biome = biomeMap.getBiome(px, relY, pz);
					for(StructureModel model : biome.vegetationModels) {
						float adaptedChance = model.getChance();
						if (stepSize != 1) {
							// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
							adaptedChance = 1 - (float)Math.pow(1 - adaptedChance, stepSize*stepSize);
						}
						if (adaptedChance > randomValue) {
							model.generate(px - 8, pz - 8, relY, chunk, caveMap, rand);
							break;
						} else {
							// Make sure that after the first one was considered all others get the correct chances.
							randomValue = (randomValue - adaptedChance)/(1 - adaptedChance);
						}
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x2026b65487da9226L;
	}
}
