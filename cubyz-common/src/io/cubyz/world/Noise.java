package io.cubyz.world;

import java.util.Random;

/**
 * Perlin noise generator for worlds
 * @author zenith391, IntegratedQuantum
 */
public class Noise {
	private static Random r = new Random();
	private static long l1, l2, l3;

	private static float[][][] xGridPoints; // [scale][x][y]
	private static float[][][] yGridPoints; // [scale][x][y]

	private static int resolution;
	private static int resolution2;
	// Calculate the gradient instead of storing it.
	// This is inefficient(since it is called every time), but allows infinite chunk generation.
	private static float generateGradient(int x, int y, int i) {
		r.setSeed(l1*x+l2*y+l3*i+resolution);
    	return 2 * r.nextFloat() - 1;
    }
	
	private static float getGradientX(int x, int y) {
		int index = xGridPoints.length-numOfBits(resolution)+numOfBits(16)-1;
		try {
			return xGridPoints[index][x][y];
		} catch (ArrayIndexOutOfBoundsException e) { // quick and dirty fix
			e.printStackTrace();
			return 0;
		}
	}
	
	private static float getGradientY(int x, int y) {
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
	private static float dotGridGradient(int ix, int iy, float x, float y) {

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
	private static float perlin(int x, int y) {

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

	    n0 = dotGridGradient(x0, y0, x, y);
	    n1 = dotGridGradient(x1, y0, x, y);
	    ix0 = lerp(n0, n1, sx);

	    n0 = dotGridGradient(x0, y1, x, y);
	    n1 = dotGridGradient(x1, y1, x, y);
	    ix1 = lerp(n0, n1, sx);

	    value = 0.5F*lerp(ix0, ix1, sy) + 0.5F;
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
	private static void calculateGridPoints(int x, int y, int width, int height, int scale) {
		int bits = numOfBits(scale)-numOfBits(16)+1;
		// Create one gridpoint more, just in case...
		width += scale;
		height += scale;
		xGridPoints = new float[bits][][];
		yGridPoints = new float[bits][][];
		for(int i = 0; scale >= 16; scale >>= 1, ++i) {
			resolution = scale;
			resolution2 = resolution-1;
		    // Determine grid cell coordinates of all cells that points can be in:
			float[][] xGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
			float[][] yGrid = new float[width/scale + 3][height/scale + 3]; // Simply assume the absolute maximum number of grid points are generated.
			int numX = 0, numY = 0;
			int x0 = 0;
			for(int ix = x; ix < x+width; ix += scale) {
				numY = 0;
				x0 = ix/resolution;
				int y0 = 0;
				for(int iy = y; iy < y+height; iy += scale) {
				    y0 = iy/resolution;
					xGrid[numX][numY] = generateGradient(x0, y0, 0);
					yGrid[numX][numY] = generateGradient(x0, y0, 1);
					numY++;
				}
				xGrid[numX][numY] = generateGradient(x0, y0+1, 0);
				yGrid[numX][numY] = generateGradient(x0, y0+1, 1);
				numX++;
			}
			numY = 0;
			int y0 = 0;
			for(int iy = y; iy < y+height; iy += scale) {
			    y0 = iy/resolution;
				xGrid[numX][numY] = generateGradient(x0+1, y0, 0);
				yGrid[numX][numY] = generateGradient(x0+1, y0, 1);
				numY++;
			}
			//System.out.println((x0*resolution)+" "+(y0*resolution)+" "+x+" "+y);
			xGrid[numX][numY] = generateGradient(x0+1, y0+1, 0);
			yGrid[numX][numY] = generateGradient(x0+1, y0+1, 1);
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
	static int offsetX, offsetY;
	static long seed;
	static long getSeed(int x, int y) {
		return (((long)(offsetX+x)) << 16)^seed^(((long)(offsetY+y)) << 32);
	}
	public static synchronized float[][] generateFractalTerrain(int x, int y, int width, int height, int scale, long seed) {
		Noise.seed = seed;
		float[][] map = new float[width][height];
		int max =scale+1;
		int and = scale-1;
		float[][] bigMap = new float[max][max];
		offsetX = x&(~and);
		offsetY = y&(~and);
		Random rand = new Random();
		rand.setSeed(getSeed(0, 0));
		bigMap[0][0] = rand.nextFloat();
		rand.setSeed(getSeed(0, scale));
		bigMap[0][scale] = rand.nextFloat();
		rand.setSeed(getSeed(scale, 0));
		bigMap[scale][0] = rand.nextFloat();
		rand.setSeed(getSeed(scale, scale));
		bigMap[scale][scale] = rand.nextFloat();
		for(int res = scale*2; res > 0; res >>>= 1) {
			// x coordinate on the grid:
			for(int px = 0; px < max; px += res<<1) {
				for(int py = res; py+res < max; py += res<<1) {
					if(px == 0 || px == scale) rand.setSeed(getSeed(px, py));
					bigMap[px][py] = (bigMap[px][py-res]+bigMap[px][py+res])/2 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[px][py] > 1.0f) bigMap[px][py] = 1.0f;
					if(bigMap[px][py] < 0.0f) bigMap[px][py] = 0.0f;
				}
			}
			// y coordinate on the grid:
			for(int px = res; px+res < max; px += res<<1) {
				for(int py = 0; py < max; py += res<<1) {
					if(py == 0 || py == scale) rand.setSeed(getSeed(px, py));
					bigMap[px][py] = (bigMap[px-res][py]+bigMap[px+res][py])/2 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[px][py] > 1.0f) bigMap[px][py] = 1.0f;
					if(bigMap[px][py] < 0.0f) bigMap[px][py] = 0.0f;
				}
			}
			// No coordinate on the grid:
			for(int px = res; px+res < max; px += res<<1) {
				for(int py = res; py+res < max; py += res<<1) {
					bigMap[px][py] = (bigMap[px-res][py-res]+bigMap[px+res][py-res]+bigMap[px-res][py+res]+bigMap[px+res][py+res])/4 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[px][py] > 1.0f) bigMap[px][py] = 1.0f;
					if(bigMap[px][py] < 0.0f) bigMap[px][py] = 0.0f;
				}
			}
		}
		for(int px = 0; px < width; px++) {
			for(int py = 0; py < height; py++) {
				try {
					map[px][py] = bigMap[(x&and)+px][(y&and)+py];
					if(map[px][py] >= 1.0f)
						map[px][py] = 0.9999f;
				} catch(Exception e) {
					map[px][py] = 0;
				}
			}
		}
		return map;
	}
	
	public static synchronized float[][] generateMapFragment(int x, int y, int width, int height, int scale, long seed) {
		float[][] map = new float[width][height];
		float factor = 0.45F;
		float sum = 0;
		r.setSeed(seed);
		l1 = r.nextLong();
		l2 = r.nextLong();
		l3 = r.nextLong();
		calculateGridPoints(x, y, width, height, scale);
		for(; scale >= 16; scale >>= 1) {
			resolution = scale;
			resolution2 = resolution-1;
		    int x0 = x & ~resolution2;
		    int y0 = y & ~resolution2;
			
			for (int x1 = x; x1 < width + x; x1++) {
				for (int y1 = y; y1 < height + y; y1++) {
					map[x1 - x][y1 - y] += factor*perlin(x1-x0, y1-y0);
				}
			}
			sum += factor;
			factor *= 0.55F;
		}
		
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] /= sum;
			}
		}
		
		return map;
	}
	
	
}
