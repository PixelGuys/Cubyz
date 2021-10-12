package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.world.Chunk;
import cubyz.world.blocks.Block;
import cubyz.world.terrain.MapFragment;

/**
 * One position vegetation, like grass or cactus.
 */

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
	public void generate(int x, int z, int h, Chunk chunk, MapFragment map, Random rand) {
		if(chunk.getVoxelSize() > 2 && (x / chunk.getVoxelSize() * chunk.getVoxelSize() != x || z / chunk.getVoxelSize() * chunk.getVoxelSize() != z)) return;
		int y = chunk.getWorldY();
		if(chunk.liesInChunk(x, h-y, z)) {
			int height = height0;
			if(deltaHeight != 0)
				height += rand.nextInt(deltaHeight);
			for(int py = chunk.startIndex(h); py < h + height; py += chunk.getVoxelSize()) {
				if(chunk.liesInChunk(x, py-y, z)) {
					chunk.updateBlockIfDegradable(x, py-y, z, block);
				}
			}
		}
	}
}
