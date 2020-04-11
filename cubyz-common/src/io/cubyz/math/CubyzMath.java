package io.cubyz.math;

public class CubyzMath {
	public static int matchSign(int num, int worldAnd) { // The world coordinates are given as two's complement in the bitregion of the worldAnd.
		if(num-(worldAnd>>>1) < 0)
			return num;
		return num | ~worldAnd; // Fill the frontal region with ones.
	}
	public static byte max(byte a, byte b) {
		return a > b ? a : b;
	}
}
