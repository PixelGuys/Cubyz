package io.cubyz.math;

import java.util.ArrayList;

public class CubyzMath {
	// Transform coordinates into the looping coordinate system.
	public static float worldModulo(float value, int worldSize) {
		if(value < 0) return value%worldSize + worldSize;
		return value%worldSize;
	}
	public static int worldModulo(int value, int worldSize) {
		if(value < 0) return value%worldSize + worldSize;
		return value%worldSize;
	}
	public static float moduloMatchSign(float num, int worldSize) { // The world coordinates are given as two's complement in the bitregion of the worldAnd.
		if(num > (worldSize >> 1))
			return num - worldSize;
		if(num < -(worldSize >> 1))
			return num + worldSize;
		return num;
	}
	public static int moduloMatchSign(int num, int worldSize) { // The world coordinates are given as two's complement in the bitregion of the worldAnd.
		if(num > (worldSize >> 1))
			return num - worldSize;
		if(num < -(worldSize >> 1))
			return num + worldSize;
		return num;
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
