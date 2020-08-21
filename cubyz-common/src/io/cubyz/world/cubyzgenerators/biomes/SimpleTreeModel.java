package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.World;

public class SimpleTreeModel extends StructureModel {
	private enum Type { // TODO: More different types and type access through biome addon files.
		PYRAMID,
		ROUND,
		BUSH,
	}
	Type type;
	Block leaves, wood, topWood;
	int height0, deltaHeight;
	
	public SimpleTreeModel(Block leaves, Block wood, Block topWood, float chance, int h0, int dh, String type) {
		super(chance);
		this.leaves = leaves;
		this.wood = wood;
		this.topWood = topWood;
		height0 = h0;
		deltaHeight = dh;
		this.type = Type.valueOf(type);
	}

	@Override
	public void generate(int x, int z, int h, Block[][][] chunk, float[][] heightMap, Random rand) {
		if(h > 0) {
			int height = height0 + rand.nextInt(deltaHeight);
			switch(type) {
				case PYRAMID: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if(x >= 0 && x < 16 && z >= 0 && z < 16) {
						for (int i = 0; i < height; i++) {
							if(chunk[x][z][h+i] != null && (!chunk[x][z][h+i].isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk[x][z][h+i] = (i == height-1) ? topWood : wood;
						}
					}
					
					//Position of the first block of leaves
					height = 3*height >> 1;
					for (int i = height/3; i < height; i++) {
						int j = (height - i) >> 1;
						for (int k = 1 - j; k < j; k++) {
							for (int l = 1 - j; l < j; l++) {
								if (x+k >= 0 && x+k < 16 && z+l >= 0 && z+l < 16) {
									if(chunk[x+k][z+l][h+i] != null && (!chunk[x+k][z+l][h+i].isDegradable() || leaves.isDegradable())) {
										continue;
									}
									chunk[x+k][z+l][h+i] = leaves;
								}
							}
						}
					}
					break;
				}
				case ROUND: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if(x >= 0 && x < 16 && z >= 0 && z < 16) {
						for (int i = 0; i < height; i++) {
							if(chunk[x][z][h+i] != null && (!chunk[x][z][h+i].isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk[x][z][h+i] = (i == height-1) ? topWood : wood;
						}
					}
					int leafRadius = 1+height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					for (int i = -leafRadius; i < leafRadius; i++) {
						for (int ix = - leafRadius; ix <= leafRadius; ix++) {
							for (int iz = - leafRadius; iz <= leafRadius; iz++) {
								int dist = i*i + ix*ix + iz*iz;
								if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) {
									if (x+ix >= 0 && x+ix < 16 && z+iz >= 0 && z+iz < 16) {
										if(chunk[x+ix][z+iz][h+i+height-1] != null && (!chunk[x+ix][z+iz][h+i+height-1].isDegradable() || leaves.isDegradable())) {
											continue;
										}
										chunk[x+ix][z+iz][h+i+height-1] = leaves;
									}
								}
							}
						}
					}
					break;
				}
				case BUSH: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					int oldHeight = height;
					if(height > 2) height = 2; // Make sure the stem of the bush stays small.
					if(x >= 0 && x < 16 && z >= 0 && z < 16) {
						for (int i = 0; i < height; i++) {
							if(chunk[x][z][h+i] != null && (!chunk[x][z][h+i].isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk[x][z][h+i] = (i == height-1) ? topWood : wood;
						}
					}
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					for (int ix = - leafRadius; ix <= leafRadius; ix++) {
						for (int iz = - leafRadius; iz <= leafRadius; iz++) {
							if (x+ix >= 0 && x+ix < 16 && z+iz >= 0 && z+iz < 16) {
								for (int i = leafRadius/2; i+h >= 0 && chunk[x+ix][z+iz][h+i+height-1] == null; i--) {
									int dist = ix*ix + iz*iz;
									// Bushes are wider than tall and always reach onto the ground:
									if(i > 0)
										dist += 4*i*i;
									if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) {
										if(chunk[x+ix][z+iz][h+i+height-1] != null && (!chunk[x+ix][z+iz][h+i+height-1].isDegradable() || leaves.isDegradable())) {
											continue;
										}
										chunk[x+ix][z+iz][h+i+height-1] = leaves;
									}
								}
							}
						}
					}
					break;
				}
			}
		}
	}
}
