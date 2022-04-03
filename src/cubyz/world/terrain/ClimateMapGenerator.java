package cubyz.world.terrain;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import pixelguys.json.JsonObject;

/**
 * Generates the climate(aka Biome) map, which is a rough representation of the world.
 */
public interface ClimateMapGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	void init(JsonObject parameters, CurrentWorldRegistries registries);

	void generateMapFragment(ClimateMapFragment fragment, long seed);
}