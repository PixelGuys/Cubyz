package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.World;

/**
 * One position vegetation, like grass or cactus.
 */

public class SimpleVegetation extends StructureModel implements ReducedStructureModel {
	Block block;
	int height0, deltaHeight;
	public SimpleVegetation(Block block, float chance, int h0, int dh) {
		super(chance);
		this.block = block;
		height0 = h0;
		deltaHeight = dh;
	}
	@Override
	public void generate(int x, int z, int h, Chunk chunk, float[][] heightMap, Random rand) {
		if(h > 0 && x >= 0 && x < 16 && z >= 0 && z < 16) {
			int height = height0;
			if(h+height < World.WORLD_HEIGHT) {
				if(deltaHeight != 0)
					height += rand.nextInt(deltaHeight);
				for(int dh = 0; dh < height; dh++)
					chunk.rawAddBlock(x, h+dh, z, block);
			}
		}
	}
	@Override
	public void generate(int x, int z, int h, ReducedChunk chunk, MetaChunk metaChunk, Random rand) {
		if((x & chunk.resolutionMask) == 0 && (z & chunk.resolutionMask) == 0) {
			int height = height0;
			if(h+height < World.WORLD_HEIGHT) {
				if(deltaHeight != 0)
					height += rand.nextInt(deltaHeight);
				for(int py = chunk.startIndex(h); py < h + height; py += chunk.resolution)
					chunk.updateBlockIfAir(x, py, z, block.color);
			}
		}
	}
}
