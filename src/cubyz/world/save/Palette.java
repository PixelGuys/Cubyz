package cubyz.world.save;

import java.util.Arrays;
import java.util.HashMap;

import cubyz.utils.Logger;
import cubyz.api.Registry;
import cubyz.api.RegistryElement;
import cubyz.utils.json.JsonObject;

/**
 * Basically a bi-directional map.
 */

public class Palette <T extends RegistryElement> {
	private final HashMap<T, Integer> TToInt = new HashMap<T, Integer>();
	private Object[] intToT = new Object[0];
	public Palette(JsonObject json, Registry<T> registry) {
		if (json == null) return;
		for (String key : json.map.keySet()) {
			T t = registry.getByID(key);
			if (t != null) {
				TToInt.put(t, json.getInt(key, 0));
			} else {
				Logger.warning("A block with ID " + key + " is used in world but isn't available.");
			}
		}
		intToT = new Object[TToInt.size()];
		for(T t : TToInt.keySet()) {
			intToT[TToInt.get(t)] = t;
		}
	}
	public JsonObject save() {
		JsonObject json = new JsonObject();
		for (T t : TToInt.keySet()) {
			json.put(t.getRegistryID().toString(), (int)TToInt.get(t));
		}
		return json;
	}
	@SuppressWarnings("unchecked")
	public T getElement(int index) {
		return (T)intToT[index];
	}
	public int getIndex(T t) {
		if (TToInt.containsKey(t)) {
			return TToInt.get(t);
		} else {
			// Create a value:
			int index = intToT.length;
			intToT = Arrays.copyOf(intToT, index+1);
			intToT[index] = t;
			TToInt.put(t, index);
			return index;
		}
	}
}
