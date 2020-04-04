package io.cubyz.client;

import java.util.AbstractList;

public class RenderList<T> extends AbstractList<T> {

	private Object[] array;
	private int size = 0;
	private int arrayIncrease = 10; // this allow to use less array re-allocations

	public RenderList(int initialCapacity) {
		super();
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
	
	@Override
	public T set(int index, T obj) {
		if (index < 0 || index >= size) {
			throw new IndexOutOfBoundsException(Integer.toString(index));
		}
		array[index] = obj;
		modCount++;
		return obj;
	}

	@Override
	public void add(int index, T obj) {
		if (index < 0 || index >= size) {
			throw new IndexOutOfBoundsException(Integer.toString(index));
		}
		if (size + 1 > array.length)
			increaseSize(arrayIncrease);
		System.arraycopy(array, index, array, index+1, array.length-index-1);
		array[index] = obj;
		modCount++;
		size++;
	}

	@Override
	public boolean add(T obj) {
		if (size + 1 > array.length)
			increaseSize(arrayIncrease);
		array[size] = obj;
		size++;
		return true;
	}

	@Override
	public T remove(int index) {
		if (index < 0 || index > size) {
			throw new IndexOutOfBoundsException(Integer.toString(index));
		}
		Object old = array[index];
		System.arraycopy(array, index, array, index-1, array.length-index-1);
		modCount++;
		size--;
		return (T) old;
	}

	@Override
	public T get(int index) {
		if (index < 0 || index > size) {
			throw new IndexOutOfBoundsException(Integer.toString(index));
		}
		return (T) array[index];
	}

	@Override
	public int size() {
		return size;
	}
	
	/**
	 * Clears the content of the array.<br/>
	 * <b>Implementation note:</b> This implementation doesn't actually clear it or zero it out for performance issues, hence
	 * {@link RenderList#trimToSize()} should be called in order to free memory.
	 */
	@Override
	public void clear() {
		size = 0;
	}

}
