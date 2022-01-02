package cubyz.world.terrain.generators;

import java.util.Random;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.ChunkManager;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.biomes.StructureModel;
import cubyz.world.terrain.noise.StaticBlueNoise;

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
		return new Resource("cubyz", "lifeland_vegetation");
	}
	
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	private static MapFragment getMapFragment(MapFragment map, MapFragment nn, MapFragment np, MapFragment pn, MapFragment pp, MapFragment no, MapFragment po, MapFragment on, MapFragment op, int px, int pz, int width) {
		if (px < 8) {
			if (pz < 8) return nn;
			if (width + 16 - pz <= 8) return np;
			return no;
		}
		if (width + 16 - px <= 8) {
			if (pz < 8) return pn;
			if (width + 16 - pz <= 8) return pp;
			return po;
		}
		if (pz < 8) return on;
		if (width + 16 - pz <= 8) return op;
		return map;
	}

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ChunkManager generator) {
		Random rand = new Random(seed + 3*(seed + 1 & Integer.MAX_VALUE));
		long rand1 = rand.nextInt() | 1;
		long rand2 = rand.nextInt() | 1;
		// Get the regions for the surrounding regions:
		MapFragment nn = map;
		MapFragment np = map;
		MapFragment pn = map;
		MapFragment pp = map;
		MapFragment no = map;
		MapFragment po = map;
		MapFragment on = map;
		MapFragment op = map;
		if ((wx & MapFragment.MAP_MASK) <= 8) {
			no = nn = np = generator.getOrGenerateMapFragment(wx - MapFragment.MAP_SIZE, wz, chunk.voxelSize);
		}
		if ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			po = pn = pp = generator.getOrGenerateMapFragment(wx + MapFragment.MAP_SIZE, wz, chunk.voxelSize);
		}
		if ((wz & MapFragment.MAP_MASK) <= 8) {
			on = generator.getOrGenerateMapFragment(wx, wz - MapFragment.MAP_SIZE, chunk.voxelSize);
			nn = generator.getOrGenerateMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.voxelSize);
			pn = generator.getOrGenerateMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.voxelSize);
		}
		if ((wz & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			op = generator.getOrGenerateMapFragment(wx, wz + MapFragment.MAP_SIZE, chunk.voxelSize);
			np = generator.getOrGenerateMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.voxelSize);
			pp = generator.getOrGenerateMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.voxelSize);
		}
		int stepSize = chunk.voxelSize;
		if (stepSize < 4) {
			// Uses a blue noise pattern for all structure that shouldn't touch.
			int[] blueNoise = StaticBlueNoise.getRegionData(chunk.wx - 8, chunk.wz - 8, chunk.getWidth() + 16, chunk.getWidth() + 16);
			for(int coordinatePair : blueNoise) {
				int px = coordinatePair >>> 16;
				int pz = coordinatePair & 0xffff;
				int wpx = px - 8 + wx;
				int wpz = pz - 8 + wz;
				rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
				// Make sure the coordinates are inside the resolution grid of the Regions internal array:
				wpx = wpx & ~(chunk.voxelSize - 1);
				wpz = wpz & ~(chunk.voxelSize - 1);

				float randomValue = rand.nextFloat();
				MapFragment cur = getMapFragment(map, nn, np, pn, pp, no, po, on, op, px, pz, chunk.getWidth());
				Biome biome = cur.getBiome(wpx, wpz);
				for(StructureModel model : biome.vegetationModels) {
					float adaptedChance = model.getChance() * 16;
					if (adaptedChance > randomValue) {
						model.generate(px - 8, pz - 8, (int)cur.getHeight(wpx, wpz) + 1, chunk, map, rand);
						break;
					} else {
						// Make sure that after the first one was considered all others get the correct chances.
						randomValue = (randomValue - adaptedChance)/(1 - adaptedChance);
					}
				}
			}
		} else {
			for(int px = 0; px < chunk.getWidth() + 16; px += stepSize) {
				for(int pz = 0; pz < chunk.getWidth() + 16; pz += stepSize) {
					int wpx = px - 8 + wx;
					int wpz = pz - 8 + wz;
					rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
					// Make sure the coordinates are inside the resolution grid of the Regions internal array:
					wpx = wpx & ~(chunk.voxelSize - 1);
					wpz = wpz & ~(chunk.voxelSize - 1);
					
					float randomValue = rand.nextFloat();
					MapFragment cur = getMapFragment(map, nn, np, pn, pp, no, po, on, op, px, pz, chunk.getWidth());
					Biome biome = cur.getBiome(wpx, wpz);
					for(StructureModel model : biome.vegetationModels) {
						float adaptedChance = model.getChance();
						if (stepSize != 1) {
							// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
							adaptedChance = 1 - (float)Math.pow(1 - adaptedChance, stepSize*stepSize);
						}
						if (adaptedChance > randomValue) {
							model.generate(px - 8, pz - 8, (int)cur.getHeight(wpx, wpz) + 1, chunk, map, rand);
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
