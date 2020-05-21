package io.cubyz.world;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	public float[][] heightMap, heatMap, humidityMap;
	public Biome[][] biomeMap;
	Surface world;
	public int x, z;
	
	public MetaChunk(int x, int z, long seed, Surface world) {
		this.x = x;
		this.z = z;
		this.world = world;
		heightMap = PerlinNoise.generateTwoOctaveMapFragment(x, z, 256, 256, 1024, seed, world.getAnd());
		humidityMap = PerlinNoise.generateTwoOctaveMapFragment(x, z, 256, 256, 1024, seed ^ 6587946239L, world.getAnd());
		heatMap = Noise.generateFractalTerrain(x, z, 256, 256, 512, seed ^ 123456789, world.getAnd()); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
		biomeMap = new Biome[256][256];
		heatMap = PerlinNoise.generateTwoOctaveMapFragment(x, z, 256, 256, 1024, seed ^ 6587946239L, world.getAnd());
		advancedHeightMapGeneration(seed);
	}
	
	public void advancedHeightMapGeneration(long seed) {
		float[][] rougherMap = Noise.generateFractalTerrain(x, z, 256, 256, 128, seed ^ -658936678493L, world.getAnd()); // Map used to add terrain roughness.
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				Biome closest = null;
				float closestDist = Float.MAX_VALUE;
				float height = 0;
				float weight = 0;
				for(RegistryElement reg : CubyzRegistries.BIOME_REGISTRY.registered()) {
					Biome biome = (Biome)reg;
					float dist = biome.dist(heightMap[i][j], heatMap[i][j], humidityMap[i][j]);
					float localHeight = 2*(rougherMap[i][j]-0.5f)*biome.getRoughness(heightMap[i][j]);
					// A roughness factor of > 1 or < -1 should also be possible. In that case the terrain should "mirror" at the(averaged) height limit(minHeight, maxHeight) of the biomes:
					localHeight += heightMap[i][j];
					localHeight -= biome.minHeight;
					localHeight = CubyzMath.floorMod(localHeight, 2*(biome.maxHeight - biome.minHeight));
					if(localHeight > (biome.maxHeight - biome.minHeight)) localHeight = 2*(biome.maxHeight - biome.minHeight) - localHeight;
					localHeight += biome.minHeight;
					
					height += localHeight/dist;
					weight += 1/dist;
					if(dist < closestDist) {
						closest = biome;
						closestDist = dist;
					}
				}
				height = height/weight;
				heightMap[i][j] = height;
				biomeMap[i][j] = closest;
			}
		}
	}
}