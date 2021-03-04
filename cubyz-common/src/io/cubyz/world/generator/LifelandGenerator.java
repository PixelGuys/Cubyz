package io.cubyz.world.generator;

import java.util.Arrays;
import java.util.Comparator;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Ore;
import io.cubyz.world.Region;
import io.cubyz.world.Chunk;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.*;

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
		RegistryElement[] unsorted = GENERATORS.registered();
		sortedGenerators = new Generator[unsorted.length];
		for (int i = 0; i < unsorted.length; i++) {
			sortedGenerators[i] = (Generator)unsorted[i];
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
	public void generate(Chunk chunk, Surface surface) {
		int wx = chunk.getWorldX();
		int wy = chunk.getWorldY();
		int wz = chunk.getWorldZ();
		long seed = surface.getStellarTorus().getLocalSeed();
		
		Region containing = surface.getRegion((wx & (~Region.regionMask)), (wz & (~Region.regionMask)));
		
		for (Generator g : sortedGenerators) {
			g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, chunk, containing, surface);
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland");
	}
}
