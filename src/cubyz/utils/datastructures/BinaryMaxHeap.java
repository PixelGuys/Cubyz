package cubyz.utils.datastructures;

import java.util.Arrays;

/**
 * A simple binary heap.
 * Thread safe.
 *
 * @param <T>  extends Comparable<T>
 */

public class BinaryMaxHeap<T extends Comparable<T>> {
	private int size;
	private T[] array;
	/**
	 * @param initialCapacity
	 */
	public BinaryMaxHeap(T[] initialCapacity) {
		array = initialCapacity;
	}
	
	/**
	 * Moves an element from a given index down the heap, such that all children are always smaller than their parents.
	 * @param i
	 */
	private void siftDown(int i) {
		while (i*2 + 2 < size) {
			int biggest = array[i*2 + 1].compareTo(array[i*2 + 2]) > 0 ? i*2 + 1 : i*2 + 2;
			biggest = array[biggest].compareTo(array[i]) > 0 ? biggest : i;
			// Break if all childs are smaller.
			if (biggest == i) return;
			// Swap it:
			T local = array[biggest];
			array[biggest] = array[i];
			array[i] = local;
			// goto the next node:
			i = biggest;
		}
	}
	
	/**
	 * Moves an element from a given index up the heap, such that all children are always smaller than their parents.
	 * @param i
	 */
	private void siftUp(int i) {
		int parentIndex = (i-1)/2;
		// Go through the parents, until the child is smaller and swap.
		while (array[parentIndex].compareTo(array[i]) < 0 && i > 0) {
			T local = array[parentIndex];
			array[parentIndex] = array[i];
			array[i] = local;
			i = parentIndex;
			parentIndex = (i-1)/2;
		}
	}
	
	/**
	 * Adds a new element to the heap.
	 * @param element
	 */
	public void add(T element) {
		synchronized(this) {
			if (size == array.length) {
				increaseCapacity(size*2);
			}
			array[size] = element;
			siftUp(size);
			size++;
		}
	}
	
	/**
	 * Returns the biggest element and removes it from the heap.
	 * @return max or null if empty.
	 */
	public T extractMax() {
		synchronized(this) {
			if (size == 0) return null;
			T ret = array[0];
			array[0] = array[--size];
			array[size] = null;
			siftDown(0);
			return ret;
		}
	}
	/**
	 * Removes all elements inside. Also fills them with nulls.
	 */
	public void clear() {
		synchronized(this) {
			while (--size >= 0) {
				array[size] = null;
			}
			size = 0;
		}
	}
	
	private void increaseCapacity(int newCapacity) {
		array = Arrays.copyOf(array, newCapacity);
	}
}


