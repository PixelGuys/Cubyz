package cubyz.world.terrain;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.utils.json.JsonObject;

/**
 * Generates the climate(aka Biome) map, which is a rough representation of the world.
 */
public interface ClimateMapGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	abstract void init(JsonObject parameters, CurrentWorldRegistries registries);

	abstract void generateMapFragment(ClimateMapFragment fragment);
}