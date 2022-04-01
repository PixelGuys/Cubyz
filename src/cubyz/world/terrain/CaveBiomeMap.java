package cubyz.world.terrain;

import cubyz.server.Server;
import cubyz.utils.datastructures.Cache;
import cubyz.world.Chunk;
import cubyz.world.ChunkData;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.noise.Cached3DFractalNoise;

import java.util.Random;

public class CaveBiomeMap extends InterpolatableCaveBiomeMap {
	private static final int CACHE_SIZE = 1 << 8; // Must be a power of 2!
	private static final int CACHE_MASK = CACHE_SIZE - 1;
	private static final int ASSOCIATIVITY = 8;
	private static final Cache<CaveBiomeMapFragment> cache = new Cache<>(new CaveBiomeMapFragment[CACHE_SIZE][ASSOCIATIVITY]);

	private final Chunk reference;

	private final MapFragment[] surfaceFragments = new MapFragment[4];

	private final Cached3DFractalNoise noiseX, noiseY, noiseZ;

	public CaveBiomeMap(Chunk chunk) {
		super(chunk);
		if(chunk.voxelSize >= 8) {
			noiseX = noiseY = noiseZ = null;
		} else {
			noiseX = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, Server.world.getSeed() ^ 0x764923684396L, 64);
			noiseY = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, Server.world.getSeed() ^ 0x6547835649265429L, 64);
			noiseZ = new Cached3DFractalNoise((chunk.wx - 32) & ~63, (chunk.wy - 32) & ~63, (chunk.wz - 32) & ~63, chunk.voxelSize*4, chunk.getWidth() + 128, Server.world.getSeed() ^ 0x56789365396783L, 64);
		}
		reference = chunk;
		surfaceFragments[0] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx - 32, chunk.wz - 32, chunk.voxelSize);
		surfaceFragments[1] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx - 32, chunk.wz + chunk.getWidth() + 32, chunk.voxelSize);
		surfaceFragments[2] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx + chunk.getWidth() + 32, chunk.wz - 32, chunk.voxelSize);
		surfaceFragments[3] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx + chunk.getWidth() + 32, chunk.wz + chunk.getWidth() + 32, chunk.voxelSize);
	}

	private Biome checkSurfaceBiome(int wx, int wy, int wz) {
		int index = 0;
		if(wx - surfaceFragments[0].wx >= MapFragment.MAP_SIZE) {
			index += 2;
		}
		if(wz - surfaceFragments[0].wz >= MapFragment.MAP_SIZE) {
			index += 1;
		}
		float height = surfaceFragments[index].getHeight(wx, wz);
		if(wy < height -32 || wy > height + 128) return null;
		return surfaceFragments[index].getBiome(wx, wz);
	}

	public float getSurfaceHeight(int wx, int wz) {
		int index = 0;
		if(wx - surfaceFragments[0].wx >= MapFragment.MAP_SIZE) {
			index += 2;
		}
		if(wz - surfaceFragments[0].wz >= MapFragment.MAP_SIZE) {
			index += 1;
		}
		return surfaceFragments[index].getHeight(wx, wz);
	}

	public Biome getBiome(int relX, int relY, int relZ) {
		return getBiomeAndSeed(relX, relY, relZ, null);
	}

	/**
	 * Also returns a seed that is unique for the corresponding biome position.
	 * @param relX
	 * @param relY
	 * @param relZ
	 * @param seed array where the seed gets placed. Should be 1 element long, obviously.
	 * @return
	 */
	public Biome getBiomeAndSeed(int relX, int relY, int relZ, long[] seed) {
		assert relX >= -32 && relX < reference.getWidth() + 32 : "x coordinate out of bounds: " + relX;
		assert relY >= -32 && relY < reference.getWidth() + 32 : "y coordinate out of bounds: " + relY;
		assert relZ >= -32 && relZ < reference.getWidth() + 32 : "z coordinate out of bounds: " + relZ;
		int wx = relX + reference.wx;
		int wy = relY + reference.wy;
		int wz = relZ + reference.wz;
		Biome check = checkSurfaceBiome(wx, wy, wz);
		if(check != null) return check;
		if(noiseX != null) {
			//                                                  ↓ intentionally cycled the noises to get different seeds.
			float valueX = noiseX.getValue(wx, wy, wz)*0.5f + noiseY.getRandomValue(wx, wy, wz)*8;
			float valueY = noiseY.getValue(wx, wy, wz)*0.5f + noiseZ.getRandomValue(wx, wy, wz)*8;
			float valueZ = noiseZ.getValue(wx, wy, wz)*0.5f + noiseX.getRandomValue(wx, wy, wz)*8;
			wx += valueX;
			wy += valueY;
			wz += valueZ;
		}

		int gridPointX = (wx + CaveBiomeMapFragment.CAVE_BIOME_SIZE/2) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		int gridPointY = (wy + CaveBiomeMapFragment.CAVE_BIOME_SIZE/2) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		int gridPointZ = (wz + CaveBiomeMapFragment.CAVE_BIOME_SIZE/2) & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		int distanceX = wx - gridPointX;
		int distanceY = wy - gridPointY;
		int distanceZ = wz - gridPointZ;
		int totalDistance = Math.abs(distanceX) + Math.abs(distanceY) + Math.abs(distanceZ);
		if(totalDistance > CaveBiomeMapFragment.CAVE_BIOME_SIZE*3/4) {
			// Or with 1 to prevent errors if the value is 0.
			gridPointX += Math.signum(distanceX | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			gridPointY += Math.signum(distanceY | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			gridPointZ += Math.signum(distanceZ | 1)*CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			// Go to a random gridpoint:
			Random rand = new Random(Server.world.getSeed());
			rand.setSeed(rand.nextLong() ^ gridPointX);
			rand.setSeed(rand.nextLong() ^ gridPointY);
			rand.setSeed(rand.nextLong() ^ gridPointZ);
			if(rand.nextBoolean()) {
				gridPointX += CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			}
			if(rand.nextBoolean()) {
				gridPointY += CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			}
			if(rand.nextBoolean()) {
				gridPointZ += CaveBiomeMapFragment.CAVE_BIOME_SIZE/2;
			}
		}

		if(seed != null) {
			// A good old "I don't know what I'm doing" hash:
			seed[0] = gridPointX << 48L ^ gridPointY << 23L ^ gridPointZ << 11L ^ gridPointX >> 5L ^ gridPointY << 3L ^ gridPointZ ^ Server.world.getSeed();
		}

		return _getBiome(gridPointX, gridPointY, gridPointZ);
	}

	static CaveBiomeMapFragment getOrGenerateFragment(int wx, int wy, int wz) {
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
			ret = new CaveBiomeMapFragment(wx, wy, wz, Server.world);
			cache.addToCache(ret, hash & CACHE_MASK);
			return ret;
		}
	}

	public static void cleanup() {
		cache.clear();
	}
}
