package cubyz.utils.datastructures;

import java.util.Arrays;

/**
 * A simple binary heap.
 * Thread safe and blocking.
 *
 * @param <T>  extends Comparable<T>
 */

public class BlockingMaxHeap<T extends Comparable<T>> {
	private int size;
	private T[] array;
	private Object[] waitingThreads;
	private int waitingThreadCount = 0;
	/**
	 * @param initialCapacity
	 * @param maxThreadCount the maximum number of threads that concurrently try to access this.
	 */
	public BlockingMaxHeap(T[] initialCapacity, int maxThreadCount) {
		array = initialCapacity;
		waitingThreads = new Object[maxThreadCount];
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
	 * Needs to be called after updating the priority of all elements.
	 */
	public void updatePriority() {
		synchronized(this) {
			for(int i = 0; i < size/2; i++) {
				siftDown(i);
			}
		}
	}

	public int size() {
		return size;
	}

	/**
	 * Returns the i-th element in the heap. Useless for most applications.
	 * @param i
	 * @return
	 */
	public T get(int i) {
		if (i >= size) return null;
		return array[i];
	}

	public T[] toArray() {
		synchronized(this) {
			return Arrays.copyOf(array, size);
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
		synchronized(waitingThreads) {
			if (waitingThreadCount != 0) {
				waitingThreadCount--;
				synchronized(waitingThreads[waitingThreadCount]) {
					waitingThreads[waitingThreadCount].notify();
				}
				waitingThreads[waitingThreadCount] = null;
			}
		}
	}

	private void removeIndex(int i) {
		array[i] = array[--size];
		array[size] = null;
		siftDown(i);
	}
	
	/**
	 * Removes an element from the heap.
	 * @param element
	 */
	public void remove(T element) {
		synchronized(this) {
			for(int i = 0; i < size; i++) {
				if (array[i] == element) {
					removeIndex(i);
					i--;
				}
			}
		}
	}
	
	/**
	 * Returns the biggest element and removes it from the heap.
	 * If empty blocks until a new object is added.
	 * @return max
	 */
	public T extractMax() throws InterruptedException {
		while (true) {
			if (size == 0) {
				Object lock = new Object();
				synchronized(lock) {
					synchronized(waitingThreads) {
						waitingThreads[waitingThreadCount] = lock;
						waitingThreadCount++;
					}
					lock.wait();
				}
			}
			synchronized(this) {
				if (size == 0) continue;
				T ret = array[0];
				removeIndex(0);
				return ret;
			}
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


