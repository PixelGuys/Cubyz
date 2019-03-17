package io.cubyz.world;

/**
 * Perlin Noise generator for Worlds
 * @author zenith391
 */
public class Noise {

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
	
	public static float[][] generateMap(int width, int height, int scale, int seed) {
		return generateMapFragment(0, 0, width, height, scale, seed);
	}
	
	public static float[][] generateMapFragment(int x, int y, int width, int height, int scale, int seed) {
		float[][] map = new float[width][height];
		
		for (int x1 = x; x1 < width + x; x1++) {
			for (int y1 = y; y1 < height + y; y1++) {
				map[x1 - x][y1 - y] = get2DPerlinNoiseValue(x1, y1, scale, seed);
			}
		}
		
		return map;
	}
	
	
}
