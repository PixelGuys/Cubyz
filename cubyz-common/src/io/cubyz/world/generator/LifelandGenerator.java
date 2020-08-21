package io.cubyz.world.generator;

import java.util.Arrays;
import java.util.Comparator;
import java.util.Random;

import org.joml.Vector3i;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.Ore;
import io.cubyz.world.Chunk;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.World;
import io.cubyz.world.cubyzgenerators.*;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

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
	public void generate(Chunk ch, Surface surface) {
		int cx = ch.getX();
		int cz = ch.getZ();
		int wx = cx << 4;
		int wz = cz << 4;
		long seed = surface.getStellarTorus().getLocalSeed();
		// Generate some maps:
		float[][] heightMap = new float[32][32];
		float[][] heatMap = new float[32][32];
		Biome[][] biomeMap = new Biome[32][32];
		surface.getMapData(wx-8, wz-8, 32, 32, heightMap, heatMap, biomeMap);
		boolean[][] vegetationIgnoreMap = new boolean[32][32]; // Stores places where vegetation should not grow, like caves and rivers.
		float[][] realHeight = new float[32][32];
		for(int px = 0; px < 32; px++) {
			for(int pz = 0; pz < 32; pz++) {
				float h = heightMap[px][pz]*World.WORLD_HEIGHT;
				if(h > World.WORLD_HEIGHT)
					h = World.WORLD_HEIGHT;
				realHeight[px][pz] = h;
			}
		}
		
		Random r = new Random(seed);
		Block[][][] chunk = new Block[16][16][World.WORLD_HEIGHT];
		byte[][][] chunkData = new byte[16][16][World.WORLD_HEIGHT];
		
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
		
		for (Generator g : sortedGenerators) {
			if (g instanceof FancyGenerator) {
				((FancyGenerator) g).generate(r.nextLong(), cx, cz, chunk, vegetationIgnoreMap, heatMap, realHeight, biomeMap, chunkData, surface.getSize());
			} else if (g instanceof BigGenerator) {
				((BigGenerator) g).generate(r.nextLong(), lx, lz, chunk, vegetationIgnoreMap, nn, np, pn, pp);
			} else {
				g.generate(r.nextLong(), cx, cz, chunk, vegetationIgnoreMap);
			}
		}

		// Place the blocks in the chunk:
		for(int px = 0; px < 16; px++) {
			for(int pz = 0; pz < 16; pz++) {
				for(int py = 0; py < World.WORLD_HEIGHT; py++) {
					Block b = chunk[px][pz][py];
					if(b != null) {
						ch.rawAddBlock(px, py, pz, b, chunkData[px][pz][py]);
						if (b.hasBlockEntity()) {
							Vector3i pos = new Vector3i(wx+px, py, wz+pz);
							ch.getBlockEntities().add(b.createBlockEntity(surface, pos));
						}
						if (b.getBlockClass() == BlockClass.FLUID)
							ch.getUpdatingLiquids().add((px << 4) | (py << 8) | pz);
					}
				}
			}
		}

		ch.applyBlockChanges();
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland");
	}
}
