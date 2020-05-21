package io.cubyz.math;

import java.util.ArrayList;

public class CubyzMath {
	public static int matchSign(int num, int worldAnd) { // The world coordinates are given as two's complement in the bitregion of the worldAnd.
		if(num-(worldAnd>>>1) < 0)
			return num;
		return num | ~worldAnd; // Fill the frontal region with ones.
	}
	
	public static int max(ArrayList<Integer> numbers) {
		if(numbers.size() == 0) return 0;
		int max = Integer.MIN_VALUE;
		for(Integer value : numbers) {
			if(value > max) max = value;
		}
		return max;
	}
	
	public static float floorMod(float input, float modulo) {
		float result = input % modulo;
		if(result < 0) result += modulo;
		return result;
	}
}
