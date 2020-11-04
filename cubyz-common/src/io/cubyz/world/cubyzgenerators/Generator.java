package io.cubyz.world.cubyzgenerators;

import io.cubyz.api.RegistryElement;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;

/**
 * Some interface to access all different generators(caves,terrain,…) through one simple function.
 */

public interface Generator extends RegistryElement {
	
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int wx, int wz, NormalChunk chunk, MetaChunk containingMetaChunk, Surface surface, boolean[][] vegetationIgnoreMap);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the torus-seed with the generator specific seed.
	 * @return The seed of this generator. SHould be unique
	 */
	abstract long getGeneratorSeed();
	
}
