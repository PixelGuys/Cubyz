package cubyz.world.terrain;

import java.util.Arrays;
import java.util.Comparator;

import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.world.terrain.cavebiomegenerators.CaveBiomeGenerator;
import cubyz.world.terrain.cavegenerators.CaveGenerator;
import cubyz.world.terrain.generators.Generator;
import pixelguys.json.JsonObject;

/**
 * Lists all the Generators and Biomes that should be used for a given world.
 * TODO: Generator/Biome blackslisting (from the world creation menu).
 * TODO: Generator settings (from the world creation menu).
 */
public class TerrainGenerationProfile {
	public final MapGenerator mapFragmentGenerator;
	public final ClimateMapGenerator climateGenerator;
	public final CaveBiomeGenerator[] caveBiomeGenerators;
	public final CaveGenerator[] caveGenerators;
	public final Generator[] generators;
	public final long seed;
	
	public TerrainGenerationProfile(JsonObject settings, CurrentWorldRegistries registries, long seed) {
		this.seed = seed;
		JsonObject generator = settings.getObjectOrNew("mapGenerator");
		mapFragmentGenerator = CubyzRegistries.MAP_GENERATOR_REGISTRY.getByID(generator.getString("id", "cubyz:mapgen_v1"));
		mapFragmentGenerator.init(generator, registries);
		generator = settings.getObjectOrNew("climateGenerator");
		climateGenerator = CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.getByID(generator.getString("id", "cubyz:polar_circles"));
		climateGenerator.init(generator, registries);

		generators = CubyzRegistries.GENERATORS.registered(new Generator[0]);
		for(int i = 0; i < generators.length; i++) {
			generators[i].init(null, registries);
		}
		Arrays.sort(generators, new Comparator<Generator>() {
			@Override
			public int compare(Generator a, Generator b) {
				if (a.getPriority() > b.getPriority()) {
					return 1;
				} else if (a.getPriority() < b.getPriority()) {
					return -1;
				} else {
					return 0;
				}
			}
		});

		caveGenerators = CubyzRegistries.CAVE_GENERATORS.registered(new CaveGenerator[0]);
		for(int i = 0; i < caveGenerators.length; i++) {
			caveGenerators[i].init(null, registries);
		}
		Arrays.sort(caveGenerators, new Comparator<CaveGenerator>() {
			@Override
			public int compare(CaveGenerator a, CaveGenerator b) {
				if (a.getPriority() > b.getPriority()) {
					return 1;
				} else if (a.getPriority() < b.getPriority()) {
					return -1;
				} else {
					return 0;
				}
			}
		});

		caveBiomeGenerators = CubyzRegistries.CAVE_BIOME_GENERATORS.registered(new CaveBiomeGenerator[0]);
		for(int i = 0; i < caveBiomeGenerators.length; i++) {
			caveBiomeGenerators[i].init(null, registries);
		}
		Arrays.sort(caveBiomeGenerators, new Comparator<CaveBiomeGenerator>() {
			@Override
			public int compare(CaveBiomeGenerator a, CaveBiomeGenerator b) {
				if (a.getPriority() > b.getPriority()) {
					return 1;
				} else if (a.getPriority() < b.getPriority()) {
					return -1;
				} else {
					return 0;
				}
			}
		});
	}
}
