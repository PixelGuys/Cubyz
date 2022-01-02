package cubyz.world.terrain;

import cubyz.world.World;

public class ClimateMapFragment {
	public static final int MAP_SHIFT = 8 + MapFragment.BIOME_SHIFT;
	public static final int MAP_SIZE = 1 << MAP_SHIFT;
	public static final int MAP_MASK = MAP_SIZE - 1;
	public final int wx, wz;
	public final World world;
	public final BiomePoint[][] map;
	
	public ClimateMapFragment(World world, int wx, int wz) {
		this.wx = wx;
		this.wz = wz;
		this.world = world;
		map = new BiomePoint[MAP_SIZE/MapFragment.BIOME_SIZE][MAP_SIZE/MapFragment.BIOME_SIZE];
	}
	
	@Override
	public int hashCode() {
		return hashCode(wx, wz);
	}
	
	public static int hashCode(int wx, int wz) {
		return (wx >> MAP_SHIFT)*31 + (wz >> MAP_SHIFT);
	}
}
