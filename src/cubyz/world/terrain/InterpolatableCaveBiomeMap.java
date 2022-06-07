package cubyz.world.terrain;

import cubyz.multiplayer.server.Server;
import cubyz.utils.FastRandom;
import cubyz.world.ChunkData;
import cubyz.world.terrain.biomes.Biome;

/**
 * Doesn't allow getting the biome at one point and instead is only useful for interpolating values between biomes.
 */

public class InterpolatableCaveBiomeMap {

	protected final CaveBiomeMapFragment[] fragments = new CaveBiomeMapFragment[8];

	protected final MapFragment[] surfaceFragments = new MapFragment[4];

	public InterpolatableCaveBiomeMap(ChunkData chunk, int width) {
		fragments[0] = CaveBiomeMap.getOrGenerateFragment(chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[1] = CaveBiomeMap.getOrGenerateFragment(chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[2] = CaveBiomeMap.getOrGenerateFragment(chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[3] = CaveBiomeMap.getOrGenerateFragment(chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[4] = CaveBiomeMap.getOrGenerateFragment(chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[5] = CaveBiomeMap.getOrGenerateFragment(chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[6] = CaveBiomeMap.getOrGenerateFragment(chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[7] = CaveBiomeMap.getOrGenerateFragment(chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);

		surfaceFragments[0] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx - 32, chunk.wz - 32, chunk.voxelSize);
		surfaceFragments[1] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx - 32, chunk.wz + width + 32, chunk.voxelSize);
		surfaceFragments[2] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx + width + 32, chunk.wz - 32, chunk.voxelSize);
		surfaceFragments[3] = Server.world.chunkManager.getOrGenerateMapFragment(chunk.wx + width + 32, chunk.wz + width + 32, chunk.voxelSize);
	}

	public float interpolateValue(int wx, int wy, int wz) {
		// find the closest gridpoint:
		int gridPointX = wx & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		int gridPointY = wy & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		int gridPointZ = wz & ~CaveBiomeMapFragment.CAVE_BIOME_MASK;
		float interpX = 1 - (wx - gridPointX)/(float)CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		float interpY = 1 - (wy - gridPointY)/(float)CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		float interpZ = 1 - (wz - gridPointZ)/(float)CaveBiomeMapFragment.CAVE_BIOME_SIZE;
		float val = 0;
		// Doing cubic interpolation.
		// Theoretically there is a way to interpolate on my weird bcc grid, which could be done with the 4 nearest grid points, but I can't figure out how to select the correct ones.
		// TODO: Figure out the better interpolation.
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					Biome biome = _getBiome(gridPointX + dx*CaveBiomeMapFragment.CAVE_BIOME_SIZE, gridPointY + dy*CaveBiomeMapFragment.CAVE_BIOME_SIZE, gridPointZ + dz*CaveBiomeMapFragment.CAVE_BIOME_SIZE);
					val += biome.caves*Math.abs(interpX - dx)*Math.abs(interpY - dy)*Math.abs(interpZ - dz);
				}
			}
		}
		return val;
	}

	protected Biome checkSurfaceBiome(int wx, int wy, int wz) {
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

	protected final Biome _getBiome(int wx, int wy, int wz) {
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

	/**
	 * Useful when the rough biome location is enough, for example for music.
	 * @param wx
	 * @param wy
	 * @param wz
	 */
	public final Biome getRoughBiome(int wx, int wy, int wz, long[] seed, boolean checkSurfaceBiome) {
		if(checkSurfaceBiome) {
			Biome check = checkSurfaceBiome(wx, wy, wz);
			if(check != null) return check;
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
			FastRandom rand = new FastRandom(Server.world.getSeed());
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
}
