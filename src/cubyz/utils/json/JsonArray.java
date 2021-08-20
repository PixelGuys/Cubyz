package cubyz.utils.json;

import java.util.ArrayList;

public class JsonArray implements JsonElement {
	public static final JsonArray EMPTY_ARRAY = new JsonArray();
	public final ArrayList<JsonElement> array = new ArrayList<>();
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void getInts(int[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getInt(defaultValues[i]);
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void getFloats(float[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getFloat(defaultValues[i]);
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void getBools(boolean[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getBool(defaultValues[i]);
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void getStrings(String[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getString(defaultValues[i]);
		}
	}

	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void addInts(int... defaultValues) {
		for(int i = 0; i < defaultValues.length; i++) {
			array.add(new JsonInt(defaultValues[i]));
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void addFloats(float... defaultValues) {
		for(int i = 0; i < defaultValues.length; i++) {
			array.add(new JsonFloat(defaultValues[i]));
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void addBools(boolean... defaultValues) {
		for(int i = 0; i < defaultValues.length; i++) {
			array.add(new JsonOthers(false, defaultValues[i]));
		}
	}
	/**
	 * Fills the given array with values. Only works if the type of `this` is JSON_ARRAY.
	 * @param defaultValues Replacement if the requested types don't exist.
	 */
	public void addStrings(String... defaultValues) {
		for(int i = 0; i < defaultValues.length; i++) {
			array.add(new JsonString(defaultValues[i]));
		}
	}

	/**
	 * Adds one element.
	 * @param element
	 */
	public void add(JsonElement element) {
		array.add(element);
	}

	public String toString() {
		StringBuilder out = new StringBuilder();
		out.append('[');
		for(int i = 0; i < array.size(); i++) {
			out.append(array.get(i).toString());
			out.append(',');//TODO: Consider removing it.
		}
		out.append(']');
		return out.toString();
	}
}