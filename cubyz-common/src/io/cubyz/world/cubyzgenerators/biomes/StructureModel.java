package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.world.Chunk;
import io.cubyz.world.MetaChunk;

/**
 * A simple model that describes how smaller structures like vegetation should be generated.
 */

public abstract class StructureModel {
	float chance;
	public StructureModel(float chance) {
		this.chance = chance;
	}
	public abstract void generate(int x, int z, int h, Chunk chunk, MetaChunk metaChunk, Random rand);
	public float getChance() {
		return chance;
	}
}