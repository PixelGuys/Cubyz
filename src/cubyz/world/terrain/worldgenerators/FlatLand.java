package cubyz.world.terrain.worldgenerators;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.world.terrain.BiomePoint;
import cubyz.world.terrain.ClimateMapFragment;
import cubyz.world.terrain.ClimateMapGenerator;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;

public class FlatLand implements ClimateMapGenerator {
	
	private static final Biome FLAT_LAND = CubyzRegistries.BIOME_REGISTRY.getByID("cubyz:flat_land");

	@Override
	public Resource getRegistryID() {
		// TODO Auto-generated method stub
		return new Resource("cubyz:flat_land");
	}

	@Override
	public void generateMapFragment(ClimateMapFragment map) {
		for (int x = 0; x < map.map.length; x++) {
			for (int z = 0; z < map.map[0].length; z++) {
				map.map[x][z] = new BiomePoint(FLAT_LAND, map.wx + x*MapFragment.BIOME_SIZE, map.wz + z*MapFragment.BIOME_SIZE, 32, 0);
			}
		}
	}
}
