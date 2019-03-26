package io.cubyz.world;

import java.util.Random;

/**
 * Perlin Noise generator for Worlds
 * @author zenith391
 */
public class Noise {
	private static Random r = new Random();

	static float get2DPerlinNoiseValue(float x, float y, float res, int seed)
	{
	    float tempX,tempY;
	    int x0,y0,ii,jj,gi0,gi1,gi2,gi3;
	    float unit = (float) (1.0f/Math.sqrt(2));
	    float tmp,s,t,u,v,Cx,Cy,Li1,Li2;
	    float gradient2[][] = {{unit,unit},{-unit,unit},{unit,-unit},{-unit,-unit},{1,0},{-1,0},{0,1},{0,-1}};

	    int perm[] =
	       {151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,
	        142,8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,
	        203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
	        74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,
	        105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,
	        187,208,89,18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,
	        64,52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,
	        47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,
	        153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,
	        112,104,218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,
	        235,249,14,239,107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,
	        127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,
	        156,180};
	    int se = seed;
	    for (int i = 0; i < perm.length; i++) {
	    	if (perm[i] < 1) {
	    		perm[i] = 1;
	    	}
	    	perm[i] = (perm[i] * se) % perm[i];
	    	se--;
	    	if (se < 1) {
	    		se = seed;
	    	}
	    	if (perm[i] < 1) {
	    		perm[i] = -perm[i];
	    	}
	    }
	    x /= res;
	    y /= res;
	    x0 = (int)(x);
	    y0 = (int)(y);
	    ii = x0 & 255;
	    jj = y0 & 255;
	    gi0 = perm[ii + perm[jj]] % 8;
	    gi1 = perm[ii + 1 + perm[jj]] % 8;
	    gi2 = perm[ii + perm[jj + 1]] % 8;
	    gi3 = perm[ii + 1 + perm[jj + 1]] % 8;
	    tempX = x-x0;
	    tempY = y-y0;
	    s = gradient2[gi0][0]*tempX + gradient2[gi0][1]*tempY;
	    tempX = x-(x0+1);
	    tempY = y-y0;
	    t = gradient2[gi1][0]*tempX + gradient2[gi1][1]*tempY;
	    tempX = x-x0;
	    tempY = y-(y0+1);
	    u = gradient2[gi2][0]*tempX + gradient2[gi2][1]*tempY;
	    tempX = x-(x0+1);
	    tempY = y-(y0+1);
	    v = gradient2[gi3][0]*tempX + gradient2[gi3][1]*tempY;
	    tmp = x-x0;
	    Cx = 3 * tmp * tmp - 2 * tmp * tmp * tmp;

	    Li1 = s + Cx*(t-s);
	    Li2 = u + Cx*(v-u);

	    tmp = y - y0;
	    Cy = 3 * tmp * tmp - 2 * tmp * tmp * tmp;

	    return 0.5f*(1+Li1 + Cy*(Li2-Li1));
	}

	private static int seed;
	private static int resolution;
	private static int resolution2;
	// Calculate the gradient instead of storing it.
	// This is inefficient(since it is called every time), but allows infinite chunk generation.
	// TODO: Make this faster
	private static float getGradient(int x, int y, int i) {
    	r.setSeed(seed);
    	r.setSeed(r.nextLong()*x+r.nextLong()*y+r.nextLong()*i);
    	return 2 * r.nextFloat() - 1;
    }
	/* Function to linearly interpolate between a0 and a1
	 * Weight w should be in the range [0.0, 1.0]
	 *
	 * as an alternative, this slightly faster equivalent function (macro) can be used:
	 * #define lerp(a0, a1, w) (a0 + w*(a1 - a0)) 
	 */
	private static float lerp(float a0, float a1, float w) {
	    return (1.0f - w)*a0 + w*a1;
	}

	// Computes the dot product of the distance and gradient vectors.
	private static float dotGridGradient(int ix, int iy, int x, int y) {

	    // Precomputed (or otherwise) gradient vectors at each grid node

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
	    float sx = (x&resolution2)/(float)resolution;
	    float sy = (y&resolution2)/(float)resolution;

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
	
	public static float[][] generateMapFragment(int x, int y, int width, int height, int scale, int seed) {
		float[][] map = new float[width][height];
		float factor = 0.45F;
		float sum = 0;
		for(; scale >= 16; scale >>= 1) {
			resolution = scale;
			resolution2 = resolution-1;
			Noise.seed = seed;
		
			for (int x1 = x; x1 < width + x; x1++) {
				for (int y1 = y; y1 < height + y; y1++) {
					//map[x1 - x][y1 - y] = get2DPerlinNoiseValue(x1, y1, scale, seed);
					map[x1 - x][y1 - y] += factor*perlin(x1, y1);
				}
			}
			sum += factor;
			factor *= 0.55F;
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
