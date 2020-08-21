package io.cubyz.world.cubyzgenerators;

import io.cubyz.blocks.Block;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

// Any type of generator that needs more information, like heat and height maps for the given chunk and the surrounding ±½ chunks.

public interface FancyGenerator extends Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, float[][] heightMap, Biome[][] biomeMap, byte[][][] blockData, int worldSize);
	default void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap) {}
}
