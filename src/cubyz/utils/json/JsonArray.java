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
	public void getInts(long[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getLong(defaultValues[i]);
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
	public void getDoubles(double[] defaultValues) {
		for(int i = 0; i < Math.min(defaultValues.length, array.size()); i++) {
			defaultValues[i] = array.get(i).getDouble(defaultValues[i]);
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
			defaultValues[i] = array.get(i).getStringValue(defaultValues[i]);
		}
	}
	/**
	 * Fills a new array with values. Only works if the type of `this` is JSON_ARRAY.
	 */
	public String[] getStrings() {
		String[] stringArray = new String[array.size()];
		for(int i = 0; i < array.size(); i++) {
			stringArray[i] = array.get(i).getStringValue("");
		}
		return stringArray;
	}

	/**
	 * Adds the given array into `this`.
	 * @param values
	 */
	public void addInts(int... values) {
		for(int i = 0; i < values.length; i++) {
			array.add(new JsonInt(values[i]));
		}
	}
	/**
	 * Adds the given array into `this`.
	 * @param values
	 */
	public void addFloats(float... values) {
		for(int i = 0; i < values.length; i++) {
			array.add(new JsonFloat(values[i]));
		}
	}
	/**
	 * Adds the given array into `this`.
	 * @param values
	 */
	public void addBools(boolean... values) {
		for(int i = 0; i < values.length; i++) {
			array.add(new JsonOthers(false, values[i]));
		}
	}
	/**
	 * Adds the given array into `this`.
	 * @param values
	 */
	public void addStrings(String... values) {
		for(int i = 0; i < values.length; i++) {
			array.add(new JsonString(values[i]));
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
			out.append(',');
		}
		if(!array.isEmpty()) { // Remove the last comma.
			out.delete(out.length() - 1, out.length());
		}
		out.append(']');
		return out.toString();
	}
}