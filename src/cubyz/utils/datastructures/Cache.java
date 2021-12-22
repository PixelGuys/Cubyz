package cubyz.utils.datastructures;

import java.util.function.Consumer;

/** 
* Implements a simple set associative cache with LRU replacement strategy.
*/

public class Cache<T> {
	public final T[][] cache;
	/**
	 * The cache will be initialized using the given layout.
	 * @param layout first dimension gives the hash size, second dimension gives the associativity.
	 */
	public Cache(T[][] layout) {
		cache = layout;
	}
	
	public int cacheRequests = 0;
	public int cacheMisses = 0;
	
	/**
	 * Tries to find the entry that fits to the supplied hashable.
	 * @param compare
	 * @param index the hash that is fit within cache.length
	 * @return
	 */
	public T find(Object compare, int index) {
		cacheRequests++;
		synchronized(cache[index]) {
			for(int i = 0; i < cache[index].length; i++) {
				T ret = cache[index][i];
				if (compare.equals(ret)) {
					if (i != 0) { // No need to put it up front when it already is on the front.
						System.arraycopy(cache[index], 0, cache[index], 1, i);
						cache[index][0] = ret;
					}
					return ret;
				}
			}
		}
		cacheMisses++;
		return null;
	}
	
	public void clear() {
		for(T[] line : cache) {
			for(int i = 0; i < line.length; i++) {
				line[i] = null;
			}
		}
	}
	public static int lost = 0;
	/**
	 * Adds a new object into the cache.
	 * @param t
	 * @param index the hash that is fit within cache.length
	 * @return the object that got kicked out of the cache if any.
	 */
	public T addToCache(T t, int index) {
		T previous = cache[index][cache[index].length - 1];
		if (previous != null) lost++;
		System.arraycopy(cache[index], 0, cache[index], 1, cache[index].length - 1);
		cache[index][0] = t;
		return previous;
	}

	public void foreach(Consumer<T> consumer) {
		for(T[] array : cache) {
			for(T obj : array) {
				if (obj != null)
					consumer.accept(obj);
			}
		}
	}
}
