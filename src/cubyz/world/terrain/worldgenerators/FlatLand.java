package cubyz.world.terrain.worldgenerators;

import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.terrain.BiomePoint;
import cubyz.world.terrain.ClimateMapFragment;
import cubyz.world.terrain.ClimateMapGenerator;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;

/**
 * Generates a flat land filled with grass, dirt and stone.
 */
public class FlatLand implements ClimateMapGenerator {
	
	private Biome FLATLAND;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		FLATLAND = CubyzRegistries.BIOME_REGISTRY.getByID("cubyz:flatland");
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:flatland");
	}

	@Override
	public void generateMapFragment(ClimateMapFragment map) {
		for (int x = 0; x < map.map.length; x++) {
			for (int z = 0; z < map.map[0].length; z++) {
				map.map[x][z] = new BiomePoint(FLATLAND, map.wx + x*MapFragment.BIOME_SIZE, map.wz + z*MapFragment.BIOME_SIZE, 32, 0);
			}
		}
	}
}
