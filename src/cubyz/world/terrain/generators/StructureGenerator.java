package cubyz.world.terrain.generators;

import java.util.Random;

import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.biomes.StructureModel;

/**
 * Used for small structures only.
 * Other structures(like rivers, caves, crystal caverns, …) should be created seperately.
 */

public class StructureGenerator implements Generator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_vegetation");
	}
	
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ServerWorld world) {
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
		if((wx & MapFragment.MAP_MASK) <= 8) {
			no = nn = np = world.getMapFragment(wx - MapFragment.MAP_SIZE, wz, chunk.getVoxelSize());
		}
		if((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			po = pn = pp = world.getMapFragment(wx + MapFragment.MAP_SIZE, wz, chunk.getVoxelSize());
		}
		if((wz & MapFragment.MAP_MASK) <= 8) {
			on = world.getMapFragment(wx, wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
			nn = world.getMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
			pn = world.getMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
		}
		if((wz & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			op = world.getMapFragment(wx, wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
			np = world.getMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
			pp = world.getMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
		}
		int stepSize = Math.max(1, chunk.voxelSize/2);
		for(int px = 0; px < chunk.getWidth() + 16; px += stepSize) {
			for(int pz = 0; pz < chunk.getWidth() + 16; pz += stepSize) {
				int wpx = px - 8 + wx;
				int wpz = pz - 8 + wz;
				rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
				// Make sure the coordinates are inside the resolution grid of the Regions internal array:
				wpx = wpx & ~(chunk.getVoxelSize() - 1);
				wpz = wpz & ~(chunk.getVoxelSize() - 1);
				
				float randomValue = rand.nextFloat();
				if(stepSize != 1) {
					// Increase chance if there are less spawn points considered. Messes up probabilities, but it's too far away to really matter.
					randomValue = (float)Math.pow(randomValue, stepSize);
				}
				MapFragment cur = map;
				if(px < 8) {
					if(pz < 8) cur = nn;
					else if(chunk.getWidth() + 16 - pz <= 8) cur = np;
					else cur = no;
				} else if(chunk.getWidth() + 16 - px <= 8) {
					if(pz < 8) cur = pn;
					else if(chunk.getWidth() + 16 - pz <= 8) cur = pp;
					else cur = po;
				} else {
					if(pz < 8) cur = on;
					else if(chunk.getWidth() + 16 - pz <= 8) cur = op;
				}
				Biome biome = cur.getBiome(wpx, wpz);
				for(StructureModel model : biome.vegetationModels) {
					if(model.getChance() > randomValue) {
						model.generate(px - 8, pz - 8, (int)cur.getHeight(wpx, wpz) + 1, chunk, map, rand);
						break;
					} else {
						randomValue = (randomValue - model.getChance())/(1 - model.getChance()); // Make sure that after the first one was considered all others get the correct chances.
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
