package io.cubyz.world.cubyzgenerators;

import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.MetaChunk;

/**
 *  A generator that needs access to the MetaChunks directly. Useful for generating big structures like rivers.
 */

public interface BigGenerator extends Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int lx, int lz, NormalChunk chunk, boolean[][] vegetationIgnoreMap, MetaChunk nn, MetaChunk np, MetaChunk pn, MetaChunk pp); // Needs coordinates of the local system of the 4 MetaChunks!
	default void generate(long seed, int cx, int cz, NormalChunk chunk, MetaChunk containingMetaChunk, Surface surface, boolean[][] vegetationIgnoreMap) {}
}
