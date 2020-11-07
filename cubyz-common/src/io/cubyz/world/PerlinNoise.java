package io.cubyz.world;

import java.util.Random;

import io.cubyz.math.CubyzMath;

/**
 * A generator for (multi-layered) perlin noise.
 */

public class PerlinNoise {
	private Random r = new Random();

	private float[][] xGridPoints; // [x][y]
	private float[][] yGridPoints; // [x][y]
	// Calculate the gradient instead of storing it.
	// This is inefficient(since it is called every time), but allows infinite chunk generation.
	private float generateGradient(int x, int y, int i, long l1, long l2, long l3, int resolution) {
		r.setSeed(l1*x+l2*y+l3*i+resolution);
    	return 2 * r.nextFloat() - 1;
    }
	
	private float getGradientX(int x, int y) {
		try {
			return xGridPoints[x][y];
		} catch (ArrayIndexOutOfBoundsException e) { // quick and dirty fix
			e.printStackTrace();
			return 0;
		}
	}
	
	private float getGradientY(int x, int y) {
		try {
			return yGridPoints[x][y];
		} catch (ArrayIndexOutOfBoundsException e) {
			e.printStackTrace();
			return 0;
		}
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
	private float dotGridGradient(int ix, int iy, float x, float y, int resolution) {

	    // Compute the distance vector
		float dx = x/resolution - ix;
		float dy = y/resolution - iy;

	    // Compute the dot-product
		float gx = getGradientX(ix, iy);
		float gy = getGradientY(ix, iy);
		float gr = (float)Math.sqrt((gx*gx+gy*gy));
		gx /= gr;
		gy /= gr;
	    return (dx*gx + dy*gy);
	}

	// Compute Perlin noise at coordinates x, y
	private float perlin(int x, int y, int resolution, int resolution2, boolean ridged) {

	    // Determine grid cell coordinates
	    int x0 = x/resolution;
	    int x1 = x0 + 1;
	    int y0 = y/resolution;
	    int y1 = y0 + 1;

	    // Determine interpolation weights
	    // Could also use higher order polynomial/s-curve here
	    float sx = s((x&resolution2)/(float)resolution);
	    float sy = s((y&resolution2)/(float)resolution);

	    // Interpolate between grid point gradients
	    float n0, n1, ix0, ix1, value;

	    n0 = dotGridGradient(x0, y0, x, y, resolution);
	    n1 = dotGridGradient(x1, y0, x, y, resolution);
	    ix0 = lerp(n0, n1, sx);

	    n0 = dotGridGradient(x0, y1, x, y, resolution);
	    n1 = dotGridGradient(x1, y1, x, y, resolution);
	    ix1 = lerp(n0, n1, sx);
	    if(ridged)
	    	value = 1 - Math.abs(lerp(ix0, ix1, sy))*(float)Math.sqrt(2);
	    else
	    	value = lerp(ix0, ix1, sy)*0.5f*(float)Math.sqrt(2) + 0.5f;
	    if(value > 1)
	    	value = 1;
	    return value;
	}
	
	// Calculate all grid points that will be needed to prevent double calculating them.
	private void calculateGridPoints(int x, int y, int width, int height, int scale, long l1, long l2, long l3, int worldSizeX, int worldSizeZ) {
		// Create one gridpoint more, just in case...
		width += scale;
		height += scale;
		int resolution = scale;
		int localSizeX = worldSizeX/resolution;
		int localSizeZ = worldSizeZ/resolution;
		// Determine grid cell coordinates of all cells that points can be in:
		float[][] xGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
		float[][] yGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
		int numX = 0, numY = 0;
		int x0 = 0;
		for(int ix = x; ix < x+width; ix += scale) {
			numY = 0;
			x0 = CubyzMath.worldModulo(ix/resolution, localSizeX);
			int y0 = 0;
			for(int iy = y; iy < y+height; iy += scale) {
			    y0 = CubyzMath.worldModulo(iy/resolution, localSizeZ);
				xGrid[numX][numY] = generateGradient(x0, y0, 0, l1, l2, l3, resolution);
				yGrid[numX][numY] = generateGradient(x0, y0, 1, l1, l2, l3, resolution);
				numY++;
			}
			xGrid[numX][numY] = generateGradient(x0, CubyzMath.worldModulo(y0 + 1, localSizeZ), 0, l1, l2, l3, resolution);
			yGrid[numX][numY] = generateGradient(x0, CubyzMath.worldModulo(y0 + 1, localSizeZ), 1, l1, l2, l3, resolution);
			numX++;
		}
		numY = 0;
		int y0 = 0;
		for(int iy = y; iy < y+height; iy += scale) {
		    y0 = CubyzMath.worldModulo(iy/resolution, localSizeZ);
			xGrid[numX][numY] = generateGradient(CubyzMath.worldModulo(x0+1, localSizeX), y0, 0, l1, l2, l3, resolution);
			yGrid[numX][numY] = generateGradient(CubyzMath.worldModulo(x0+1, localSizeX), y0, 1, l1, l2, l3, resolution);
			numY++;
		}
		
		xGrid[numX][numY] = generateGradient(CubyzMath.worldModulo(x0+1, localSizeX), CubyzMath.worldModulo(y0+1, localSizeZ), 0, l1, l2, l3, resolution);
		yGrid[numX][numY] = generateGradient(CubyzMath.worldModulo(x0+1, localSizeX), CubyzMath.worldModulo(y0+1, localSizeZ), 1, l1, l2, l3, resolution);
		numY++;
		numX++;
		// Copy the values into smaller arrays and put them into the array containing all grid points:
		float[][] xGridR = new float[numX+1][numY+1];
		float[][] yGridR = new float[numX+1][numY+1];
		for(int ix = 0; ix < numX+1; ix++) {
			System.arraycopy(xGrid[ix], 0, xGridR[ix], 0, numY+1);
			System.arraycopy(yGrid[ix], 0, yGridR[ix], 0, numY+1);
		}
		xGridPoints = xGridR;
		yGridPoints = yGridR;
	}
	
	public float[][] generateThreeOctaveMapFragment(int x, int y, int width, int height, int scale, long seed, int worldSizeX, int worldSizeZ) {
		float[][] map = new float[width][height];
		Random r = new Random(seed);
		long l1 = r.nextLong();
		long l2 = r.nextLong();
		long l3 = r.nextLong();
		calculateGridPoints(x, y, width, height, scale, l1, l2, l3, worldSizeX, worldSizeZ);
		int resolution = scale;
		int resolution2 = resolution-1;
		int x0 = x & ~resolution2;
		int y0 = y & ~resolution2;
			
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] = perlin(x1-x0, y1-y0, resolution, resolution2, false)*0.6f;
			}
		}
		scale >>= 1;
		calculateGridPoints(x, y, width, height, scale, l1, l2, l3, worldSizeX, worldSizeZ);
		resolution = scale;
		resolution2 = resolution-1;
		x0 = x & ~resolution2;
		y0 = y & ~resolution2;
			
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] += perlin(x1-x0, y1-y0, resolution, resolution2, false)*0.3f;
			}
		}
		scale >>= 2;
		calculateGridPoints(x, y, width, height, scale, l1, l2, l3, worldSizeX, worldSizeZ);
		resolution = scale;
		resolution2 = resolution-1;
		x0 = x & ~resolution2;
		y0 = y & ~resolution2;
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] += perlin(x1-x0, y1-y0, resolution, resolution2, false)*0.1f;

				// Do some rescaling, so the output has an almost uniform distribution:
				map[x1 - x][y1 - y] -= 0.5f;
				map[x1 - x][y1 - y] *= 4f;
				map[x1 - x][y1 - y] += 0.5f;
				map[x1 - x][y1 - y] = (map[x1 - x][y1 - y]) % 2;
				if(map[x1 - x][y1 - y] < 0) map[x1 - x][y1 - y] += 2;
				if(map[x1 - x][y1 - y] >= 1) map[x1 - x][y1 - y] = 2-map[x1 - x][y1 - y];
				if(map[x1 - x][y1 - y] >= 0.999f) map[x1 - x][y1 - y] = 0.999f;
			}
		}
		
		return map;
	}
}
