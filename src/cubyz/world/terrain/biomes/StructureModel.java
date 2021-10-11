package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.world.Chunk;
import cubyz.world.terrain.MapFragment;

/**
 * A simple model that describes how smaller structures like vegetation should be generated.
 */

public abstract class StructureModel {
	float chance;
	public StructureModel(float chance) {
		this.chance = chance;
	}
	public abstract void generate(int x, int z, int h, Chunk chunk, MapFragment map, Random rand);
	public float getChance() {
		return chance;
	}
}