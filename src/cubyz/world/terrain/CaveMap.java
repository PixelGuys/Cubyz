package cubyz.world.terrain;

import cubyz.utils.datastructures.Cache;
import cubyz.world.Chunk;
import cubyz.world.ChunkData;

/**
 * Stores cave data (whether a block is solid or not).
 * This is used mainly for the surface structure und plants in caves.
 */

public class CaveMap {
	private static final int CACHE_SIZE = 1 << 9; // Must be a power of 2!
	private static final int CACHE_MASK = CACHE_SIZE - 1;
	private static final int ASSOCIATIVITY = 8; // 512 MiB Cache size
	private static final Cache<CaveMapFragment> cache = new Cache<>(new CaveMapFragment[CACHE_SIZE][ASSOCIATIVITY]);

	private static TerrainGenerationProfile profile;

	private final Chunk reference;

	private final CaveMapFragment[] fragments = new CaveMapFragment[8];

	public CaveMap(Chunk chunk) {
		reference = chunk;
		fragments[0] = getOrGenerateFragment(chunk.wx - chunk.getWidth(), chunk.wy - chunk.getWidth(), chunk.wz - chunk.getWidth(), chunk.voxelSize);
		fragments[1] = getOrGenerateFragment(chunk.wx - chunk.getWidth(), chunk.wy - chunk.getWidth(), chunk.wz + chunk.getWidth(), chunk.voxelSize);
		fragments[2] = getOrGenerateFragment(chunk.wx - chunk.getWidth(), chunk.wy + chunk.getWidth(), chunk.wz - chunk.getWidth(), chunk.voxelSize);
		fragments[3] = getOrGenerateFragment(chunk.wx - chunk.getWidth(), chunk.wy + chunk.getWidth(), chunk.wz + chunk.getWidth(), chunk.voxelSize);
		fragments[4] = getOrGenerateFragment(chunk.wx + chunk.getWidth(), chunk.wy - chunk.getWidth(), chunk.wz - chunk.getWidth(), chunk.voxelSize);
		fragments[5] = getOrGenerateFragment(chunk.wx + chunk.getWidth(), chunk.wy - chunk.getWidth(), chunk.wz + chunk.getWidth(), chunk.voxelSize);
		fragments[6] = getOrGenerateFragment(chunk.wx + chunk.getWidth(), chunk.wy + chunk.getWidth(), chunk.wz - chunk.getWidth(), chunk.voxelSize);
		fragments[7] = getOrGenerateFragment(chunk.wx + chunk.getWidth(), chunk.wy + chunk.getWidth(), chunk.wz + chunk.getWidth(), chunk.voxelSize);
	}

	public boolean isSolid(int relX, int relY, int relZ) {
		int wx = relX + reference.wx;
		int wy = relY + reference.wy;
		int wz = relZ + reference.wz;
		int index = 0;
		if(wx - fragments[0].wx >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 4;
		}
		if(wy - fragments[0].wy >= CaveMapFragment.HEIGHT*reference.voxelSize) {
			index += 2;
		}
		if(wz - fragments[0].wz >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 1;
		}
		relX = wx - fragments[index].wx;
		relY = (wy - fragments[index].wy)/reference.voxelSize;
		relZ = wz - fragments[index].wz;
		long height = fragments[index].getHeightData(relX, relZ);
		return (height & 1L<<relY) != 0;
	}

	public int getHeightData(int relX, int relZ) {
		int wx = relX + reference.wx;
		int wz = relZ + reference.wz;
		int index = 0;
		if(wx - fragments[0].wx >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 4;
		}
		if(wz - fragments[0].wz >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 1;
		}
		int deltaY = reference.wy - fragments[0].wy;
		if(deltaY >= CaveMapFragment.HEIGHT*reference.voxelSize) {
			index += 2;
			deltaY -= CaveMapFragment.HEIGHT*reference.voxelSize;
		}
		relX = wx - fragments[index].wx;
		relZ = wz - fragments[index].wz;
		long height = fragments[index].getHeightData(relX, relZ);
		if(deltaY == 0) {
			return (int)height;
		} else {
			return (int)(height >>> 32);
		}
	}

	public int findTerrainChangeAbove(int relX, int relZ, int y) {
		int wx = relX + reference.wx;
		int wz = relZ + reference.wz;
		int index = 0;
		if(wx - fragments[0].wx >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 4;
		}
		if(wz - fragments[0].wz >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 1;
		}
		int relativeY = (y + reference.wy - fragments[0].wy)/reference.voxelSize;
		relX = wx - fragments[index].wx;
		relZ = wz - fragments[index].wz;
		long height = 0;
		boolean startFilled = false;
		int result = relativeY;
		if(relativeY < CaveMapFragment.HEIGHT) {
			// Check the lower part first.
			height = fragments[index].getHeightData(relX, relZ) >> relativeY;
			startFilled = (height & 1) != 0;
			if(startFilled) {
				height = ~height;
			}
		}
		if(height == 0) {
			// Check the upper part:
			result = Math.max(CaveMapFragment.HEIGHT, result);
			relativeY -= CaveMapFragment.HEIGHT;
			height = fragments[index+2].getHeightData(relX, relZ);
			if(relativeY >= 0) {
				height >>= relativeY;
				startFilled = (height & 1) != 0;
			}
			if(startFilled) {
				height = ~height;
			}
		}
		result += Long.numberOfTrailingZeros(height);
		return result*reference.voxelSize + fragments[0].wy - reference.wy;
	}

	public int findTerrainChangeBelow(int relX, int relZ, int y) {
		int wx = relX + reference.wx;
		int wz = relZ + reference.wz;
		int index = 0;
		if(wx - fragments[0].wx >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 4;
		}
		if(wz - fragments[0].wz >= CaveMapFragment.WIDTH*reference.voxelSize) {
			index += 1;
		}
		int relativeY = (y + reference.wy - fragments[0].wy)/reference.voxelSize;
		relX = wx - fragments[index].wx;
		relZ = wz - fragments[index].wz;
		long height = 0;
		boolean startFilled = false;
		int result = relativeY;
		if(relativeY >= CaveMapFragment.HEIGHT) {
			relativeY -= CaveMapFragment.HEIGHT;
			// Check the upper part first.
			height = fragments[index+2].getHeightData(relX, relZ) << 63-relativeY;
			startFilled = (height & 1L<<63) != 0;
			if(startFilled) {
				height = ~height & -1L << 63-relativeY;
			}
			relativeY += CaveMapFragment.HEIGHT;
		}
		if(height == 0) {
			// Check the upper part:
			result = Math.min(CaveMapFragment.HEIGHT - 1, result);
			height = fragments[index].getHeightData(relX, relZ);
			if(relativeY >= 0) {
				height <<= 63-relativeY;
				startFilled = (height & 1L<<63) != 0;
			}
			if(startFilled) {
				height = ~height;
			}
		}
		result -= Long.numberOfLeadingZeros(height);
		return result*reference.voxelSize + fragments[0].wy - reference.wy;
	}
	
	private static CaveMapFragment getOrGenerateFragment(int wx, int wy, int wz, int voxelSize) {
		wx &= ~(CaveMapFragment.WIDTH_MASK*voxelSize | voxelSize-1);
		wy &= ~(CaveMapFragment.HEIGHT_MASK*voxelSize | voxelSize-1);
		wz &= ~(CaveMapFragment.WIDTH_MASK*voxelSize | voxelSize-1);
		ChunkData compare = new ChunkData(wx, wy, wz, voxelSize);
		int hash = compare.hashCode() & CACHE_MASK;
		CaveMapFragment ret = cache.find(compare, hash);
		if (ret != null) return ret;
		synchronized(cache.cache[hash]) {
			// Try again in case it was already generated in another thread:
			ret = cache.find(new ChunkData(wx, wy, wz, voxelSize), hash);
			if (ret != null) return ret;
			ret = new CaveMapFragment(wx, wy, wz, voxelSize, profile);
			cache.addToCache(ret, hash & CACHE_MASK);
			return ret;
		}
	}

	public static void cleanup() {
		cache.clear();
	}

	public static void init(TerrainGenerationProfile profile) {
		CaveMap.profile = profile;
	}
}
