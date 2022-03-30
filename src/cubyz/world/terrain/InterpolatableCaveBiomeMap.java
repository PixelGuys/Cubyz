package cubyz.world.terrain;

import cubyz.world.ChunkData;
import cubyz.world.terrain.biomes.Biome;

/**
 * Doesn't allow getting the biome at one point and instead is only useful for interpolating values between biomes.
 */

public class InterpolatableCaveBiomeMap {

	protected final CaveBiomeMapFragment[] fragments = new CaveBiomeMapFragment[8];

	public InterpolatableCaveBiomeMap(ChunkData chunk) {
		fragments[0] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[1] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[2] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[3] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[4] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[5] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[6] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz - CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
		fragments[7] = CaveBiomeMap.getOrGenerateFragment(CaveBiomeMap.world, chunk.wx + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wy + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2, chunk.wz + CaveBiomeMapFragment.CAVE_BIOME_MAP_SIZE/2);
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
}
