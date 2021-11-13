package cubyz.world.save;

import java.util.Arrays;
import java.util.HashMap;

import cubyz.utils.json.JsonObject;
import cubyz.world.blocks.Blocks;

public class BlockPalette {
	private final HashMap<Integer, Integer> TToInt = new HashMap<Integer, Integer>();
	private int[] intToT = new int[0];
	public BlockPalette(JsonObject json) {
		if(json == null) return;
		for (String key : json.map.keySet()) {
			int t = Blocks.getByID(key);
			TToInt.put(t, json.getInt(key, 0));
		}
		intToT = new int[TToInt.size()];
		for(Integer t : TToInt.keySet()) {
			intToT[TToInt.get(t)] = t;
		}
	}
	public JsonObject save() {
		JsonObject json = new JsonObject();
		for (Integer t : TToInt.keySet()) {
			json.put(Blocks.id(t).toString(), (int)TToInt.get(t));
		}
		return json;
	}

	public int getElement(int index) {
		return intToT[index];
	}
	public int getIndex(int t) {
		if(TToInt.containsKey(t)) {
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
