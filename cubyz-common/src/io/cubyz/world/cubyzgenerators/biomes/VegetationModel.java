package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.blocks.Block;

// A simple model that describes how vegetation should be generated.

public abstract class VegetationModel {
	float chance;
	public VegetationModel(float chance) {
		this.chance = chance;
	}
	public abstract void generate(int x, int y, int h, Block[][][] chunk, float random);
	public float getChance() {
		return chance;
	}
}