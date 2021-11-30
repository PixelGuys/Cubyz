package cubyz.world.terrain.noise;

import java.util.Random;

import cubyz.utils.Logger;
import cubyz.utils.math.CubyzMath;

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
			Logger.error(e);
			return 0;
		}
	}
	
	private float getGradientY(int x, int y) {
		try {
			return yGridPoints[x][y];
		} catch (ArrayIndexOutOfBoundsException e) {
			Logger.error(e);
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
	private float perlin(int x, int y, int resolution, int resolution2) {

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
	    float n0, n1, ix0, ix1;

	    n0 = dotGridGradient(x0, y0, x, y, resolution);
	    n1 = dotGridGradient(x1, y0, x, y, resolution);
	    ix0 = lerp(n0, n1, sx);

	    n0 = dotGridGradient(x0, y1, x, y, resolution);
	    n1 = dotGridGradient(x1, y1, x, y, resolution);
	    ix1 = lerp(n0, n1, sx);
	    return lerp(ix0, ix1, sy)*(float)Math.sqrt(2);
	}
	
	// Calculate all grid points that will be needed to prevent double calculating them.
	private void calculateGridPoints(int x, int y, int width, int height, int scale, long l1, long l2, long l3) {
		// Create one gridpoint more, just in case...
		width += scale;
		height += scale;
		int resolutionShift = CubyzMath.binaryLog(scale);
		// Determine grid cell coordinates of all cells that points can be in:
		float[][] xGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
		float[][] yGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
		int numX = 0, numY = 0;
		int x0 = 0;
		for(int ix = x; ix < x+width; ix += scale) {
			numY = 0;
			x0 = ix >> resolutionShift;
			int y0 = 0;
			for(int iy = y; iy < y+height; iy += scale) {
			    y0 = iy >> resolutionShift;
				xGrid[numX][numY] = generateGradient(x0, y0, 0, l1, l2, l3, resolutionShift);
				yGrid[numX][numY] = generateGradient(x0, y0, 1, l1, l2, l3, resolutionShift);
				numY++;
			}
			xGrid[numX][numY] = generateGradient(x0, y0 + 1, 0, l1, l2, l3, resolutionShift);
			yGrid[numX][numY] = generateGradient(x0, y0 + 1, 1, l1, l2, l3, resolutionShift);
			numX++;
		}
		numY = 0;
		int y0 = 0;
		for(int iy = y; iy < y+height; iy += scale) {
		    y0 = iy >> resolutionShift;
			xGrid[numX][numY] = generateGradient(x0+1, y0, 0, l1, l2, l3, resolutionShift);
			yGrid[numX][numY] = generateGradient(x0+1, y0, 1, l1, l2, l3, resolutionShift);
			numY++;
		}
		
		xGrid[numX][numY] = generateGradient(x0+1, y0+1, 0, l1, l2, l3, resolutionShift);
		yGrid[numX][numY] = generateGradient(x0+1, y0+1, 1, l1, l2, l3, resolutionShift);
		numY++;
		numX++;
		xGridPoints = xGrid;
		yGridPoints = yGrid;
	}
	
	/**
	 * Returns a ridgid map of floats with values between 0 and 1.
	 * @param x
	 * @param y
	 * @param width
	 * @param height
	 * @param scale wavelength of lowest frequency layer. Must be a power of 2!
	 * @param minScale wavelength of highest frequency layer. Must be a power of 2!
	 * @param seed
	 * @param worldSizeX
	 * @param worldSizeZ
	 * @param voxelSize size of each unit in the indexing of the output map
	 * @param reductionFactor amplitude reduction for each frequency increase.
	 * @return
	 */
	public float[][] generateRidgidNoise(int x, int y, int width, int height, int scale, int minScale, long seed, int voxelSize, float reductionFactor) {
		float[][] map = new float[width/voxelSize][height/voxelSize];
		Random r = new Random(seed);
		long l1 = r.nextLong();
		long l2 = r.nextLong();
		long l3 = r.nextLong();
		float fac = 1/((1 - (float)Math.pow(reductionFactor, CubyzMath.binaryLog(scale/minScale)+1))/(1 - reductionFactor)); // geometric series.
		for(; scale >= minScale; scale >>= 1) {
			calculateGridPoints(x, y, width, height, scale, l1, l2, l3);
			int resolution = scale;
			int resolution2 = resolution-1;
			int x0 = x & ~resolution2;
			int y0 = y & ~resolution2;
				
			for (int x1 = x; x1 < width + x; x1 += voxelSize) {
				for (int y1 = y; y1 < height + y; y1 += voxelSize) {
					map[(x1 - x)/voxelSize][(y1 - y)/voxelSize] += (1 - Math.abs(perlin(x1-x0, y1-y0, resolution, resolution2)))*fac;
				}
			}
			fac *= reductionFactor;
		}
		return map;
	}
	
	/**
	 * Returns a smooth map of floats with values between 0 and 1.
	 * @param x
	 * @param y
	 * @param width
	 * @param height
	 * @param scale wavelength of lowest frequency layer. Must be a power of 2!
	 * @param minScale wavelength of highest frequency layer. Must be a power of 2!
	 * @param seed
	 * @param worldSizeX
	 * @param worldSizeZ
	 * @param voxelSize size of each unit in the indexing of the output map
	 * @param reductionFactor amplitude reduction for each frequency increase.
	 * @return
	 */
	public float[][] generateSmoothNoise(int x, int y, int width, int height, int scale, int minScale, long seed, int voxelSize, float reductionFactor) {
		float[][] map = new float[width/voxelSize][height/voxelSize];
		Random r = new Random(seed);
		long l1 = r.nextLong();
		long l2 = r.nextLong();
		long l3 = r.nextLong();
		float fac = 1/((1 - (float)Math.pow(reductionFactor, CubyzMath.binaryLog(scale/minScale)+1))/(1 - reductionFactor)); // geometric series.
		for(; scale >= minScale; scale >>= 1) {
			calculateGridPoints(x, y, width, height, scale, l1, l2, l3);
			int resolution = scale;
			int resolution2 = resolution-1;
			int x0 = x & ~resolution2;
			int y0 = y & ~resolution2;
				
			for (int x1 = x; x1 < width + x; x1 += voxelSize) {
				for (int y1 = y; y1 < height + y; y1 += voxelSize) {
					map[(x1 - x)/voxelSize][(y1 - y)/voxelSize] += perlin(x1-x0, y1-y0, resolution, resolution2)*fac;
				}
			}
			fac *= reductionFactor;
		}
		return map;
	}
}
