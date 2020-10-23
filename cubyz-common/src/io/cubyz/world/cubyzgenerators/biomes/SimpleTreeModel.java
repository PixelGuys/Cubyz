package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.World;

/**
 * Creates a variety of different tree shapes.<br>
 * TODO: Add more!
 */

public class SimpleTreeModel extends StructureModel implements ReducedStructureModel {
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
	public void generate(int x, int z, int h, Chunk chunk, float[][] heightMap, Random rand) {
		if(h > 0) {
			int height = height0 + rand.nextInt(deltaHeight);
			switch(type) {
				case PYRAMID: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if(x >= 0 && x < 16 && z >= 0 && z < 16) {
						for (int i = 0; i < height; i++) {
							if(chunk.getBlockAt(x, h+i, z) != null && (!chunk.getBlockAt(x, h+i, z).isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk.rawAddBlock(x, h+i, z, (i == height-1) ? topWood : wood, (byte)0);
						}
					}
					
					// Position of the first block of leaves
					height = 3*height >> 1;
					for (int i = height/3; i < height; i++) {
						int j = (height - i)/2;
						for (int k = 1 - j; k < j; k++) {
							for (int l = 1 - j; l < j; l++) {
								if (x+k >= 0 && x+k < 16 && z+l >= 0 && z+l < 16) {
									if(chunk.getBlockAt(x+k, h+i, z+l) != null && (!chunk.getBlockAt(x+k, h+i, z+l).isDegradable() || leaves.isDegradable())) {
										continue;
									}
									chunk.rawAddBlock(x+k, h+i, z+l, leaves, (byte)0);
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
							if(chunk.getBlockAt(x, h+i, z) != null && (!chunk.getBlockAt(x, h+i, z).isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk.rawAddBlock(x, h+i, z, (i == height-1) ? topWood : wood, (byte)0);
						}
					}
					
					int leafRadius = 1 + height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					for (int i = -leafRadius; i < leafRadius; i++) {
						for (int ix = - leafRadius; ix <= leafRadius; ix++) {
							for (int iz = - leafRadius; iz <= leafRadius; iz++) {
								int dist = i*i + ix*ix + iz*iz;
								if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) {
									if (x+ix >= 0 && x+ix < 16 && z+iz >= 0 && z+iz < 16) {
										if(chunk.getBlockAt(x+ix, h+i+height-1, z+iz) != null && (!chunk.getBlockAt(x+ix, h+i+height-1, z+iz).isDegradable() || leaves.isDegradable())) {
											continue;
										}
										chunk.rawAddBlock(x+ix, h+i+height-1, z+iz, leaves, (byte)0);
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
							if(chunk.getBlockAt(x, h+i, z) != null && (!chunk.getBlockAt(x, h+i, z).isDegradable() || wood.isDegradable())) {
								continue;
							}
							chunk.rawAddBlock(x, h+i, z, (i == height-1) ? topWood : wood, (byte)0);
						}
					}
					
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					for (int ix = - leafRadius; ix <= leafRadius; ix++) {
						for (int iz = - leafRadius; iz <= leafRadius; iz++) {
							if (x+ix >= 0 && x+ix < 16 && z+iz >= 0 && z+iz < 16) {
								for (int i = leafRadius/2; i >= -leafRadius/2; i--) {
									int dist = ix*ix + iz*iz;
									// Bushes are wider than tall:
									dist += 4*i*i;
									if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) {
										if(chunk.getBlockAt(x+ix, h+i+height-1, z+iz) != null && (!chunk.getBlockAt(x+ix, h+i+height-1, z+iz).isDegradable() || leaves.isDegradable())) {
											continue;
										}
										chunk.rawAddBlock(x+ix, h+i+height-1, z+iz, leaves, (byte)0);
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

	@Override
	public void generate(int x, int z, int h, ReducedChunk chunk, MetaChunk metaChunk, Random rand) {
		if(h > 0) {
			int height = height0 + rand.nextInt(deltaHeight);
			switch(type) {
				case PYRAMID: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if((x & chunk.resolutionMask) == 0 && (z & chunk.resolutionMask) == 0) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.resolution) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood.color : wood.color);
						}
					}
					// Position of the first block of leaves
					height = 3*height >> 1;
					for(int py = chunk.startIndex(h + height/3); py < h + height; py += chunk.resolution) {
						int j = (height - (py - h))/2;
						for (int px = chunk.startIndex(x + 1 - j); px < x + j; px += chunk.resolution) {
							for (int pz = chunk.startIndex(z + 1 - j); pz < z + j; pz += chunk.resolution) {
								chunk.updateBlockIfAir(px, py, pz, leaves.color);
							}
						}
					}
					break;
				}
				case ROUND: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if((x & chunk.resolutionMask) == 0 && (z & chunk.resolutionMask) == 0) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.resolution) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood.color : wood.color);
						}
					}
					
					
					int leafRadius = 1 + height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
					for (int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.resolution) {
						for (int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.resolution) {
							for (int pz = chunk.startIndex(z - leafRadius); pz <= z + leafRadius; pz += chunk.resolution) {
								int dist = (py - center)*(py - center) + (px - x)*(px - x) + (pz - z)*(pz - z);
								if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfAir(px, py, pz, leaves.color);
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
					
					if((x & chunk.resolutionMask) == 0 && (z & chunk.resolutionMask) == 0) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.resolution) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood.color : wood.color);
						}
					}
					
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
					for (int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.resolution) {
						for (int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.resolution) {
							for (int pz = chunk.startIndex(z - leafRadius/2); pz <= z + leafRadius/2; pz += chunk.resolution) {
								int dist = (px - x)*(px - x) + (pz - z)*(pz - z);
								// Bushes are wider than tall:
								dist += 4*(py - center)*(py - center);
								if(dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfAir(px, py, pz, leaves.color);
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
