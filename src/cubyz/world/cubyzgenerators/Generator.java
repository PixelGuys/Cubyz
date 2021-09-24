package cubyz.world.cubyzgenerators;

import cubyz.api.RegistryElement;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.terrain.MapFragment;

/**
 * Some interface to access all different generators(caves,terrain,…) through one simple function.
 */

public interface Generator extends RegistryElement {
	
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ServerWorld world);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	 * @return The seed of this generator. Should be unique
	 */
	abstract long getGeneratorSeed();
	
}
