package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;

// A simple model that describes how smaller structures like vegetation should be generated.

public abstract class StructureModel {
	float chance;
	public StructureModel(float chance) {
		this.chance = chance;
	}
	public abstract void generate(int x, int z, int h, Block[][][] chunk, int[][] heightMap, Random rand);
	public float getChance() {
		return chance;
	}
}