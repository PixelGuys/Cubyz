package io.cubyz.world;

import java.util.Random;

/**
 * Perlin noise generator for worlds
 * @author zenith391, IntegratedQuantum
 */
public class Noise {
	private static Random r = new Random();
	private static long l1, l2, l3;

	private static int resolution;
	private static int resolution2;
	// Calculate the gradient instead of storing it.
	// This is inefficient(since it is called every time), but allows infinite chunk generation.
	private static float getGradient(int x, int y, int i) {
		r.setSeed(l1*x+l2*y+l3*i+resolution);
    	return 2 * r.nextFloat() - 1;
    }
	/* Function to linearly interpolate between a0 and a1
	 * Weight w should be in the range [0.0, 1.0]
	 */
	private static float lerp(float a0, float a1, float w) {
	    return a0 + w*(a1 - a0);
	}
	
	// s-curve
	private static float s(float x) {
		return 3*x*x-2*x*x*x;
	}

	// Computes the dot product of the distance and gradient vectors.
	private static float dotGridGradient(int ix, int iy, int x, int y) {

	    // Compute the distance vector
		float dx = x/(float)resolution - ix;
		float dy = y/(float)resolution - iy;

	    // Compute the dot-product
		float gx = getGradient(ix, iy, 0);
		float gy = getGradient(ix, iy, 1);
		float gr = (float)Math.sqrt((gx*gx+gy*gy));
		gx /= gr;
		gy /= gr;
	    return (dx*gx + dy*gy);
	}

	// Compute Perlin noise at coordinates x, y
	private static float perlin(int x, int y) {

	    // Determine grid cell coordinates
	    int x0 = x/resolution;
	    if(x < 0) {
	    	x0 = (x-resolution2)/resolution;
	    }
	    int x1 = x0 + 1;
	    int y0 = y/resolution;
	    if(y < 0) {
	    	y0 = (y-resolution2)/resolution;
	    }
	    int y1 = y0 + 1;

	    // Determine interpolation weights
	    // Could also use higher order polynomial/s-curve here
	    float sx = s((x&resolution2)/(float)resolution);
	    float sy = s((y&resolution2)/(float)resolution);

	    // Interpolate between grid point gradients
	    float n0, n1, ix0, ix1, value;

	    n0 = dotGridGradient(x0, y0, x, y);
	    n1 = dotGridGradient(x1, y0, x, y);
	    ix0 = lerp(n0, n1, sx);

	    n0 = dotGridGradient(x0, y1, x, y);
	    n1 = dotGridGradient(x1, y1, x, y);
	    ix1 = lerp(n0, n1, sx);

	    value = lerp(ix0, ix1, sy);
	    value = 0.5F * value + 0.5F;
	    if(value > 1)
	    	value = 1;
	    return value;
	}
	
	public static float[][] generateMap(int width, int height, int scale, int seed) {
		return generateMapFragment(0, 0, width, height, scale, seed);
	}
	
	// Map generation is rather slow at the moment. It takes almost as much time as the chunk generation.
	public static float[][] generateMapFragment(int x, int y, int width, int height, int scale, int seed) {
		float[][] map = new float[width][height];
		float factor = 0.45F;
		float sum = 0;
		r.setSeed(seed);
		l1 = r.nextLong();
		l2 = r.nextLong();
		l3 = r.nextLong();
		int offset = 0; // Offset the individual noise maps to avoid those rifts in landscape(especially at coordinates like {0, 0})
		for(; scale >= 16; scale >>= 1) {
			resolution = scale;
			resolution2 = resolution-1;		
			for (int x1 = x; x1 < width + x; x1++) {
				for (int y1 = y; y1 < height + y; y1++) {
					//map[x1 - x][y1 - y] = get2DPerlinNoiseValue(x1, y1, scale, seed);
					map[x1 - x][y1 - y] += factor*perlin(x1 + offset, y1 + offset);
				}
			}
			sum += factor;
			factor *= 0.55F;
			offset++;
		}
		
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				//map[x1 - x][y1 - y] = get2DPerlinNoiseValue(x1, y1, scale, seed);
				map[x1 - x][y1 - y] /= sum;
			}
		}
		
		return map;
	}
	
	
}
