package cubyz.utils.datastructures;

import java.util.Random;
import java.util.function.Consumer;

import cubyz.utils.math.CubyzMath;

/**
 * A list that allows to choose randomly from the contained object, if they have a chance assigned to them.
 * @param <T>
 */

public class RandomList<T extends ChanceObject> {
	private static final int arrayIncrease = 10;
	
	private ChanceObject[] array;
	private int size;
	private long sum; // Has to be long in case the ChanceObjects have values close to integer limit.
	
	public RandomList() {
		this(10);
	}
	
	public RandomList(int initialCapacity) {
		size = 0;
		sum = 0;
		array = new ChanceObject[initialCapacity];
	}
	
	public RandomList(RandomList<T> other) {
		size = other.size;
		sum = other.sum;
		array = new ChanceObject[size];
		System.arraycopy(other.array, 0, array, 0, size);
	}
	
	private void increaseSize(int increment) {
		ChanceObject[] newArray = new ChanceObject[array.length + increment];
		System.arraycopy(array, 0, newArray, 0, array.length);
		array = newArray;
	}
	
	@SuppressWarnings("unchecked")
	public void forEach(Consumer<T> action) {
		for(int i = 0; i < size; i++) {
			action.accept((T)array[i]);
		}
	}
	
	public int size() {
		return size;
	}
	
	@SuppressWarnings("unchecked")
	public T get(int index) {
		return (T)array[index];
	}
	
	public void add(T object) {
		if (size == array.length)
			increaseSize(arrayIncrease);
		array[size] = object;
		size++;
		sum += object.chance;
	}
	
	@SuppressWarnings("unchecked")
	public T getRandomly(Random rand) {
		long value = rangedRandomLong(rand, sum);
		for(int i = 0; i < size; i++) {
			if (value < array[i].chance)
				return (T)array[i];
			value -= array[i].chance;
		}
		throw new IllegalStateException("Seems like someone made changes to the code without thinking. Report this immediately!");
	}
	
	private static long rangedRandomLong(Random rand, long max) {
		long and = CubyzMath.fillBits(max);
		long out = 0;
		do {
			out = rand.nextLong();
			out &= and;
		} while (out >= max);
		return out;
	}
}
