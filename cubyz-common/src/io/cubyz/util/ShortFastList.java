package io.cubyz.util;

import java.lang.reflect.Array;
import java.util.Comparator;

/** 
 * A faster list implementation.
 * Velocity is reached by sacrificing bound checks, by keeping some additional memory
 * (When removing elements they are not necessarily cleared from the array) and through direct data access.
**/
public class ShortFastList {

	public short[] array;
	public int size = 0;
	private static final int arrayIncrease = 20; // this allow to use less array re-allocations

	@SuppressWarnings("unchecked")
	public ShortFastList(int initialCapacity) {
		array = (short[])new short[ initialCapacity];
	}

	public ShortFastList() {
		this(10);
	}

	@SuppressWarnings("unchecked")
	public void increaseSize(int increment) {
		short[] newArray = (short[])new short[ array.length + increment];
		System.arraycopy(array, 0, newArray, 0, array.length);
		array = newArray;
	}

	@SuppressWarnings("unchecked")
	public void trimToSize() {
		short[] newArray = (short[])new short[ size];
		System.arraycopy(array, 0, newArray, 0, size);
		array = newArray;
	}

	@SuppressWarnings("unchecked")
	public short[] toArray() {
		short[] newArray = (short[])new short[ size];
		System.arraycopy(array, 0, newArray, 0, size);
		return newArray;
	}
	
	public void set(int index, short obj) {
		array[index] = obj;
	}
	
	public void add(short obj) {
		if (size == array.length)
			increaseSize(arrayIncrease);
		array[size] = obj;
		size++;
	}
	
	public void remove(int index) {
		System.arraycopy(array, index+1, array, index, array.length-index-1);
		size--;
	}
	
	public void remove(short t) {
		for(int i = size-1; i >= 0; i--) {
			if(array[i] == t)
				remove(i); // Don't break here in case of multiple occurrence.
		}
	}
	
	public boolean contains(short t) {
		for(int i = size-1; i >= 0; i--) {
			if(array[i] == t)
				return true;
		}
		return false;
	}
	
	public boolean isEmpty() {
		return size == 0;
	}
	
	/**
	 * Sort using Quick Sort algorithm.
	 * @param comp comparator
	 */
	public void sort(Comparator comp) {
		if (size > 1) {
			sort(comp, 0, size-1);
		}
	}
	
	/**
	 * Sort using Quick Sort algorithm.
	 * @param comp comparator
	 * @param l index of the left-most element in the to sorting area.
	 * @param r index of the right-most element in the to sorting area.
	 */
	public void sort(Comparator comp, int l, int r) {
		if(l >= r) return;
		int i = l, j = r;
		
		short x = array[(l+r)/2];
		while (true) {
			while (comp.compare( array[i], x) < 0) {
				i++;
			}
			while (comp.compare(x,  array[j]) < 0) {
				j--;
			}
			if (i <= j) {
				short temp = array[i];
				array[i] = array[j];
				array[j] = temp;
				i++;
				j--;
			}
			if (i > j) {
				break;
			}
		}
		if (l < j) {
			sort(comp, l, j);
		}
		if (i < r) {
			sort(comp, i, r);
		}
	}
	
	/**
	 * Sets the size to 0, meaning {@link RenderList#trimToSize()} should be called in order to free memory.
	 */
	public void clear() {
		size = 0;
	}

}
