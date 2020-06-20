package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.World;

// One position vegetation, like grass or cactus.

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
	public void generate(int x, int z, int h, Block[][][] chunk, int[][] heightMap, Random rand) {
		if(h > 0 && x >= 0 && x < 16 && z >= 0 && z < 16) {
			int height = height0;
			if(h+height < World.WORLD_HEIGHT) {
				if(deltaHeight != 0)
					height += rand.nextInt(deltaHeight);
				for(int dh = 0; dh < height; dh++)
					chunk[x][z][h+dh] = block;
			}
		}
	}
}
