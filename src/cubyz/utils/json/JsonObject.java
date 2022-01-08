package cubyz.utils.json;

import cubyz.utils.algorithms.StringOperation;

import java.io.PrintWriter;
import java.util.HashMap;
import java.util.Map.Entry;

public class JsonObject implements JsonElement {
	public HashMap<String, JsonElement> map;
	public JsonObject() {
		map = new HashMap<>();
	}

	public void writeObjectToStream(PrintWriter out) {
		out.println(toString() + "\n"); //having an empty line at the end to indicate the end of the jsonobject
	}
	@Override
	public int getInt(String key, int defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getInt(defaultValue);
		return defaultValue;
	}

	@Override
	public long getLong(String key, long defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getLong(defaultValue);
		return defaultValue;
	}

	@Override
	public float getFloat(String key, float defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getFloat(defaultValue);
		return defaultValue;
	}

	@Override
	public double getDouble(String key, double defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getDouble(defaultValue);
		return defaultValue;
	}

	@Override
	public boolean getBool(String key, boolean defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getBool(defaultValue);
		return defaultValue;
	}

	@Override
	public String getString(String key, String defaultValue) {
		JsonElement object = map.get(key);
		if (object != null)
			return object.getStringValue(defaultValue);
		return defaultValue;
	}

	@Override
	public JsonArray getArray(String key) {
		JsonElement object = map.get(key);
		if (object instanceof JsonArray)
			return (JsonArray)object;
		return null;
	}

	@Override
	public JsonArray getArrayNoNull(String key) {
		JsonElement object = map.get(key);
		if (object instanceof JsonArray)
			return (JsonArray)object;
		return JsonArray.EMPTY_ARRAY;
	}

	@Override
	public JsonElement get(String key) {
		return map.get(key);
	}

	public JsonObject getObject(String key) {
		JsonElement object = map.get(key);
		if (object instanceof JsonObject)
			return (JsonObject)object;
		return null;
	}

	public JsonObject getObjectOrNew(String key) {
		JsonElement object = map.get(key);
		if (object instanceof JsonObject)
			return (JsonObject)object;
		return new JsonObject();
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, long value) {
		map.put(key, new JsonInt(value));
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, double value) {
		map.put(key, new JsonFloat(value));
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, boolean value) {
		map.put(key, new JsonOthers(false, value));
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, String value) {
		map.put(key, new JsonString(value));
	}

	/**
	 * Adds a new parameter to this JsonObject.
	 */
	public void put(String key, JsonElement element) {
		map.put(key, element);
	}

	/**
	 * Checks if a key is available.
	 */
	public boolean has(String key) {
		return map.containsKey(key);
	}
	
	public String toString() {
		StringBuilder out = new StringBuilder();
		out.append('{');
		for(Entry<String, JsonElement> entries : map.entrySet()) {
			out.append("\"");
			out.append(StringOperation.escape(entries.getKey()));
			out.append("\":");
			out.append(entries.getValue().toString());
			out.append(',');
		}
		if(!map.isEmpty()) { // Remove the last comma.
			out.delete(out.length() - 1, out.length());
		}
		out.append('}');
		return out.toString();
	}
}
