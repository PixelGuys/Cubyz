package cubyz.utils.math;

import java.util.ArrayList;

/**
 * A collection of special math functions used by Cubyz.
 */

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
	public static int moduloMatchSign(int num, int worldSize) {
		if(num > (worldSize >> 1))
			return num - worldSize;
		if(num < -(worldSize >> 1))
			return num + worldSize;
		return num;
	}
	public static float match(float x, float playerX, int worldSize) {
		if(playerX < worldSize >> 2 && x > 3*worldSize >> 2) {
	        return x - worldSize;
		} else if(playerX > 3*worldSize >> 2 && x < worldSize >> 2) {
	        return x + worldSize;
		} else {
			return x;
		}
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
	
	public static int shiftRight(int value, int shift) {
		return shift < 0 ? value << -shift : value >>> shift;
	}
	
	public static int binaryLog(int in) {
		int log = 0;
		if((in & (0b11111111_11111111_00000000_00000000)) != 0) {
			log += 16;
			in >>= 16;
		}
		if((in & (0b11111111_00000000)) != 0) {
			log += 8;
			in >>= 8;
		}
		if((in & (0b11110000)) != 0) {
			log += 4;
			in >>= 4;
		}
		if((in & (0b1100)) != 0) {
			log += 2;
			in >>= 2;
		}
		if((in & (0b10)) != 0) {
			log += 1;
		}
		return log;
	}
	
	public static int binaryLog(long in) {
		int log = 0;
		if((in & (0b11111111_11111111_11111111_11111111_00000000_00000000_00000000_00000000L)) != 0) {
			log += 16;
			in >>= 16;
		}
		if((in & (0b11111111_11111111_00000000_00000000L)) != 0) {
			log += 16;
			in >>= 16;
		}
		if((in & (0b11111111_00000000L)) != 0) {
			log += 8;
			in >>= 8;
		}
		if((in & (0b11110000L)) != 0) {
			log += 4;
			in >>= 4;
		}
		if((in & (0b1100L)) != 0) {
			log += 2;
			in >>= 2;
		}
		if((in & (0b10L)) != 0) {
			log += 1;
		}
		return log;
	}
	
	/**
	 * Fills all bits after the leading 1 with 1s.
	 * Example input:  00001010 11000101
	 * Example output: 00001111 11111111
	 * @param input
	 * @return
	 */
	public static long fillBits(long input) {
		int bitLength = binaryLog(input);
		return ~(-2L << bitLength);
	}
	
	/**
	 * Works like the normal sign function except for sign(0) which in this function returns 1.
	 * @param in
	 * @return
	 */
	public static int nonZeroSign(float in) {
		in = Math.signum(in);
		if(in == 0) in = 1;
		return (int)in;
	}
}
