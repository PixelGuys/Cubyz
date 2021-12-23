package cubyz.world.terrain;

import cubyz.utils.datastructures.Cache;
import cubyz.world.World;

public class ClimateMap {
	private static final int CACHE_SIZE = 1 << 8; // Must be a power of 2!
	private static final int CACHE_MASK = CACHE_SIZE - 1;
	private static final int ASSOCIATIVITY = 4;
	private static final Cache<ClimateMapFragment> cache = new Cache<ClimateMapFragment>(new ClimateMapFragment[CACHE_SIZE][ASSOCIATIVITY]);
	private static World world = null;
	public static BiomePoint[][] getBiomeMap(World world, int wx, int wz, int width, int height) {
		if (world != ClimateMap.world) {
			cache.clear(); // Clear the cache if the world changed!
			ClimateMap.world = world;
		}
		
		BiomePoint[][] map = new BiomePoint[width/MapFragment.BIOME_SIZE][height/MapFragment.BIOME_SIZE];
		int wxStart = wx & ~ClimateMapFragment.MAP_MASK;
		int wzStart = wz & ~ClimateMapFragment.MAP_MASK;
		int wxEnd = wx+width & ~ClimateMapFragment.MAP_MASK;
		int wzEnd = wz+height & ~ClimateMapFragment.MAP_MASK;
		for(int x = wxStart; x <= wxEnd; x += ClimateMapFragment.MAP_SIZE) {
			for(int z = wzStart; z <= wzEnd; z += ClimateMapFragment.MAP_SIZE) {
				ClimateMapFragment mapPiece = getOrGenerateFragment(world, x, z);
				// Offset of the indices in the result map:
				int xOffset = (x - wx) >> MapFragment.BIOME_SHIFT;
				int zOffset = (z - wz) >> MapFragment.BIOME_SHIFT;
				// Go through all indices in the mapPiece:
				for(int lx = 0; lx < mapPiece.map.length; lx++) {
					int resultX = lx + xOffset;
					if (resultX < 0 || resultX >= map.length) continue;
					for(int lz = 0; lz < mapPiece.map[0].length; lz++) {
						int resultZ = lz + zOffset;
						if (resultZ < 0 || resultZ >= map.length) continue;
						map[resultX][resultZ] = mapPiece.map[lx][lz];
					}
				}
			}
		}
		return map;
	}
	
	private static class ClimateMapFragmentComparator {
		private final int wx, wz;
		private ClimateMapFragmentComparator(int wx, int wz) {
			this.wx = wx;
			this.wz = wz;
		}
		@Override
		public boolean equals(Object other) {
			if (other instanceof ClimateMapFragment) {
				return ((ClimateMapFragment)other).wx == wx && ((ClimateMapFragment)other).wz == wz;
			}
			return false;
		}
	}
	
	public static ClimateMapFragment getOrGenerateFragment(World world, int wx, int wz) {
		int hash = ClimateMapFragment.hashCode(wx, wz) & CACHE_MASK;
		ClimateMapFragment ret = cache.find(new ClimateMapFragmentComparator(wx, wz), hash);
		if (ret != null) return ret;
		synchronized(cache.cache[hash]) {
			// Try again in case it was already generated in another thread:
			ret = cache.find(new ClimateMapFragmentComparator(wx, wz), hash);
			if (ret != null) return ret;
			ret = new ClimateMapFragment(world, wx, wz);
			world.chunkManager.climateGenerator.generateMapFragment(ret);
			cache.addToCache(ret, ret.hashCode() & CACHE_MASK);
			return ret;
		}
	}
}
