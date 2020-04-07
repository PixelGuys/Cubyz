package io.cubyz.world.cubyzgenerators;

import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.Noise;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.VegetationModel;

public class VegetationGenerator implements FancyGenerator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_vegetation");
	}
	
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	@Override
	public void generate(long seed, int cx, int cy, Block[][][] chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, int[][] heightMap, Biome[][] biomeMap) {
		int wx = cx << 4;
		int wy = cy << 4;
		
		float[][] vegetationMap = Noise.generateRandomMap(wx-8, wy-8, 32, 32, seed + 3*(seed + 1 & Integer.MAX_VALUE));
		// Go through all positions in this and ±½ chunks to determine if there is a tree and if yes generate it.
		for(int px = 0; px < 32; px++) {
			for(int py = 0; py < 32; py++) {
				if(!vegetationIgnoreMap[px][py]) {
					for(VegetationModel model : biomeMap[px][py].vegetationModels()) {
						if(model.considerCoordinates(px-8, py-8, heightMap[px][py]+1, chunk, vegetationMap[px][py])) {
							break;
						}
					}
				}
			}
		}
	}

}
