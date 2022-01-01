package cubyz.world.save;

import java.util.Arrays;
import java.util.HashMap;

import cubyz.utils.json.JsonObject;
import cubyz.world.blocks.Blocks;

public class BlockPalette {
	private final HashMap<Integer, Integer> TToInt = new HashMap<Integer, Integer>();
	private int[] intToT = new int[0];
	public BlockPalette(JsonObject json) {
		if (json == null) return;
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

	public int getElement(int block) {
		return (block & ~Blocks.TYPE_MASK) | intToT[block & Blocks.TYPE_MASK];
	}
	public int getIndex(int block) {
		int data = block & ~Blocks.TYPE_MASK;
		int index = block & Blocks.TYPE_MASK;
		if (TToInt.containsKey(index)) {
			return TToInt.get(index) | data;
		} else {
			// Create a value:
			int newIndex = intToT.length;
			intToT = Arrays.copyOf(intToT, newIndex+1);
			intToT[newIndex] = index;
			TToInt.put(index, newIndex);
			// TODO: Store block palette on each change here!
			return newIndex | data;
		}
	}
}
