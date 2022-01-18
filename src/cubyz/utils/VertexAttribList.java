package cubyz.utils;

import java.util.Arrays;

/**
 * Used to accumulate vertex attributes in a single array.
 * Trying to mimick the behaviour of std::vector<Vertex> from C++.
 * TODO: Change when project valhalla gets released.
 */
public class VertexAttribList {
	private int[] attribs;
	private int currentIndex = 0;
	private final int numberOfAttributes;
	
	public VertexAttribList(int numberOfAttributes) {
		this.numberOfAttributes = numberOfAttributes;
		attribs = new int[128*numberOfAttributes];
	}
	
	public void endVertex() {
		currentIndex += numberOfAttributes;
		if(currentIndex >= attribs.length) {
			attribs = Arrays.copyOf(attribs, attribs.length*2);
		}
	}
	
	public void add(int offset, int value) {
		attribs[currentIndex + offset] = value;
	}
	
	public void add(int offset, float value) {
		attribs[currentIndex + offset] = Float.floatToIntBits(value);
	}
	
	public void clear() {
		currentIndex = 0;
	}
	
	public int size() {
		return currentIndex;
	}
	
	public int currentVertex() {
		return currentIndex/numberOfAttributes;
	}
	
	public int[] toArray() {
		return Arrays.copyOf(attribs, currentIndex);
	}
}
