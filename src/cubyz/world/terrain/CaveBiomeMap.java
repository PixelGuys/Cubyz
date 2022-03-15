package cubyz.world.terrain;

import cubyz.utils.datastructures.Cache;
import cubyz.world.Chunk;
import cubyz.world.ChunkData;
import cubyz.world.World;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.noise.Cached3DFractalNoise;

public class CaveBiomeMap {
	private static final int CACHE_SIZE = 1 << 8; // Must be a power of 2!
	private static final int CACHE_MASK = CACHE_SIZE - 1;
	private static final int ASSOCIATIVITY = 8;
	private static final Cache<CaveBiomeMapFragment> cache = new Cache<>(new CaveBiomeMapFragment[CACHE_SIZE][ASSOCIATIVITY]);
	private static World world = null;

	private final Chunk reference;

	private final CaveBiomeMapFragment[] fragments = new CaveBiomeMapFragment[8];

	private final Cached3DFractalNoise noiseX, noiseY, noiseZ;

	public CaveBiomeMap(World world, Chunk chunk) {
		if (world != CaveBiomeMap.world) {
			cache.clear(); // Clear the cache if the world changed!
			CaveBiomeMap.world = world;
		}
		if(chunk.voxelSize >= 8) {
			noiseX = noiseY = noiseZ = null;
		} else {
			noiseX = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, world.getSeed() ^ 0x764923684396L, 64);
			noiseY = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, world.getSeed() ^ 0x6547835649265429L, 64);
			noiseZ = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, world.getSeed() ^ 0x56789365396783L, 64);
		}
		reference = chunk;
		fragments[0] = getOrGenerateFragment(world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[1] = getOrGenerateFragment(world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[2] = getOrGenerateFragment(world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[3] = getOrGenerateFragment(world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[4] = getOrGenerateFragment(world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[5] = getOrGenerateFragment(world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[6] = getOrGenerateFragment(world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[7] = getOrGenerateFragment(world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
	}

	public Biome getBiome(int relX, int relY, int relZ) {
		// TODO: return surface biome if close to surface.
		assert relX >= -32 && relX < reference.getWidth() + 32 : "x coordinate out of bounds: " + relX;
		assert relY >= -32 && relY < reference.getWidth() + 32 : "y coordinate out of bounds: " + relY;
		assert relZ >= -32 && relZ < reference.getWidth() + 32 : "z coordinate out of bounds: " + relZ;
		int wx = relX + reference.wx;
		int wy = relY + reference.wy;
		int wz = relZ + reference.wz;
		if(noiseX != null) {
			//                                                  ↓ intentionally cycled the noises to get different seeds.
			float valueX = noiseX.getValue(wx, wy, wz)*0.5f + noiseY.getRandomValue(wx, wy, wz)*8;
			float valueY = noiseY.getValue(wx, wy, wz)*0.5f + noiseZ.getRandomValue(wx, wy, wz)*8;
			float valueZ = noiseZ.getValue(wx, wy, wz)*0.5f + noiseX.getRandomValue(wx, wy, wz)*8;
			wx += valueX;
			wy += valueY;
			wz += valueZ;
		}

		int gridPointX = (wx + CaveBiomeMapFragment.CAVE_BIOME_SIZE) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK & ~CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		int gridPointY = (wy + CaveBiomeMapFragment.CAVE_BIOME_SIZE) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK & ~CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		int gridPointZ = (wz + CaveBiomeMapFragment.CAVE_BIOME_SIZE) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK & ~CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		int distanceX = wx - gridPointX;
		int distanceY = wy - gridPointY;
		int distanceZ = wz - gridPointZ;
		int totalDistance = Math.abs(distanceX) + Math.abs(distanceY) + Math.abs(distanceZ);
		if(totalDistance > CaveBiomeMapFragment.CAVE_BIOME_SIZE*3/2) {
			// Or with 1 to prevent errors if the value is 0.
			gridPointX += Math.signum(distanceX | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE;
			gridPointY += Math.signum(distanceY | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE;
			gridPointZ += Math.signum(distanceZ | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		}

		return _getBiome(gridPointX, gridPointY, gridPointZ);
	}

	private Biome _getBiome(int wx, int wy, int wz) {
		int index = 0;
		if(wx - fragments[0].wx >= CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE) {
			index += 4;
		}
		if(wy - fragments[0].wy >= CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE) {
			index += 2;
		}
		if(wz - fragments[0].wz >= CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE) {
			index += 1;
		}
		int relX = wx - fragments[index].wx;
		int relY = wy - fragments[index].wy;
		int relZ = wz - fragments[index].wz;
		int indexInArray = CaveBiomeMapFragment.getIndex(relX, relY, relZ);
		return fragments[index].biomeMap[indexInArray];
	}

	public static CaveBiomeMapFragment getOrGenerateFragment(World world, int wx, int wy, int wz) {
		wx &= ~CaveBiomeMapFragment.CAVE_BIOME_MAP_MASK;
		wy &= ~CaveBiomeMapFragment.CAVE_BIOME_MAP_MASK;
		wz &= ~CaveBiomeMapFragment.CAVE_BIOME_MAP_MASK;
		ChunkData compare = new ChunkData(wx, wy, wz, CaveBiomeMapFragment.CAVE_BIOME_SIZE);
		int hash = compare.hashCode() & CACHE_MASK;
		CaveBiomeMapFragment ret = cache.find(compare, hash);
		if (ret != null) return ret;
		synchronized(cache.cache[hash]) {
			// Try again in case it was already generated in another thread:
			ret = cache.find(new ChunkData(wx, wy, wz, 1), hash);
			if (ret != null) return ret;
			ret = new CaveBiomeMapFragment(wx, wy, wz, world);
			cache.addToCache(ret, hash & CACHE_MASK);
			return ret;
		}
	}
}
