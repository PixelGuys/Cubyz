package cubyz.utils.datastructures;

/**
 * A key for HashMaps that require 3 integers(for example chunk maps).
 */

public class HashMapKey3D {
	public final int x, y, z, hash;
	public HashMapKey3D(int x, int y, int z) {
		this.x = x;
		this.y = y;
		this.z = z;
		hash = ((x << 13) | (x >>> 19)) ^ ((y << 7) | (y >>> 25)) ^ ((z << 23) | (z >>> 9)); // This should be a good hash for normal worlds. Although better ones may exist.
	}
	
	public int hashCode() {
		return hash;
	}
	
	@Override
	public boolean equals(Object other) {
		if (other instanceof HashMapKey3D) {
			return ((HashMapKey3D)other).x == x & ((HashMapKey3D)other).y == y & ((HashMapKey3D)other).z == z;
		}
		return false;
	}
}
