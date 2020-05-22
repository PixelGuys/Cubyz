package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.World;

public class SimpleTreeModel extends StructureModel {
	Block leaves, wood, topWood;
	int height0, deltaHeight;
	
	public SimpleTreeModel(Block leaves, Block wood, Block topWood, float chance, int h0, int dh) {
		super(chance);
		this.leaves = leaves;
		this.wood = wood;
		this.topWood = topWood;
		height0 = h0;
		deltaHeight = dh;
	}

	@Override
	public void generate(int x, int y, int h, Block[][][] chunk, float random) {
		if(h > 0) {
			int height = height0 + new Random(Float.floatToRawIntBits(random)).nextInt(deltaHeight);
			if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
				return;
			
			if(x >= 0 && x < 16 && y >= 0 && y < 16) {
				for (int i = 0; i < height; i++) {
					if(chunk[x][y][h+i] != null && (!chunk[x][y][h+i].isDegradable() || wood.isDegradable())) {
						continue;
					}
					chunk[x][y][h+i] = (i == height-1) ? topWood : wood;
				}
			}
			
			//Position of the first block of leaves
			height = 3 * height >> 1;
			for (int i = height / 3; i < height; i++) {
				int j = (height - i) >> 1;
				for (int k = 1 - j; k < j; k++) {
					for (int l = 1 - j; l < j; l++) {
						if (x+k >= 0 && x+k < 16 && y+l >= 0 && y+l < 16) {
							if(chunk[x+k][y+l][h+i] != null && (!chunk[x+k][y+l][h+i].isDegradable() || leaves.isDegradable())) {
								continue;
							}
							chunk[x+k][y+l][h+i] = leaves;
						}
					}
				}
			}
		}
	}
}
