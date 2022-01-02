package cubyz.world.terrain;

import cubyz.world.World;
import cubyz.world.save.MapIO;
import cubyz.world.save.WorldIO;
import cubyz.world.terrain.biomes.Biome;

/**
 * Generates and stores the height and Biome maps of the planet.
 */
public class MapFragment extends MapFragmentCompare {
	public static final int BIOME_SHIFT = 7;
	/** The average diameter of a biome. */
	public static final int BIOME_SIZE = 1 << BIOME_SHIFT;
	public static final int MAP_SHIFT = 10;
	public static final int MAP_SIZE = 1 << MAP_SHIFT;
	public static final int MAP_MASK = MAP_SIZE - 1;
	
	public final World world;
	public final float[][] heightMap;
	public final Biome[][] biomeMap;
	public final MapIO mapIO;
	
	public int minHeight = Integer.MAX_VALUE;
	public int maxHeight = 0;
	
	public MapFragment(int wx, int wz, World world, WorldIO tio, int voxelSize) {
		super(wx, wz, voxelSize);
		heightMap = new float[MAP_SIZE / voxelSize][MAP_SIZE / voxelSize];
		biomeMap = new Biome[MAP_SIZE / voxelSize][MAP_SIZE / voxelSize];
		this.world = world;
		mapIO = new MapIO(this, tio);
	}
	
	public Biome getBiome(int wx, int wz) {
		wx = (wx & MAP_MASK)/voxelSize;
		wz = (wz & MAP_MASK)/voxelSize;
		return biomeMap[wx][wz];
	}
	
	public float getHeight(int wx, int wz) {
		wx = (wx & MAP_MASK)/voxelSize;
		wz = (wz & MAP_MASK)/voxelSize;
		return heightMap[wx][wz];
	}
	
	public int getMinHeight() {
		return minHeight;
	}
	
	public int getMaxHeight() {
		return maxHeight;
	}
}
