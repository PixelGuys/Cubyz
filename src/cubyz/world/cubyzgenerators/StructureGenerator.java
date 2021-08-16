package cubyz.world.cubyzgenerators;

import java.util.Random;

import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.Surface;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.cubyzgenerators.biomes.StructureModel;
import cubyz.world.terrain.MapFragment;

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
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, Surface surface) {
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
			no = nn = np = surface.getMapFragment(wx - MapFragment.MAP_SIZE, wz, chunk.getVoxelSize());
		}
		if((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			po = pn = pp = surface.getMapFragment(wx + MapFragment.MAP_SIZE, wz, chunk.getVoxelSize());
		}
		if((wz & MapFragment.MAP_MASK) <= 8) {
			on = surface.getMapFragment(wx, wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
			nn = surface.getMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
			pn = surface.getMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz - MapFragment.MAP_SIZE, chunk.getVoxelSize());
		}
		if((wz & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth()) {
			op = surface.getMapFragment(wx, wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
			np = surface.getMapFragment(wx - ((wx & MapFragment.MAP_MASK) <= 8 ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
			pp = surface.getMapFragment(wx + ((wx & MapFragment.MAP_MASK) >= MapFragment.MAP_SIZE - 8 - chunk.getWidth() ? MapFragment.MAP_SIZE : 0), wz + MapFragment.MAP_SIZE, chunk.getVoxelSize());
		}
		for(int px = 0; px < chunk.getWidth() + 16; px++) {
			for(int pz = 0; pz < chunk.getWidth() + 16; pz++) {
				int wpx = px - 8 + wx;
				int wpz = pz - 8 + wz;
				rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
				// Make sure the coordinates are inside the resolution grid of the Regions internal array:
				wpx = wpx & ~(chunk.getVoxelSize() - 1);
				wpz = wpz & ~(chunk.getVoxelSize() - 1);
				
				float randomValue = rand.nextFloat();
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
