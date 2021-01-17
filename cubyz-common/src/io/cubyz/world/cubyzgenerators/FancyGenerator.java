package io.cubyz.world.cubyzgenerators;

import io.cubyz.world.Region;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * Any type of generator that needs more information, like heat and height maps for the given chunk and the surrounding ±½ chunks.
 */

public interface FancyGenerator extends Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int cx, int cz, NormalChunk chunk, boolean[][] vegetationIgnoreMap, float[][] heightMap, Biome[][] biomeMap, Surface surface);
	default void generate(long seed, int cx, int cz, NormalChunk chunk, Region containingRegion, Surface surface, boolean[][] vegetationIgnoreMap) {}
}
