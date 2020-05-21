package io.cubyz.world;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	public float[][] heightMap, heatMap;
	public Biome[][] biomeMap;
	Surface world;
	public int x, z;
	
	public MetaChunk(int x, int z, long seed, Surface world) {
		this.x = x;
		this.z = z;
		this.world = world;
		heightMap = PerlinNoise.generateOneOctaveMapFragment(x, z, 256, 256, 1024, seed, world.getAnd());
		heatMap = Noise.generateFractalTerrain(x, z, 256, 256, 512, seed ^ 123456789, world.getAnd()); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
		biomeMap = new Biome[256][256];
		advancedHeightMapGeneration(seed);
	}
	
	public void advancedHeightMapGeneration(long seed) {
		float[][] rougherMap = Noise.generateFractalWorleyNoise(x, z, 256, 256, 256, seed ^ -658936678493L, world.getAnd()); // Map used to add terrain roughness.
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				Biome closest = null;
				float closestDist = Float.MAX_VALUE;
				float roughness = 0;
				float weight = 0;
				float maxWeight = 0;
				for(RegistryElement reg : CubyzRegistries.BIOME_REGISTRY.registered()) {
					Biome b = (Biome)reg;
					float dist = b.dist(heightMap[i][j], heatMap[i][j]);
					roughness += b.getRoughness(heightMap[i][j])/dist;
					weight += 1/dist;
					if(1/dist > maxWeight) maxWeight = 1/dist;
					if(dist < closestDist) {
						closest = b;
						closestDist = dist;
					}
				}
				heightMap[i][j] += rougherMap[i][j]*roughness/weight;
				biomeMap[i][j] = closest;
			}
		}
	}
}