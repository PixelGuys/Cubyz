package cubyz.world.terrain.cavegenerators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.utils.json.JsonObject;
import cubyz.world.terrain.CaveMapFragment;

/**
 * A generator for the cave map.
 */

public interface CaveGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	abstract void init(JsonObject parameters, CurrentWorldRegistries registries);
	
	abstract int getPriority(); // Used to prioritize certain generators over others.
	abstract void generate(long seed, CaveMapFragment map);
	
	/**
	 * To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	 * @return The seed of this generator. Should be unique
	 */
	abstract long getGeneratorSeed();
	
}
