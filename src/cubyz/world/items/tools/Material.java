package cubyz.world.items.tools;

import cubyz.utils.json.JsonObject;

/**
 * Holds the basic properties of a tool crafting material.
 */
public class Material {
	/** how much it weighs */
	public final float density;
	/** how fast it breaks */
	public final float resistance;
	/** how useful it is for block breaking */
	public final float power;

	public Material(JsonObject json) {
		density = json.getFloat("density", 1.0f);
		resistance = json.getFloat("resistance", 1.0f);
		power = json.getFloat("power", 1.0f);

	}
}
