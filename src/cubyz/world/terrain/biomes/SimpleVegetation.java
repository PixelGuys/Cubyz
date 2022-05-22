package cubyz.world.terrain.biomes;

import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * One position vegetation, like grass or cactus.
 */

public class SimpleVegetation extends StructureModel {
	int block;
	int height0, deltaHeight;

	public SimpleVegetation() {
		super(new Resource("cubyz", "simple_vegetation"), 0);
		this.block = 0;
		height0 = 0;
		deltaHeight = 0;
	}
	public SimpleVegetation(JsonObject json) {
		super(new Resource("cubyz", "simple_vegetation"), json.getFloat("chance", 0.5f));
		this.block = Blocks.getByID(json.getString("block", "cubyz:grass"));
		height0 = json.getInt("height", 1);
		deltaHeight = json.getInt("height_variation", 0);
	}
	
	@Override
	public void generate(int x, int z, int y, Chunk chunk, CaveMap map, FastRandom rand) {
		if (chunk.voxelSize > 2 && (x / chunk.voxelSize * chunk.voxelSize != x || z / chunk.voxelSize * chunk.voxelSize != z)) return;
		if (chunk.liesInChunk(x, y, z)) {
			int height = height0;
			if (deltaHeight != 0)
				height += rand.nextInt(deltaHeight);
			if(y + height >= map.findTerrainChangeAbove(x, z, y)) // Space is too small.
				return;
			for(int py = chunk.startIndex(y); py < y + height; py += chunk.voxelSize) {
				if (chunk.liesInChunk(x, py, z)) {
					chunk.updateBlockIfDegradable(x, py, z, block);
				}
			}
		}
	}

	@Override
	public StructureModel loadStructureModel(JsonObject json) {
		return new SimpleVegetation(json);
	}
}
