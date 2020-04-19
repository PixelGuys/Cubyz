package io.cubyz.client;

import java.util.Comparator;

public class RenderList<T> {

	public Object[] array;
	protected int size = 0;
	protected int arrayIncrease = 20; // this allow to use less array re-allocations

	public RenderList(int initialCapacity) {
		array = new Object[initialCapacity];
	}

	public RenderList() {
		this(10);
	}

	protected void increaseSize(int increment) {
		Object[] newArray = new Object[array.length + increment];
		System.arraycopy(array, 0, newArray, 0, array.length);
		array = newArray;
	}

	public void trimToSize() {
		Object[] newArray = new Object[size];
		System.arraycopy(array, 0, newArray, 0, size);
		array = newArray;
	}
	
	public void set(int index, T obj) {
		array[index] = obj;
	}
	
	public void add(T obj) {
		if (size == array.length)
			increaseSize(arrayIncrease);
		array[size] = obj;
		size++;
	}
	
	public T remove(int index) {
		Object old = array[index];
		System.arraycopy(array, index, array, index-1, array.length-index-1);
		size--;
		return (T) old;
	}
	
	public int size() {
		return size;
	}
	
	public boolean isEmpty() {
		return size == 0;
	}
	
	public void sort(Comparator<T> comp) {
		/*
		// TODO: use more efficient than bubble sort
		for (int i = size-1; i > 0; i--) {
			for (int j = 0; j < i; j++) {
				if (comp.compare((T) array[j], (T) array[j + 1]) > 0) {
					Object temp = array[j];
					array[j] = array[j+1];
					array[j+1] = temp;
				}
			}
		}
		*/
		if (size > 0) {
			sort(comp, 0, size-1);
		}
	}
	
	@SuppressWarnings("unchecked")
	private void sort(Comparator<T> comp, int l, int r) {
		int i = l, j = r;
		
		T x = (T) array[(l+r)/2];
		while (true) {
			while (comp.compare((T) array[i], x) < 0) {
				i++;
			}
			while (comp.compare(x, (T) array[j]) < 0) {
				j--;
			}
			if (i <= j) {
				Object temp = array[i];
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
