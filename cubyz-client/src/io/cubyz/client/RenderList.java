package io.cubyz.client;

public class RenderList<T> {

	protected Object[] array;
	protected int size = 0;
	protected int arrayIncrease = 10; // this allow to use less array re-allocations

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
	
	public void set(int index, T obj) {
		array[index] = obj;
	}
	
	public void add(T obj) {
		if (size + 1 > array.length)
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
	
	public T get(int index) {
		return (T) array[index];
	}
	
	public int size() {
		return size;
	}
	
	public boolean isEmpty() {
		return size == 0;
	}
	
	/**
	 * Clears the content of the array.<br/>
	 * <b>Implementation note:</b> This implementation doesn't actually clear it or zero it out for performance issues, hence
	 * {@link RenderList#trimToSize()} should be called in order to free memory.
	 */
	public void clear() {
		size = 0;
	}
	
	public RenderSubList<T> subList(int start, int end) {
		return new RenderSubList<T>(this, start, end);
	}
	
	/**
	 * Sub list of a RenderList. Note that editing sublist content will not affect the parent list's content!
	 * @param <E>
	 */
	class RenderSubList<E> extends RenderList<E> {
		public RenderSubList(RenderList<E> parent, int start, int end) {
			size = end - start;
			array = new Object[size];
			System.arraycopy(parent.array, start, array, 0, size);
		}
	}

}
