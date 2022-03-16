package cubyz.world.terrain;

import cubyz.utils.datastructures.RandomList;
import cubyz.world.ChunkData;
import cubyz.world.World;
import cubyz.world.terrain.biomes.Biome;

import java.util.Random;

/**
 * Cave biome data from a slice of the world.
 */
public class CaveBiomeMapFragment extends ChunkData {

	public static final int CAVE_BIOME_SHIFT = 7;
	public static final int CAVE_BIOME_SIZE = 1 << CAVE_BIOME_SHIFT;
	public static final int CAVE_BIOME_MASK = CAVE_BIOME_SIZE - 1;
	public static final int CAVE_BIOME_MAP_SHIFT = 11;
	public static final int CAVE_BIOME_MAP_SIZE = 1 << CAVE_BIOME_MAP_SHIFT;
	public static final int CAVE_BIOME_MAP_MASK = CAVE_BIOME_MAP_SIZE - 1;

	public final Biome[] biomeMap = new Biome[1 << 3*(CAVE_BIOME_MAP_SHIFT - CAVE_BIOME_SHIFT)];

	public CaveBiomeMapFragment(int wx, int wy, int wz, World world) {
		super(wx, wy, wz, CAVE_BIOME_SIZE);
		assert (wx & CAVE_BIOME_MAP_SIZE-1) == 0 && (wy & CAVE_BIOME_MAP_SIZE-1) == 0 && (wz & CAVE_BIOME_MAP_SIZE-1) == 0;
		Random rand = new Random(world.getSeed());
		long rand1 = rand.nextLong() | 1;
		long rand2 = rand.nextLong() | 1;
		long rand3 = rand.nextLong() | 1;
		rand.setSeed(wx*rand1 ^ wy*rand2 ^ wz*rand3);
		RandomList<Biome> biomes = world.registries.biomeRegistry.byTypeBiomes.get(Biome.Type.CAVE);
		for(int i = 0; i < biomeMap.length; i++) {
			biomeMap[i] = biomes.getRandomly(rand);
		}
	}

	public static int getIndex(int relX, int relY, int relZ) {
		assert(relX >= 0 && relX < CAVE_BIOME_MAP_SIZE) : "x coordinate out of bounds: " + relX;
		assert(relY >= 0 && relY < CAVE_BIOME_MAP_SIZE) : "y coordinate out of bounds: " + relY;
		assert(relZ >= 0 && relZ < CAVE_BIOME_MAP_SIZE) : "z coordinate out of bounds: " + relZ;
		relX >>= CAVE_BIOME_SHIFT;
		relY >>= CAVE_BIOME_SHIFT;
		relZ >>= CAVE_BIOME_SHIFT;
		return relX << 2*(CAVE_BIOME_MAP_SHIFT - CAVE_BIOME_SHIFT) | relY << (CAVE_BIOME_MAP_SHIFT - CAVE_BIOME_SHIFT) | relZ;
	}
}
