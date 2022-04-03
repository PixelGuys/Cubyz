package cubyz.world.terrain;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import pixelguys.json.JsonObject;

/**
 * Generates the detailed(block-level precision) height and biome maps from the climate map.
 */
public interface MapGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	void init(JsonObject parameters, CurrentWorldRegistries registries);

	void generateMapFragment(MapFragment fragment, long seed);
}
