package cubyz.api;

import java.util.ArrayList;
import java.util.List;

import cubyz.utils.Logger;

/**
 * A registry type that doesn't use any ID, but instead uses the T.equals() function.
 * @param <T>
 */

public class NoIDRegistry<T> {
	private ArrayList<T> registered;
	private boolean debug = Boolean.parseBoolean(System.getProperty("registry.debugEnabled", "false"));
	
	public NoIDRegistry() {
		registered = new ArrayList<>();
	}
	
	public NoIDRegistry(NoIDRegistry<T> other) {
		registered = new ArrayList<T>(other.registered);
	}
	
	public T[] registered(T[] array) {
		return registered.toArray(array);
	}
	
	protected String getType(Class<?> cl) {
		if (cl.getSuperclass() != Object.class) {
			return getType(cl.getSuperclass());
		} else {
			return cl.getSimpleName();
		}
	}
	
	public boolean contains(T element) {
		for (int i = 0; i < registered.size(); i++) {
			if (registered.get(i).equals(element)) {
				return true;
			}
		}
		return false;
	}
	
	public void register(T element) {
		if (contains(element)) {
			throw new IllegalStateException(getType(element.getClass()) + " with identifier \"" + element.toString() + "\" is already registered!");
		}
		registered.add(element);
		if (debug) {
			Logger.info("Registered " + getType(element.getClass()) + " as " + element.toString());
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
	
	public int getLength() {
		return registered.size();
	}
	
	// Print all registered objects.
	@Override
	public String toString() {
		String res = "";
		for(T entry : registered) {
			res += entry+"\n";
		}
		return res;
	}
}
