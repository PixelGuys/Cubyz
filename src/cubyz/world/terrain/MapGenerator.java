package cubyz.world.terrain;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.RegistryElement;
import cubyz.utils.json.JsonObject;

/**
 * Generates the detailed(block-level precision) height and biome maps from the climate map.
 */
public interface MapGenerator extends RegistryElement {

	/**
	 * Initializes this generator to the current world.
	 * @param parameters
	 * @param registries
	 */
	abstract void init(JsonObject parameters, CurrentWorldRegistries registries);

	abstract void generateMapFragment(MapFragment fragment);
}
