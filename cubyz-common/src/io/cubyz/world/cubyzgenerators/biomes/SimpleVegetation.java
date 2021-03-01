package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.Region;
import io.cubyz.world.World;

/**
 * One position vegetation, like grass or cactus.
 */

public class SimpleVegetation extends StructureModel {
	Block block;
	int height0, deltaHeight;
	public SimpleVegetation(Block block, float chance, int h0, int dh) {
		super(chance);
		this.block = block;
		height0 = h0;
		deltaHeight = dh;
	}
	@Override
	public void generate(int x, int z, int h, Chunk chunk, Region region, Random rand) {
		int y = chunk.getWorldY();
		if(chunk.liesInChunk(x, h-y, z)) {
			int height = height0;
			if(h+height < World.WORLD_HEIGHT) {
				if(deltaHeight != 0)
					height += rand.nextInt(deltaHeight);
				for(int py = chunk.startIndex(h); py < h + height; py += chunk.getVoxelSize()) {
					if(chunk.liesInChunk(x, py-y, z)) {
						chunk.updateBlockIfAir(x, py-y, z, block);
					}
				}
			}
		}
	}
}
