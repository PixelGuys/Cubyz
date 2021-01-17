package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.Region;
import io.cubyz.world.World;

/**
 * Creates a variety of different tree shapes.<br>
 * TODO: Add more!
 */

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
	public void generate(int x, int z, int h, Chunk chunk, Region region, Random rand) {
		if(h > 0) {
			int height = height0 + rand.nextInt(deltaHeight);
			switch(type) {
				case PYRAMID: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if(chunk.liesInChunk(x, z)) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.getVoxelSize()) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood : wood);
						}
					}
					// Position of the first block of leaves
					height = 3*height >> 1;
					for(int py = chunk.startIndex(h + height/3); py < h + height; py += chunk.getVoxelSize()) {
						int j = (height - (py - h))/2;
						for (int px = chunk.startIndex(x + 1 - j); px < x + j; px += chunk.getVoxelSize()) {
							for (int pz = chunk.startIndex(z + 1 - j); pz < z + j; pz += chunk.getVoxelSize()) {
								if(chunk.liesInChunk(px, pz))
									chunk.updateBlockIfAir(px, py, pz, leaves);
							}
						}
					}
					break;
				}
				case ROUND: {
					if(h+height+1 >= World.WORLD_HEIGHT) // the max array index is 255 but world height is 256 (for array **length**)
						return;
					
					if(chunk.liesInChunk(x, z)) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.getVoxelSize()) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood : wood);
						}
					}
					
					
					int leafRadius = 1 + height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
					for (int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.getVoxelSize()) {
						for (int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.getVoxelSize()) {
							for (int pz = chunk.startIndex(z - leafRadius); pz <= z + leafRadius; pz += chunk.getVoxelSize()) {
								int dist = (py - center)*(py - center) + (px - x)*(px - x) + (pz - z)*(pz - z);
								if(chunk.liesInChunk(px, pz) && chunk.liesInChunk(py) && dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfAir(px, py, pz, leaves);
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
					
					if(chunk.liesInChunk(x, z)) {
						for (int y = chunk.startIndex(h); y < h + height; y += chunk.getVoxelSize()) {
							chunk.updateBlockIfAir(x, y, z, (y == height-1) ? topWood : wood);
						}
					}
					
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
					for (int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.getVoxelSize()) {
						for (int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.getVoxelSize()) {
							for (int pz = chunk.startIndex(z - leafRadius/2); pz <= z + leafRadius/2; pz += chunk.getVoxelSize()) {
								int dist = (px - x)*(px - x) + (pz - z)*(pz - z);
								// Bushes are wider than tall:
								dist += 4*(py - center)*(py - center);
								if(chunk.liesInChunk(px, pz) && dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfAir(px, py, pz, leaves);
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
