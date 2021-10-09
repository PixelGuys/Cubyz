package cubyz.world.items.tools;

import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonObject;

/**
 * Holds the basic properties of a tool crafting material.
 */
public class Material {
	/** how much it weighs */
	public final float density;
	/** how long it takes until the tool breaks */
	public final float resistance;
	/** how useful it is for block breaking */
	public final float power;

	/** How rough the texture should look. */
	public final float roughness;
	/** The colors that are used to make tool textures. */
	public final int[] colorPalette;

	public Material(JsonObject json) {
		density = json.getFloat("density", 1.0f);
		resistance = json.getFloat("resistance", 1.0f);
		power = json.getFloat("power", 1.0f);
		roughness = Math.max(json.getFloat("roughness", 1f), 0);
		JsonArray colors = json.getArrayNoNull("colors");
		colorPalette = new int[colors.array.size()];
		colors.getInts(colorPalette);
	}

	public Material(float density, float resistance, float power, float roughness, int[] colors) {
		this.density = density;
		this.resistance = resistance;
		this.power = power;
		this.roughness = roughness;
		colorPalette = colors;
	}

	@Override
	public int hashCode() {
		int hash = Float.floatToIntBits(density);
		hash = 101*hash + Float.floatToIntBits(resistance);
		hash = 101*hash + Float.floatToIntBits(power);
		hash = 101*hash + Float.floatToIntBits(roughness);
		return hash;
	}
}
