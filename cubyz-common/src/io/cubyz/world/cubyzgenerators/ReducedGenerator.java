package io.cubyz.world.cubyzgenerators;

import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;

/**
 * This interface is directly used for generating ReducedChunks.
 */

public interface ReducedGenerator {
	abstract void generate(long seed, int wx, int wz, ReducedChunk chunk, MetaChunk containingMetaChunk, Surface surface);
}
