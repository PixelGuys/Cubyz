package cubyz.world.terrain.noise;

import cubyz.utils.FastRandom;
import cubyz.world.ChunkData;

/**
 * Like FractalNoise.java, except in 3D and it generates values on demand and caches results, instead of generating everything at once.
 */
public class Cached3DFractalNoise extends ChunkData {

	private final float[][][] cache;
	private final int voxelShift;
	private final long seedX, seedY, seedZ;
	private final int scale;

	public Cached3DFractalNoise(int wx, int wy, int wz, int voxelSize, int size, long seed, int scale) {
		super(wx, wy, wz, voxelSize);
		int maxSize = size/voxelSize;
		voxelShift = Integer.numberOfTrailingZeros(voxelSize);
		cache = new float[maxSize + 1][maxSize + 1][maxSize + 1];
		FastRandom rand = new FastRandom(seed);
		seedX = rand.nextInt();
		seedY = rand.nextInt();
		seedZ = rand.nextInt();
		this.scale = scale;
		scale /= voxelSize;
		// Init the corners:
		for(int x = 0; x <= maxSize; x += scale) {
			for(int y = 0; y <= maxSize; y += scale) {
				for (int z = 0; z <= maxSize; z += scale) {
					cache[x][y][z] = (scale + 1 + scale*getGridValue(x, y, z))*voxelSize;
				}//                    ↑ sacrifice some resolution to reserve the value 0, for determining if the value was initialized. This prevents an expensive array initialization.
			}
		}
	}

	public float getRandomValue(int wx, int wy, int wz) {
		return FastRandom.nextFloat(wx*seedX ^ wy*seedY ^ wz*seedZ) - 0.5f;
	}

	private float getGridValue(int relX, int relY, int relZ) {
		return getRandomValue(wx + relX*voxelSize, wy + relY*voxelSize, wz + relZ*voxelSize);
	}

	private void generateRegion(int x, int y, int z, int voxelSize) {
		x &= ~(voxelSize-1);
		y &= ~(voxelSize-1);
		z &= ~(voxelSize-1);
		// Make sure that all higher points are generated:
		_getValue(x | voxelSize, y | voxelSize, z | voxelSize);

		int xMid = x + voxelSize/2;
		int yMid = y + voxelSize/2;
		int zMid = z + voxelSize/2;
		float randomFactor = voxelSize*this.voxelSize;
		for(int a = 0; a <= voxelSize; a += voxelSize) { // 2 coordinates on the grid.
			for(int b = 0; b <= voxelSize; b += voxelSize) {
				cache[x + a][y + b][zMid] = (cache[x + a][y + b][z] + cache[x + a][y + b][z + voxelSize])/2 + randomFactor*getGridValue(x + a, y + b, zMid); // x-y
				cache[x + a][yMid][z + b] = (cache[x + a][y][z + b] + cache[x + a][y + voxelSize][z + b])/2 + randomFactor*getGridValue(x + a, yMid, z + b); // x-z
				cache[xMid][y + a][z + b] = (cache[x][y + a][z + b] + cache[x + voxelSize][y + a][z + b])/2 + randomFactor*getGridValue(xMid, y + a, z + b); // y-z
			}
		}
		for(int a = 0; a <= voxelSize; a += voxelSize) { // 1 coordinate on the grid.
			cache[x + a][yMid][zMid] = (
						cache[x + a][yMid][z] + cache[x + a][yMid][z + voxelSize]
						+ cache[x + a][y][zMid] + cache[x + a][y + voxelSize][zMid]
					)/4 + randomFactor*getGridValue(x + a, yMid, zMid); // x
			cache[xMid][y + a][zMid] = (
						cache[xMid][y + a][z] + cache[xMid][y + a][z + voxelSize]
						+ cache[x][y + a][zMid] + cache[x + voxelSize][y + a][zMid]
					)/4 + randomFactor*getGridValue(xMid, y + a, zMid); // y
			cache[xMid][yMid][z + a] = (
						cache[xMid][y][z + a] + cache[xMid][y + voxelSize][z + a]
						+ cache[x][yMid][z + a] + cache[x + voxelSize][yMid][z + a]
					)/4 + randomFactor*getGridValue(xMid, yMid, z + a); // z
		}
		// Center point:
		cache[xMid][yMid][zMid] = (
					cache[xMid][yMid][z] + cache[xMid][yMid][z + voxelSize]
					+ cache[xMid][y][zMid] + cache[xMid][y + voxelSize][zMid]
					+ cache[x][yMid][zMid] + cache[x + voxelSize][yMid][zMid]
				)/6 + randomFactor*getGridValue(xMid, yMid, zMid);
	}

	private float _getValue(int x, int y, int z) {
		float value = cache[x][y][z];
		if(value != 0) return value;
		// Need to actually generate stuff now.
		int minShift = Math.min(Integer.numberOfTrailingZeros(x), Math.min(Integer.numberOfTrailingZeros(y), Integer.numberOfTrailingZeros(z)));
		generateRegion(x, y, z, 2 << minShift);
		return cache[x][y][z];
	}

	public float getValue(int wx, int wy, int wz) {
		int x = (wx - this.wx) >> voxelShift;
		int y = (wy - this.wy) >> voxelShift;
		int z = (wz - this.wz) >> voxelShift;
		return _getValue(x, y, z) - scale;
	}
}
