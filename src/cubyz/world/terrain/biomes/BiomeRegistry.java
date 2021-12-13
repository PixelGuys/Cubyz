package cubyz.world.terrain.biomes;

import java.util.HashMap;

import cubyz.api.Registry;
import cubyz.utils.datastructures.RandomList;

/**
 * A registry that also keeps a map of biomes by type.
 */

public class BiomeRegistry extends Registry<Biome> {
	public final HashMap<Biome.Type, RandomList<Biome>> byTypeBiomes = new HashMap<Biome.Type, RandomList<Biome>>();
	public BiomeRegistry() {
		for(Biome.Type type : Biome.Type.values()) {
			byTypeBiomes.put(type, new RandomList<>());
		}
	}
	
	public BiomeRegistry(BiomeRegistry other) {
		super(other);
		for(Biome.Type type : Biome.Type.values()) {
			byTypeBiomes.put(type, new RandomList<>(other.byTypeBiomes.get(type)));
		}
	}
	
	@Override
	public boolean register(Biome biome) {
		if (super.register(biome)) {
			byTypeBiomes.get(biome.type).add(biome);
			return true;
		}
		return false;
	}
}
