package cubyz.api;

import pixelguys.json.JsonObject;

public interface DataOrientedRegistry extends RegistryElement {
	/**
	 * Registers a new "instance" using the json data.
	 * @param id
	 * @param json
	 * @return index
	 */
	void register(String assetFolder, Resource id, JsonObject json);

	/**
	 * Resets all worls specific objects.
	 * The length is given.
	 * @param len
	 */
	void reset();
}
