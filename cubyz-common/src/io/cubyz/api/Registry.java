package io.cubyz.api;

import java.util.HashMap;
import java.util.List;
import java.util.Map.Entry;

import io.cubyz.CubyzLogger;

public class Registry<T extends IRegistryElement> {
	private HashMap<String, T> hashMap = new HashMap<>();
	private boolean debug = Boolean.parseBoolean(System.getProperty("registry.debugEnabled", "false"));
	private boolean alwaysError = Boolean.parseBoolean(System.getProperty("registry.dumpAsError", "true"));
	
	public IRegistryElement[] registered() { // can be casted to T
		return hashMap.values().toArray(new IRegistryElement[0]);
	}
	
	protected String getType(Class<?> cl) {
		if (cl.getSuperclass() != Object.class) {
			return getType(cl.getSuperclass());
		} else {
			return cl.getSimpleName();
		}
	}
	
	public int indexOf(T element) {
		int i = 0;
		for (String key : hashMap.keySet()) {
			if (key.equals(element.getRegistryID().toString())) {
				return i;
			}
			i++;
		}
		return -1;
	}
	
	public void register(T element) {
		if (hashMap.containsKey(element.getRegistryID().toString())) {
			throw new IllegalStateException(getType(element.getClass()) + " with identifier \"" + element.getRegistryID() + "\" is already registered!");
		}
		if (element.getRegistryID() == null || element.getRegistryID().getID().equals("empty")) {
			if (alwaysError) {
				throw new IllegalArgumentException(element.getClass().getName() + " does not have any ID set!");
			}
			System.err.println(element.getClass().getName() + " does not have any ID set. Skipping!");
			System.err.flush();
			return;
		}
		hashMap.put(element.getRegistryID().toString(), element);
		if (debug) {
			CubyzLogger.instance.info("Registered " + getType(element.getClass()) + " as " + element.getRegistryID());
		}
	}
	
	@SuppressWarnings("unchecked")
	public void registerAll(T... elements) {
		for (T elem : elements) {
			register(elem);
		}
	}
	
	public void registerAll(List<T> list) {
		for (T elem : list) {
			register(elem);
		}
	}
	
	public T getByID(String id) {
		return hashMap.get(id);
	}
	
	public int getLength() {
		return hashMap.size();
	}
	
	// Print all registered objects.
	@Override
	public String toString() {
		String res = "";
		for(Entry<String, T> entry : hashMap.entrySet().toArray(new Entry[0])) {
			res += entry.getKey()+"\n";
		}
		return res;
	}
}
