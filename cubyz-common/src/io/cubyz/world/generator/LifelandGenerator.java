package io.cubyz.world.generator;

import java.util.Arrays;
import java.util.Comparator;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Ore;
import io.cubyz.world.Region;
import io.cubyz.world.Chunk;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.*;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

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
		int cx = wx >> NormalChunk.chunkShift;
		int cy = wy >> NormalChunk.chunkShift;
		int cz = wz >> NormalChunk.chunkShift;
		long seed = surface.getStellarTorus().getLocalSeed();
		// Generate some maps:
		float[][] heightMap = new float[32][32];
		Biome[][] biomeMap = new Biome[32][32];
		surface.getMapData(wx-8, wz-8, 32, 32, heightMap, biomeMap);
		boolean[][] vegetationIgnoreMap = new boolean[32][32]; // Stores places where vegetation should not grow, like caves and rivers.
		
		Region containing = surface.getRegion((wx & (~255)), (wz & (~255)));
		
		for (Generator g : sortedGenerators) {
			if (g instanceof FancyGenerator) {
				((FancyGenerator) g).generate(seed ^ g.getGeneratorSeed(), cx, cy, cz, chunk, vegetationIgnoreMap, heightMap, biomeMap, surface);
			} else {
				g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, chunk, containing, surface, vegetationIgnoreMap);
			}
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland");
	}
}
