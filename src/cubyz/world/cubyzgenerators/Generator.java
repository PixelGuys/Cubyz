package cubyz.world.cubyzgenerators;

import cubyz.api.RegistryElement;
import cubyz.world.Chunk;
import cubyz.world.Region;
import cubyz.world.Surface;

/**
 * Some interface to access all different generators(caves,terrain,…) through one simple function.
 */

public interface Generator extends RegistryElement {
	
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int wx, int wy, int wz, Chunk chunk, Region containingRegion, Surface surface);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the torus-seed with the generator specific seed.
	 * @return The seed of this generator. SHould be unique
	 */
	abstract long getGeneratorSeed();
	
}
