package cubyz.world.terrain.biomes;

import cubyz.api.CubyzRegistries;
import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * A simple model that describes how smaller structures like vegetation should be generated.
 */

public abstract class StructureModel implements RegistryElement {
	public final Resource id;
	float chance;

	public StructureModel(Resource id, float chance) {
		this.id = id;
		this.chance = chance;
	}

	/**
	 * 
	 * @param x relative
	 * @param z relative
	 * @param y relative
	 * @param chunk
	 * @param map
	 * @param rand
	 */
	public abstract void generate(int x, int z, int y, Chunk chunk, CaveMap map, FastRandom rand);
	public abstract StructureModel loadStructureModel(JsonObject json);

	public float getChance() {
		return chance;
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}

	public static StructureModel loadStructure(JsonObject json) {
		if (!json.has("id")) return null;
		return CubyzRegistries.STRUCTURE_REGISTRY.getByID(json.getString("id", "???")).loadStructureModel(json);
	}
}