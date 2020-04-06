package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.World;

// One position vegetation, like grass or cactus.

public class SimpleVegetation implements VegetationModel {
	Block block;
	float chance;
	int height0, deltaHeight;
	public SimpleVegetation(Block block, float chance, int h0, int dh) {
		this.block = block;
		this.chance = chance;
		height0 = h0;
		deltaHeight = dh;
	}
	@Override
	public boolean considerCoordinates(int x, int y, int h, Block[][][] chunk, float random) {
		if(chance > random && h > 0 && x >= 0 && x < 16 && y >= 0 && y < 16) {
			int height = height0;
			if(h+height < World.WORLD_HEIGHT) {
				if(deltaHeight != 0)
					height += + new Random((long)(x*random*549264290 + y*(1-random)*57285843)).nextInt(deltaHeight);
				for(int dh = 0; dh < height; dh++)
					chunk[x][y][h+dh] = block;
				return true;
			}
		}
		return false;
	}
}
