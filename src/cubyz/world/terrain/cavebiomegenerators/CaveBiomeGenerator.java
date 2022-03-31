package cubyz.world.terrain.cavebiomegenerators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.world.terrain.CaveBiomeMapFragment;
import pixelguys.json.JsonObject;

/**
 * A generator for the cave biome map.
 */

public interface CaveBiomeGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	void init(JsonObject parameters, CurrentWorldRegistries registries);

	int getPriority(); // Used to prioritize certain generators over others.
	void generate(long seed, CaveBiomeMapFragment map);

	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	 * @return The seed of this generator. Should be unique
	 */
	long getGeneratorSeed();

}
