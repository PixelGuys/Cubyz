package io.cubyz.world.cubyzgenerators.biomes;

import java.util.HashMap;

import io.cubyz.api.Registry;
import io.cubyz.util.RandomList;

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
		if(super.register(biome)) {
			byTypeBiomes.get(biome.type).add(biome);
			return true;
		}
		return false;
	}
}
