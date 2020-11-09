package io.cubyz.world;

import java.util.Random;

import io.cubyz.math.CubyzMath;

/**
 * Fractal Noise Generator for world generation.
 * @author IntegratedQuantum
 */

public class Noise {
	static long getSeed(int x, int y, int offsetX, int offsetY, int worldSizeX, int worldSizeY, long seed, int scale) {
		Random rand = new Random(seed*(scale | 1));
		long l1 = rand.nextLong() | 1;
		long l2 = rand.nextLong() | 1;
		return (((long)(CubyzMath.worldModulo(offsetX + x, worldSizeX)))*l1) ^ seed ^ (((long)(CubyzMath.worldModulo(offsetY + y, worldSizeY)))*l2);
	}
	private static void generateFractalTerrain(int wx, int wy, int x0, int y0, int width, int height, int scale, long seed, int worldSizeX, int worldSizeZ, float[][] map) {
		int max =scale+1;
		int and = scale-1;
		float[][] bigMap = new float[max][max];
		int offsetX = wx&(~and);
		int offsetY = wy&(~and);
		Random rand = new Random();
		// Generate the 4 corner points of this map using a coordinate-depending seed:
		rand.setSeed(getSeed(0, 0, offsetX, offsetY, worldSizeX, worldSizeZ, seed, scale));
		bigMap[0][0] = rand.nextFloat();
		rand.setSeed(getSeed(0, scale, offsetX, offsetY, worldSizeX, worldSizeZ, seed, scale));
		bigMap[0][scale] = rand.nextFloat();
		rand.setSeed(getSeed(scale, 0, offsetX, offsetY, worldSizeX, worldSizeZ, seed, scale));
		bigMap[scale][0] = rand.nextFloat();
		rand.setSeed(getSeed(scale, scale, offsetX, offsetY, worldSizeX, worldSizeZ, seed, scale));
		bigMap[scale][scale] = rand.nextFloat();
		// Increase the "grid" of points with already known heights in each round by a factor of 2×2, like so(# marks the gridpoints of the first grid, * the points of the second grid and + the points of the third grid(and so on…)):
		/*
			#+*+#
			+++++
			*+*+*
			+++++
			#+*+#
		 */
		// Each new gridpoint gets the average height value of the surrounding known grid points which is afterwards offset by a random value. Here is a visual representation of this process(with random starting values):
		/*
		█░▒▓						small							small
			█???█	grid	█?█?█	random	█?▓?█	grid	██▓██	random	██▓██
			?????	resize	?????	change	?????	resize	▓▓▒▓█	change	▒▒▒▓█
			?????	→→→→	▒?▒?▓	→→→→	▒?░?▓	→→→→	▒▒░▒▓	→→→→	▒░░▒▓
			?????			?????	of new	?????			░░░▒▓	of new	░░▒▓█
			 ???▒			 ?░?▒	values	 ?░?▒			 ░░▒▒	values	 ░░▒▒
			 
			 Another important thing to note is that the side length of the grid has to be 2^n + 1 because every new gridpoint needs a new neighbor. So the rightmost column and the bottom row are already part of the next map piece.
			 One other important thing in the implementation of this algorithm is that the relative height change has to decrease the in every iteration. Otherwise the terrain would look really noisy.
		 */
		for(int res = scale*2; res > 0; res >>>= 1) {
			// x coordinate on the grid:
			for(int x = 0; x < max; x += res<<1) {
				for(int y = res; y+res < max; y += res<<1) {
					if(x == 0 || x == scale) rand.setSeed(getSeed(x, y, offsetX, offsetY, worldSizeX, worldSizeZ, seed, res)); // If the point touches another region, the seed has to be coordinate dependent.
					bigMap[x][y] = (bigMap[x][y-res]+bigMap[x][y+res])/2 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[x][y] > 1.0f) bigMap[x][y] = 1.0f;
					if(bigMap[x][y] < 0.0f) bigMap[x][y] = 0.0f;
				}
			}
			// y coordinate on the grid:
			for(int x = res; x+res < max; x += res<<1) {
				for(int y = 0; y < max; y += res<<1) {
					if(y == 0 || y == scale) rand.setSeed(getSeed(x, y, offsetX, offsetY, worldSizeX, worldSizeZ, seed, res)); // If the point touches another region, the seed has to be coordinate dependent.
					bigMap[x][y] = (bigMap[x-res][y]+bigMap[x+res][y])/2 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[x][y] > 1.0f) bigMap[x][y] = 1.0f;
					if(bigMap[x][y] < 0.0f) bigMap[x][y] = 0.0f;
				}
			}
			// No coordinate on the grid:
			for(int x = res; x+res < max; x += res<<1) {
				for(int y = res; y+res < max; y += res<<1) {
					bigMap[x][y] = (bigMap[x-res][y-res]+bigMap[x+res][y-res]+bigMap[x-res][y+res]+bigMap[x+res][y+res])/4 + (rand.nextFloat()-0.5f)*res/scale;
					if(bigMap[x][y] > 1.0f) bigMap[x][y] = 1.0f;
					if(bigMap[x][y] < 0.0f) bigMap[x][y] = 0.0f;
				}
			}
		}
		for(int px = 0; px < width; px++) {
			for(int py = 0; py < height; py++) {
				map[x0 + px][y0 + py] = bigMap[(wx&and)+px][(wy&and)+py];
				if(map[x0 + px][y0 + py] >= 1.0f)
					map[x0 + px][y0 + py] = 0.9999f;
			}
		}
	}
	public static float[][] generateFractalTerrain(int wx, int wy, int width, int height, int scale, long seed, int worldSizeX, int worldSizeZ) {
		float[][] map = new float[width][height];
		for(int x0 = 0; x0 < width; x0 += scale) {
			for(int y0 = 0; y0 < height; y0 += scale) {
				generateFractalTerrain(wx + x0, wy + y0, x0, y0, Math.min(width-x0, scale), Math.min(height-y0, scale), scale, seed, worldSizeX, worldSizeZ, map);
			}
		}
		return map;
	}
	static float dist(float x, float y, float z) {
		return (float)Math.sqrt(x*x + y*y + z*z);
	}
	// Use Fractal terrain generation as a base and use the intersection of the fractally generated terrain with a 3d worley noise map to get an interesting map.
	// A little slower than pure fractal terrain, but a lot more detail-rich.
	public static float[][] generateFractalWorleyNoise(int wx, int wy, int width, int height, int scale, long seed, int worldSizeX, int worldSizeZ) {
		float [][] map = generateFractalTerrain(wx, wy, width, height, scale, seed, worldSizeX, worldSizeZ);
		int num = 1;
		float[] pointsX = new float[num*25], pointsY = new float[num*25], pointsZ = new float[num*25];
		int index = 0;
		float fac = 2048;
		for(int x = -2; x <= 2; x++) {
			for(int y = -2; y <= 2; y++) {
				Random r = new Random(getSeed(wx, wy, x*width, y*height, worldSizeX, worldSizeZ, seed, scale));
				for(int i = 0; i < num; i++) {
					pointsX[index] = x*width+r.nextFloat()*width;
					pointsY[index] = y*width+r.nextFloat()*height;
					pointsZ[index] = r.nextFloat()*fac;
					index++;
				}
			}
		}
		for(int x = 0; x < width; x++) {
			for(int y = 0; y < height; y++) {
				float closest = Float.MAX_VALUE;
				for(int i = 0; i < index; i++) {
					float dist = dist(x-pointsX[i], y-pointsY[i], map[x][y]*fac-pointsZ[i]);
					if(dist < closest) closest = dist;
				}
				map[x][y] = 1.0f-(float)Math.pow(closest/400.0f, 1);
				if(map[x][y] < 0.1f) map[x][y] = 0.1f;
			}
		}
		return map;
	}
}
