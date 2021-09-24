package cubyz.world.generator;

import java.util.Arrays;
import java.util.Comparator;

import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Ore;
import cubyz.world.cubyzgenerators.*;
import cubyz.world.terrain.MapFragment;

/**
 * The normal generator for Cubyz.
 */

public class LifelandGenerator extends SurfaceGenerator {
	
	public static void init() {
		GENERATORS.registerAll(new TerrainGenerator(), new OreGenerator(), new CaveGenerator(), new CrystalCavernGenerator(), new StructureGenerator());
	}
	
	public static void initOres(Ore[] ores) {
		OreGenerator.ores = ores;
	}
	
	public static final Registry<Generator> GENERATORS = new Registry<>();
	Generator[] sortedGenerators;
	
	public void sortGenerators() {
		Generator[] unsorted = GENERATORS.registered(new Generator[0]);
		sortedGenerators = new Generator[unsorted.length];
		for (int i = 0; i < unsorted.length; i++) {
			sortedGenerators[i] = unsorted[i];
		}
		Arrays.sort(sortedGenerators, new Comparator<Generator>() {
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
	}
	
	@Override
	public void generate(Chunk chunk, ServerWorld world) {
		int wx = chunk.getWorldX();
		int wy = chunk.getWorldY();
		int wz = chunk.getWorldZ();
		long seed = world.getSeed();
		
		MapFragment containing = world.getMapFragment(wx, wz, chunk.getVoxelSize());
		
		for (Generator g : sortedGenerators) {
			g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, chunk, containing, world);
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland");
	}
}
