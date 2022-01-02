package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.MapFragment;

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
	public void generate(int x, int z, int h, Chunk chunk, MapFragment map, Random rand) {
		int y = chunk.wy;
		h -= y;
		int height = height0 + rand.nextInt(deltaHeight);
		
		if (chunk.voxelSize >= 16) {
			// Ensures that even at lowest resolution some leaves are rendered for smaller trees.
			if (chunk.liesInChunk(x, h, z)) {
				chunk.updateBlockIfDegradable(x, h, z, leaves);
			}
			if (chunk.liesInChunk(x, h + chunk.voxelSize, z)) {
				chunk.updateBlockIfDegradable(x, h + chunk.voxelSize, z, leaves);
			}
			return;
		}
		
		if (h < chunk.getWidth()) {
			switch(type) {
				case PYRAMID: {
					if (chunk.voxelSize <= 2) {
						for(int py = chunk.startIndex(h); py < h + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == h + height-1) ? topWood : wood);
							}
						}
					}
					// Position of the first block of leaves
					height = 3*height >> 1;
					for(int py = chunk.startIndex(h + height/3); py < h + height; py += chunk.voxelSize) {
						int j = (height - (py - h))/2;
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
						for(int py = chunk.startIndex(h); py < h + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == h + height-1) ? topWood : wood);
							}
						}
					}
					
					
					int leafRadius = 1 + height/2;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
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
						for(int py = chunk.startIndex(h); py < h + height; py += chunk.voxelSize) {
							if (chunk.liesInChunk(x, py, z)) {
								chunk.updateBlockIfDegradable(x, py, z, (py == h + height-1) ? topWood : wood);
							}
						}
					}
					
					int leafRadius = oldHeight/2 + 1;
					float floatLeafRadius = leafRadius - rand.nextFloat();
					int center = h + height;
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
