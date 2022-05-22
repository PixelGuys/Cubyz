package cubyz.world.terrain.biomes;

import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * Creates a variety of different tree shapes.<br>
 * TODO: Add more!
 */

public class SimpleTreeModel extends StructureModel {
	private enum Type { // TODO: More different types.
		PYRAMID,
		ROUND,
		BUSH,
	}
	Type type;
	int leaves, wood, topWood;
	int height0, deltaHeight;
	
	public SimpleTreeModel() {
		super(new Resource("cubyz", "simple_tree"), 0);
		leaves = 0;
		wood = 0;
		topWood = 0;
		height0 = 0;
		deltaHeight = 0;
		type = Type.ROUND;
	}

	public SimpleTreeModel(JsonObject json) {
		super(new Resource("cubyz", "simple_tree"), json.getFloat("chance", 0.5f));
		leaves = Blocks.getByID(json.getString("leaves", "cubyz:oak_leaves"));
		wood = Blocks.getByID(json.getString("log", "cubyz:oak_log"));
		topWood = Blocks.getByID(json.getString("top", "cubyz:oak_top"));
		height0 = json.getInt("height", 6);
		deltaHeight = json.getInt("height_variation", 3);
		type = Type.valueOf(json.getString("type", "round").toUpperCase());
	}

	@Override
	public void generate(int x, int z, int y, Chunk chunk, CaveMap map, FastRandom rand) {
		int height = height0 + rand.nextInt(deltaHeight);

		if(y + height >= map.findTerrainChangeAbove(x, z, y)) // Space is too small.
			return;
		
		if (chunk.voxelSize >= 16) {
			// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
			if (chunk.liesInChunk(x, y, z)) {
				chunk.updateBlockIfDegradable(x, y, z, leaves);
			}
			if (chunk.liesInChunk(x, y + chunk.voxelSize, z)) {
				chunk.updateBlockIfDegradable(x, y + chunk.voxelSize, z, leaves);
			}
			return;
		}
		
		if (y < chunk.getWidth()) {
			switch(type) {
				case PYRAMID: {
					if (chunk.voxelSize <= 2) {
						for(int py = chunk.startIndex(y); py < y + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == y + height-1) ? topWood : wood);
							}
						}
					}
					// Position of the first block of leaves
					height = 3*height >> 1;
					for(int py = chunk.startIndex(y + height/3); py < y + height; py += chunk.voxelSize) {
						int j = (height - (py - y))/2;
						for(int px = chunk.startIndex(x + 1 - j); px < x + j; px += chunk.voxelSize) {
							for(int pz = chunk.startIndex(z + 1 - j); pz < z + j; pz += chunk.voxelSize) {
								if (chunk.liesInChunk(px, py, pz))
									chunk.updateBlockIfDegradable(px, py, pz, leaves);
							}
						}
					}
					break;
				}
				case ROUND: {
					if (chunk.voxelSize <= 2) {
						for(int py = chunk.startIndex(y); py < y + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == y + height-1) ? topWood : wood);
							}
						}
					}
					
					
					int leafRadius = 1 + height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = y + height;
					for(int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.voxelSize) {
						for(int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.voxelSize) {
							for(int pz = chunk.startIndex(z - leafRadius); pz <= z + leafRadius; pz += chunk.voxelSize) {
								int dist = (py - center)*(py - center) + (px - x)*(px - x) + (pz - z)*(pz - z);
								if (chunk.liesInChunk(px, py, pz) && dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfDegradable(px, py, pz, leaves);
								}
							}
						}
					}
					break;
				}
				case BUSH: {
					int oldHeight = height;
					if (height > 2) height = 2; // Make sure the stem of the bush stays small.

					if (chunk.voxelSize <= 2) {
						for(int py = chunk.startIndex(y); py < y + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == y + height-1) ? topWood : wood);
							}
						}
					}
					
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = y + height;
					for (int py = chunk.startIndex(center - leafRadius); py < center + leafRadius; py += chunk.voxelSize) {
						for (int px = chunk.startIndex(x - leafRadius); px <= x + leafRadius; px += chunk.voxelSize) {
							for (int pz = chunk.startIndex(z - leafRadius/2); pz <= z + leafRadius/2; pz += chunk.voxelSize) {
								int dist = (px - x)*(px - x) + (pz - z)*(pz - z);
								// Bushes are wider than tall:
								dist += 4*(py - center)*(py - center);
								if (chunk.liesInChunk(px, py, pz) && dist < (floatLeafRadius)*(floatLeafRadius) && (dist < (floatLeafRadius - 0.25f)*(floatLeafRadius - 0.25f) || rand.nextInt(2) != 0)) { // TODO: Use another seed to make this more reliable!
									chunk.updateBlockIfDegradable(px, py, pz, leaves);
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
	public StructureModel loadStructureModel(JsonObject json) {
		return new SimpleTreeModel(json);
	}
}
