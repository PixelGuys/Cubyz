package io.cubyz.world;

import java.util.Random;

public class PerlinNoise {
	private static Random r = new Random();

	private static float[][][] xGridPoints; // [scale][x][y]
	private static float[][][] yGridPoints; // [scale][x][y]
	// Calculate the gradient instead of storing it.
	// This is inefficient(since it is called every time), but allows infinite chunk generation.
	private static float generateGradient(int x, int y, int i, long l1, long l2, long l3, int resolution) {
		r.setSeed(l1*x+l2*y+l3*i+resolution);
    	return 2 * r.nextFloat() - 1;
    }
	
	private static float getGradientX(int x, int y, int resolution) {
		int index = xGridPoints.length-numOfBits(resolution)+numOfBits(16)-1;
		try {
			return xGridPoints[index][x][y];
		} catch (ArrayIndexOutOfBoundsException e) { // quick and dirty fix
			e.printStackTrace();
			return 0;
		}
	}
	
	private static float getGradientY(int x, int y, int resolution) {
		int index = yGridPoints.length-numOfBits(resolution)+numOfBits(16)-1;
		try {
			return yGridPoints[index][x][y];
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
	private static float dotGridGradient(int ix, int iy, float x, float y, int resolution) {

	    // Compute the distance vector
		float dx = x/resolution - ix;
		float dy = y/resolution - iy;

	    // Compute the dot-product
		float gx = getGradientX(ix, iy, resolution);
		float gy = getGradientY(ix, iy, resolution);
		float gr = (float)Math.sqrt((gx*gx+gy*gy));
		gx /= gr;
		gy /= gr;
	    return (dx*gx + dy*gy);
	}

	// Compute Perlin noise at coordinates x, y
	private static float perlin(int x, int y, int resolution, int resolution2, boolean ridged) {

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
	    	value = 1 - (float)Math.sqrt(Math.abs(lerp(ix0, ix1, sy)));
	    else
	    	value = lerp(ix0, ix1, sy)*0.5f + 0.5f;
	    if(value > 1)
	    	value = 1;
	    return value;
	}
	
	// Returns how many bits a number is long:
	private static int numOfBits(int num) {
		int log = 0;
	    if( ( num & 0xffff0000 ) != 0 ) { num >>>= 16; log = 16; }
	    if( num >= 256 ) { num >>>= 8; log += 8; }
	    if( num >= 16  ) { num >>>= 4; log += 4; }
	    if( num >= 4   ) { num >>>= 2; log += 2; }
	    return log + ( num >>> 1 );
	}
	
	// Calculate all grid points that will be needed to prevent double calculating them.
	private static void calculateGridPoints(int x, int y, int width, int height, int scale, long l1, long l2, long l3, int worldAnd) {
		int bits = numOfBits(scale)-numOfBits(16)+1;
		// Create one gridpoint more, just in case...
		width += scale;
		height += scale;
		xGridPoints = new float[bits][][];
		yGridPoints = new float[bits][][];
		for(int i = 0; scale >= 16; scale >>= 1, ++i) {
			int resolution = scale;
			int localAnd = worldAnd/resolution;
		    // Determine grid cell coordinates of all cells that points can be in:
			float[][] xGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
			float[][] yGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
			int numX = 0, numY = 0;
			int x0 = 0;
			for(int ix = x; ix < x+width; ix += scale) {
				numY = 0;
				x0 = ix/resolution & localAnd;
				int y0 = 0;
				for(int iy = y; iy < y+height; iy += scale) {
				    y0 = iy/resolution & localAnd;
					xGrid[numX][numY] = generateGradient(x0, y0, 0, l1, l2, l3, resolution);
					yGrid[numX][numY] = generateGradient(x0, y0, 1, l1, l2, l3, resolution);
					numY++;
				}
				xGrid[numX][numY] = generateGradient(x0, (y0+1) & localAnd, 0, l1, l2, l3, resolution);
				yGrid[numX][numY] = generateGradient(x0, (y0+1) & localAnd, 1, l1, l2, l3, resolution);
				numX++;
			}
			numY = 0;
			int y0 = 0;
			for(int iy = y; iy < y+height; iy += scale) {
			    y0 = iy/resolution & localAnd;
				xGrid[numX][numY] = generateGradient((x0+1) & localAnd, y0, 0, l1, l2, l3, resolution);
				yGrid[numX][numY] = generateGradient((x0+1) & localAnd, y0, 1, l1, l2, l3, resolution);
				numY++;
			}
			//System.out.println((x0*resolution)+" "+(y0*resolution)+" "+x+" "+y);
			xGrid[numX][numY] = generateGradient((x0+1) & localAnd, (y0+1) & localAnd, 0, l1, l2, l3, resolution);
			yGrid[numX][numY] = generateGradient((x0+1) & localAnd, (y0+1) & localAnd, 1, l1, l2, l3, resolution);
			numY++;
			numX++;
			// Copy the values into smaller arrays and put them into the array containing all grid points:
			float[][] xGridR = new float[numX+1][numY+1];
			float[][] yGridR = new float[numX+1][numY+1];
			for(int ix = 0; ix < numX+1; ix++) {
				System.arraycopy(xGrid[ix], 0, xGridR[ix], 0, numY+1);
				System.arraycopy(yGrid[ix], 0, yGridR[ix], 0, numY+1);
				for(int iy = 0; iy < numY; iy++) {
					if(xGridR[ix][iy] < -1)
						System.out.println("problematic value at " + ix+" "+ iy);
				}
			}
			xGridPoints[i] = xGridR;
			yGridPoints[i] = yGridR;
		}
	}
	
	public static float[][] generateMapFragment(int x, int y, int width, int height, int scale, long seed, int worldAnd) {
		float[][] map = new float[width][height];
		float factor = 0.5F;
		float sum = 0;
		Random r = new Random(seed);
		long l1 = r.nextLong();
		long l2 = r.nextLong();
		long l3 = r.nextLong();
		calculateGridPoints(x, y, width, height, scale, l1, l2, l3, worldAnd);
		for(; scale >= 16; scale >>= 2) {
			int resolution = scale;
			int resolution2 = resolution-1;
		    int x0 = x & ~resolution2;
		    int y0 = y & ~resolution2;
			
			for (int x1 = x; x1 < width + x; x1++) {
				for (int y1 = y; y1 < height + y; y1++) {
					map[x1 - x][y1 - y] += factor*perlin(x1-x0, y1-y0, resolution, resolution2, scale >= 256);
				}
			}
			sum += factor;
			factor *= 0.25F;
		}
		
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] /= sum;
			}
		}
		
		return map;
	}
}
