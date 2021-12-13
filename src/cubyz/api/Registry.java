package cubyz.api;

import java.util.HashMap;
import java.util.List;
import java.util.Map.Entry;

import cubyz.utils.Logger;

/**
 * A registry that uses registry IDs to avoid duplicate entries.
 * @param <T>
 */

public class Registry<T extends RegistryElement> {
	private HashMap<String, T> hashMap;
	
	// cache values to avoid useless memory allocation (toArray allocates a new array at each call)
	private T[] values;
	private boolean dirty = true;
	
	private boolean debug = Boolean.parseBoolean(System.getProperty("registry.debugEnabled", "false"));
	private boolean alwaysError = Boolean.parseBoolean(System.getProperty("registry.dumpAsError", "true"));
	
	public Registry() {
		hashMap = new HashMap<>();
	}
	
	public Registry(Registry<T> other) {
		hashMap = new HashMap<String, T>(other.hashMap);
	}
	
	public T[] registered(T[] array) {
		if (dirty) {
			values = hashMap.values().toArray(array);
			dirty = false;
		}
		return values;
	}
	
	public int size() {
		return hashMap.size();
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
	
	public boolean register(T element) {
		if (hashMap.containsKey(element.getRegistryID().toString())) {
			throw new IllegalStateException(getType(element.getClass()) + " with identifier \"" + element.getRegistryID() + "\" is already registered!");
		}
		if (element.getRegistryID() == null || element.getRegistryID().getID().equals("empty")) {
			if (alwaysError) {
				throw new IllegalArgumentException(element.getClass().getName() + " does not have any ID set!");
			}
			System.err.println(element.getClass().getName() + " does not have any ID set. Skipping!");
			System.err.flush();
			return false;
		}
		hashMap.put(element.getRegistryID().toString(), element);
		if (debug) {
			Logger.info("Registered " + getType(element.getClass()) + " as " + element.getRegistryID());
		}
		dirty = true;
		return true;
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
		T obj = hashMap.get(id);
		if (obj == null) {
			if (!id.equals("empty:empty") && !id.equals("null")) // Don't warn if it was intentional.
				Logger.warning("Couldn't find registry element with name: "+id);
		}
		return obj;
	}
	
	public T getByID(Resource id) {
		T obj = hashMap.get(id.toString());
		if (obj == null) {
			if (!id.equals(new Resource("empty", "empty"))) // Don't warn if it was intentional.
				Logger.warning("Couldn't find registry element with name: "+id);
		}
		return obj;
	}
	
	public int getLength() {
		return hashMap.size();
	}
	
	// Print all registered objects.
	@SuppressWarnings("unchecked")
	@Override
	public String toString() {
		String res = "";
		for(Entry<String, T> entry : hashMap.entrySet().toArray(new Entry[0])) {
			res += entry.getKey()+"\n";
		}
		return res;
	}
}
