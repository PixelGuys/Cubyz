package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.Resource;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Chunk;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.World;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.StructureModel;

/**
 * Used for small structures only.
 * Other structures(like rivers, caves, crystal caverns, …) should be created seperately.
 */

public class StructureGenerator implements Generator, ReducedGenerator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_vegetation");
	}
	
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	@Override
	public void generate(long seed, int cx, int cz, NormalChunk chunk, MetaChunk containingMetaChunk, Surface surface, boolean[][] vegetationIgnoreMap) {
		int wx = cx << 4;
		int wz = cz << 4;
		this.generate(seed, wx, wz, chunk, containingMetaChunk, surface);
	}
	
	private void generate(long seed, int wx, int wz, Chunk chunk, MetaChunk containingMetaChunk, Surface surface) {
		Random rand = new Random(seed + 3*(seed + 1 & Integer.MAX_VALUE));
		int worldSize = surface.getSize();
		long rand1 = rand.nextInt() | 1;
		long rand2 = rand.nextInt() | 1;
		// Get the meta chunks for the surrounding regions:
		MetaChunk nn = containingMetaChunk;
		MetaChunk np = containingMetaChunk;
		MetaChunk pn = containingMetaChunk;
		MetaChunk pp = containingMetaChunk;
		MetaChunk no = containingMetaChunk;
		MetaChunk po = containingMetaChunk;
		MetaChunk on = containingMetaChunk;
		MetaChunk op = containingMetaChunk;
		if((wx & 255) <= 8) {
			no = nn = np = surface.getMetaChunk((wx & ~255) - 256, wz & ~255);
		}
		if((wx & 255) >= 256 - 8 - chunk.getWidth()) {
			po = pn = pp = surface.getMetaChunk((wx & ~255) + 256, wz & ~255);
		}
		if((wz & 255) <= 8) {
			on = surface.getMetaChunk((wx & ~255), (wz & ~255) - 256);
			nn = surface.getMetaChunk((wx & ~255) - ((wx & 255) <= 8 ? 256 : 0), (wz & ~255) - 256);
			pn = surface.getMetaChunk((wx & ~255) + ((wx & 255) >= 256 - 8 - chunk.getWidth() ? 256 : 0), (wz & ~255) - 256);
		}
		if((wz & 255) >= 256 - 8 - chunk.getWidth()) {
			op = surface.getMetaChunk((wx & ~255), (wz & ~255) + 256);
			np = surface.getMetaChunk((wx & ~255) - ((wx & 255) <= 8 ? 256 : 0), (wz & ~255) + 256);
			pp = surface.getMetaChunk((wx & ~255) + ((wx & 255) >= 256 - 8 - chunk.getWidth() ? 256 : 0), (wz & ~255) + 256);
		}
		for(int px = 0; px < chunk.getWidth() + 16; px++) {
			for(int pz = 0; pz < chunk.getWidth() + 16; pz++) {
				int wpx = CubyzMath.worldModulo(px - 8 + wx, worldSize);
				int wpz = CubyzMath.worldModulo(pz - 8 + wz, worldSize);
				rand.setSeed((wpx*rand1 << 32) ^ wpz*rand2 ^ seed);
				float randomValue = rand.nextFloat();
				MetaChunk cur = containingMetaChunk;
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
				Biome biome = cur.biomeMap[wpx & 255][wpz & 255];
				for(StructureModel model : biome.vegetationModels()) {
					if(model.getChance() > randomValue) {
						model.generate(px - 8, pz - 8, (int)(cur.heightMap[wpx & 255][wpz & 255]*World.WORLD_HEIGHT) + 1, chunk, containingMetaChunk, rand);
						break;
					} else {
						randomValue = (randomValue - model.getChance())/(1 - model.getChance()); // Make sure that after the first one was considered all others get the correct chances.
					}
				}
			}
		}
	}

	@Override
	public void generate(long seed, int wx, int wz, ReducedChunk chunk, MetaChunk containingMetaChunk, Surface surface) {
		this.generate(seed, wx, wz, (Chunk)chunk, containingMetaChunk, surface);
	}

	@Override
	public long getGeneratorSeed() {
		return 0x2026b65487da9226L;
	}
}
