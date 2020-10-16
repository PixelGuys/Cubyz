package io.cubyz.world.cubyzgenerators;

import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;

/**
 * If a generator generates big features it should implement this interface, so those features get displayed in the far away regions.
 * This interface is directly used for generating ReducedChunks.
 */

public interface ReducedGenerator {
	abstract void generate(long seed, int wx, int wz, ReducedChunk chunk, MetaChunk containingMetaChunk, Surface surface);
}
