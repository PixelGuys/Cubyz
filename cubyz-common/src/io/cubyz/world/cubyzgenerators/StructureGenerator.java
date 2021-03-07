package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.Resource;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.Chunk;
import io.cubyz.world.Region;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.StructureModel;

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
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, Region containingRegion, Surface surface) {
		Random rand = new Random(seed + 3*(seed + 1 & Integer.MAX_VALUE));
		int worldSizeX = surface.getSizeX();
		int worldSizeZ = surface.getSizeZ();
		long rand1 = rand.nextInt() | 1;
		long rand2 = rand.nextInt() | 1;
		// Get the regions for the surrounding regions:
		Region nn = containingRegion;
		Region np = containingRegion;
		Region pn = containingRegion;
		Region pp = containingRegion;
		Region no = containingRegion;
		Region po = containingRegion;
		Region on = containingRegion;
		Region op = containingRegion;
		if((wx & Region.regionMask) <= 8) {
			no = nn = np = surface.getRegion(wx - Region.regionSize, wz, chunk.getVoxelSize());
		}
		if((wx & Region.regionMask) >= Region.regionSize - 8 - chunk.getWidth()) {
			po = pn = pp = surface.getRegion(wx + Region.regionSize, wz, chunk.getVoxelSize());
		}
		if((wz & Region.regionMask) <= 8) {
			on = surface.getRegion(wx, wz - Region.regionSize, chunk.getVoxelSize());
			nn = surface.getRegion(wx - ((wx & Region.regionMask) <= 8 ? Region.regionSize : 0), wz - Region.regionSize, chunk.getVoxelSize());
			pn = surface.getRegion(wx + ((wx & Region.regionMask) >= Region.regionSize - 8 - chunk.getWidth() ? Region.regionSize : 0), wz - Region.regionSize, chunk.getVoxelSize());
		}
		if((wz & Region.regionMask) >= Region.regionSize - 8 - chunk.getWidth()) {
			op = surface.getRegion(wx, wz + Region.regionSize, chunk.getVoxelSize());
			np = surface.getRegion(wx - ((wx & Region.regionMask) <= 8 ? Region.regionSize : 0), wz + Region.regionSize, chunk.getVoxelSize());
			pp = surface.getRegion(wx + ((wx & Region.regionMask) >= Region.regionSize - 8 - chunk.getWidth() ? Region.regionSize : 0), wz + Region.regionSize, chunk.getVoxelSize());
		}
		for(int px = 0; px < chunk.getWidth() + 16; px++) {
			for(int pz = 0; pz < chunk.getWidth() + 16; pz++) {
				int wpx = CubyzMath.worldModulo(px - 8 + wx, worldSizeX);
				int wpz = CubyzMath.worldModulo(pz - 8 + wz, worldSizeZ);
				rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
				// Make sure the coordinates are inside the resolution grid of the Regions internal array:
				wpx = wpx & ~(chunk.getVoxelSize() - 1);
				wpz = wpz & ~(chunk.getVoxelSize() - 1);
				
				float randomValue = rand.nextFloat();
				Region cur = containingRegion;
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
						model.generate(px - 8, pz - 8, (int)cur.getHeight(wpx, wpz) + 1, chunk, containingRegion, rand);
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
