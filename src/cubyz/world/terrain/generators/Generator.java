package cubyz.world.terrain.generators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.world.Chunk;
import cubyz.world.terrain.CaveBiomeMap;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * Some interface to access all different generators(caves, terrain, …) through one simple function.
 */

public interface Generator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	void init(JsonObject parameters, CurrentWorldRegistries registries);
	
	int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	void generate(long seed, int wx, int wy, int wz, Chunk chunk, CaveMap caveMap, CaveBiomeMap biomeMap);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	 * @return The seed of this generator. Should be unique
	 */
	long getGeneratorSeed();
	
}
