package cubyz.utils.datastructures;

import java.util.Arrays;
import java.util.Comparator;

/** 
 * A very simple list implementation that gives direct access to the underlying array.
 * It also simplifies the `toArray()` method which in ArrayList needs to be supplied with a `new int[0]`
**/

public class IntSimpleList {

	public int[] array;
	public int size = 0;

	public IntSimpleList(int[] initialArray) {
		array = initialArray;
	}

	public IntSimpleList(int initialSize) {
		array = new int[initialSize];
	}

	public IntSimpleList() {
		this(64);
	}

	public void increaseSize(int increment) {
		array = Arrays.copyOf(array, array.length + increment);
	}

	public void trimToSize() {
		array = Arrays.copyOf(array, size);
	}

	public int[] toArray() {
		return Arrays.copyOf(array, size);
	}
	
	public void set(int index, int obj) {
		array[index] = obj;
	}
	
	public void add(int obj) {
		if (size == array.length)
			increaseSize(Math.max(array.length/2, 1));
		array[size] = obj;
		size++;
	}
	
	@SafeVarargs
	public final void add(int... obj) {
		if (size + obj.length >= array.length)
			increaseSize(Math.max(array.length*3/2, array.length + obj.length));
		for(int o : obj) {
			array[size] = o;
			size++;
		}
	}
	
	public void removeIndex(int index) {
		System.arraycopy(array, index+1, array, index, size-index-1);
		size--;
	}
	
	public void remove(int t) {
		for(int i = 0; i < size; i++) {
			if (array[i] == t)
				removeIndex(i); // Don't break here in case of multiple occurrence.
		}
	}
	
	public boolean contains(int t) {
		for(int i = 0; i < size; i++) {
			if (array[i] == t)
				return true;
		}
		return false;
	}
	
	/**
	 * @param t
	 * @return the first index of t or -1 if t is not inside the list.
	 */
	public int indexOf(int t) {
		for(int i = 0; i < size; i++) {
			if (array[i] == t)
				return i;
		}
		return -1;
	}
	
	public boolean isEmpty() {
		return size == 0;
	}

	public void sort() {
		Arrays.sort(array, 0, size);
	}
	
	/**
	 * Sets the size to 0, meaning {@link IntSimpleList#trimToSize()} should be called in order to free memory.
	 * Doesn't null the entries (→ potential memory leak)
	 */
	public void clear() {
		size = 0;
	}

}
