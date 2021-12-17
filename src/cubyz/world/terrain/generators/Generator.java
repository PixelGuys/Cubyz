package cubyz.world.terrain.generators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.ChunkManager;
import cubyz.world.terrain.MapFragment;

/**
 * Some interface to access all different generators(caves, terrain, …) through one simple function.
 */

public interface Generator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	abstract void init(JsonObject parameters, CurrentWorldRegistries registries);
	
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ChunkManager generator);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	 * @return The seed of this generator. Should be unique
	 */
	abstract long getGeneratorSeed();
	
}
