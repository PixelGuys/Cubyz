package io.cubyz.world.cubyzgenerators;

import io.cubyz.world.MetaChunk;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * Any type of generator that needs more information, like heat and height maps for the given chunk and the surrounding ±½ chunks.
 */

public interface FancyGenerator extends Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int cx, int cz, NormalChunk chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, float[][] heightMap, Biome[][] biomeMap, int worldSize);
	default void generate(long seed, int cx, int cz, NormalChunk chunk, MetaChunk containingMetaChunk, Surface surface, boolean[][] vegetationIgnoreMap) {}
}
