package io.cubyz.save;

import java.util.Arrays;
import java.util.HashMap;

import io.cubyz.Logger;
import io.cubyz.api.Registry;
import io.cubyz.api.RegistryElement;
import io.cubyz.ndt.NDTContainer;

/**
 * Basically a bi-directional map.
 */

public class Palette <T extends RegistryElement> {
	private final HashMap<T, Integer> TToInt = new HashMap<T, Integer>();
	private Object[] intToT = new Object[0];
	public Palette(NDTContainer paletteNDT, Registry<T> registry) {
		if(paletteNDT == null) return;
		for (String key : paletteNDT.keys()) {
			T t = registry.getByID(key);
			if (t != null) {
				TToInt.put(t, paletteNDT.getInteger(key));
			} else {
				Logger.warning("A block with ID " + key + " is used in world but isn't available.");
			}
		}
		intToT = new Object[TToInt.size()];
		for(T t : TToInt.keySet()) {
			intToT[TToInt.get(t)] = t;
		}
	}
	public NDTContainer saveTo(NDTContainer container) {
		for (T t : TToInt.keySet()) {
			container.setInteger(t.getRegistryID().toString(), TToInt.get(t));
		}
		return container;
	}
	@SuppressWarnings("unchecked")
	public T getElement(int index) {
		return (T)intToT[index];
	}
	public int getIndex(T t) {
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
