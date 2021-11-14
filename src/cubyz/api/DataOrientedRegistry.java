package cubyz.api;

import cubyz.utils.json.JsonObject;

public interface DataOrientedRegistry extends RegistryElement {
	/**
	 * Registers a new "instance" using the json data.
	 * @param id
	 * @param json
	 * @return index
	 */
	int register(String assetFolder, Resource id, JsonObject json);

	/**
	 * Resets all worls specific objects.
	 * The length is given.
	 * @param len
	 */
	void reset(int len);
}
