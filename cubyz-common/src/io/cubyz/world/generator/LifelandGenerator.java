package io.cubyz.world.generator;

import java.util.Arrays;
import java.util.Comparator;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Ore;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.*;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * The normal generator for Cubyz.
 */

public class LifelandGenerator extends SurfaceGenerator {
	
	public static void init() {
		GENERATORS.registerAll(new TerrainGenerator(), new RiverGenerator(), new OreGenerator(), new CaveGenerator(), new CrystalCavernGenerator(), new StructureGenerator());
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
	public void generate(NormalChunk chunk, Surface surface) {
		int cx = chunk.getX();
		int cz = chunk.getZ();
		int wx = cx << 4;
		int wz = cz << 4;
		long seed = surface.getStellarTorus().getLocalSeed();
		// Generate some maps:
		float[][] heightMap = new float[32][32];
		float[][] heatMap = new float[32][32];
		Biome[][] biomeMap = new Biome[32][32];
		surface.getMapData(wx-8, wz-8, 32, 32, heightMap, heatMap, biomeMap);
		boolean[][] vegetationIgnoreMap = new boolean[32][32]; // Stores places where vegetation should not grow, like caves and rivers.
		
		// Get the MetaChunks used by the BigGenerator.:
		int lx, lz;
		MetaChunk nn, np, pn, pp;
		if((wx & 255) < 128) {
			lx = (wx & 255) + 256;
			if((wz & 255) < 128) {
				lz = (wz & 255) + 256;
				nn = surface.getMetaChunk((wx & (~255)) - 256, (wz & (~255)) - 256);
				np = surface.getMetaChunk((wx & (~255)) - 256, (wz & (~255)));
				pn = surface.getMetaChunk((wx & (~255)), (wz & (~255)) - 256);
				pp = surface.getMetaChunk((wx & (~255)), (wz & (~255)));
			} else {
				lz = (wz & 255);
				nn = surface.getMetaChunk((wx & (~255)) - 256, (wz & (~255)));
				np = surface.getMetaChunk((wx & (~255)) - 256, (wz & (~255)) + 256);
				pn = surface.getMetaChunk((wx & (~255)), (wz & (~255)));
				pp = surface.getMetaChunk((wx & (~255)), (wz & (~255)) + 256);
			}
		} else {
			lx = (wx & 255);
			if((wz & 255) < 128) {
				lz = (wz & 255) + 256;
				nn = surface.getMetaChunk((wx & (~255)), (wz & (~255)) - 256);
				np = surface.getMetaChunk((wx & (~255)), (wz & (~255)));
				pn = surface.getMetaChunk((wx & (~255)) + 256, (wz & (~255)) - 256);
				pp = surface.getMetaChunk((wx & (~255)) + 256, (wz & (~255)));
			} else {
				lz = (wz & 255);
				nn = surface.getMetaChunk((wx & (~255)), (wz & (~255)));
				np = surface.getMetaChunk((wx & (~255)), (wz & (~255)) + 256);
				pn = surface.getMetaChunk((wx & (~255)) + 256, (wz & (~255)));
				pp = surface.getMetaChunk((wx & (~255)) + 256, (wz & (~255)) + 256);
			}
		}
		MetaChunk containing = surface.getMetaChunk((wx & (~255)), (wz & (~255)));
		
		for (Generator g : sortedGenerators) {
			if (g instanceof FancyGenerator) {
				((FancyGenerator) g).generate(seed ^ g.getGeneratorSeed(), cx, cz, chunk, vegetationIgnoreMap, heatMap, heightMap, biomeMap, surface.getSize());
			} else if (g instanceof BigGenerator) {
				((BigGenerator) g).generate(seed ^ g.getGeneratorSeed(), lx, lz, chunk, vegetationIgnoreMap, nn, np, pn, pp);
			} else {
				g.generate(seed ^ g.getGeneratorSeed(), wx, wz, chunk, containing, surface, vegetationIgnoreMap);
			}
		}

		chunk.applyBlockChanges();
	}

	@Override
	public void generate(ReducedChunk chunk, Surface surface) {
		long seed = surface.getStellarTorus().getLocalSeed();
		int wx = chunk.cx << 4;
		int wz = chunk.cz << 4;
		MetaChunk metaChunk = surface.getMetaChunk(wx & (~255), wz & (~255));
		for (Generator g : sortedGenerators) {
			if (g instanceof ReducedGenerator) {
				((ReducedGenerator) g).generate(seed ^ g.getGeneratorSeed(), wx, wz, chunk, metaChunk, surface);
			}
		}
		chunk.applyBlockChanges();
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland");
	}
}
