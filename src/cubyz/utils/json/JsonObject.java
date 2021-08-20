package cubyz.utils.json;

import java.util.HashMap;
import java.util.Map.Entry;

public class JsonObject implements JsonElement {
	public HashMap<String, JsonElement> map;
	public JsonObject() {
		map = new HashMap<>();
	}

	@Override
	public int getInt(String key, int defaultValue) {
		JsonElement object = map.get(key);
		if(object != null)
			return object.getInt(defaultValue);
		return defaultValue;
	}

	@Override
	public float getFloat(String key, float defaultValue) {
		JsonElement object = map.get(key);
		if(object != null)
			return object.getFloat(defaultValue);
		return defaultValue;
	}

	@Override
	public boolean getBool(String key, boolean defaultValue) {
		JsonElement object = map.get(key);
		if(object != null)
			return object.getBool(defaultValue);
		return defaultValue;
	}

	@Override
	public String getString(String key, String defaultValue) {
		JsonElement object = map.get(key);
		if(object != null)
			return object.getString(defaultValue);
		return defaultValue;
	}

	@Override
	public JsonArray getArray(String key) {
		JsonElement object = map.get(key);
		if(object instanceof JsonArray)
			return (JsonArray)object;
		return null;
	}

	@Override
	public JsonArray getArrayNoNull(String key) {
		JsonElement object = map.get(key);
		if(object instanceof JsonArray)
			return (JsonArray)object;
		return JsonArray.EMPTY_ARRAY;
	}

	@Override
	public JsonElement get(String key) {
		return map.get(key);
	}

	public JsonObject getObject(String key) {
		JsonElement object = map.get(key);
		if(object instanceof JsonObject)
			return (JsonObject)object;
		return null;
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, int value) {
		map.put(key, new JsonInt(value));
	}

	/**
	 * Adds a new property to this JsonObject.
	 */
	public void put(String key, float value) {
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
			out.append(entries.getKey());
			out.append("\":");
			out.append(entries.getValue().toString());
			out.append(',');//TODO: Consider removing it.
		}
		out.append('}');
		return out.toString();
	}
}
