package io.cubyz.world;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	public float[][] heightMap, heatMap, humidityMap;
	public Biome[][] biomeMap;
	Surface world;
	public int x, z;
	
	public MetaChunk(int x, int z, long seed, Surface world, CurrentSurfaceRegistries registries) {
		this.x = x;
		this.z = z;
		this.world = world;
		
		heightMap = PerlinNoise.generateThreeOctaveMapFragment(x, z, 256, 256, 2048, seed, world.getAnd());
		heatMap = PerlinNoise.generateThreeOctaveMapFragment(x, z, 256, 256, 2048, seed ^ 6587946239L, world.getAnd());
		humidityMap = PerlinNoise.generateThreeOctaveMapFragment(x, z, 256, 256, 2048, seed ^ -1324585483391L, world.getAnd());
		
		biomeMap = new Biome[256][256];
		advancedHeightMapGeneration(seed, registries);
	}
	
	public void advancedHeightMapGeneration(long seed, CurrentSurfaceRegistries registries) {
		float[][] rougherMap = Noise.generateFractalTerrain(x, z, 256, 256, 128, seed ^ -954936678493L, world.getAnd()); // Map used to add terrain roughness.
		for(int ix = 0; ix < 256; ix++) {
			for(int iy = 0; iy < 256; iy++) {
				// How many of the first biomes are used in the interpolation. This is limited to prevent long-range effects of biomes.
				final int numberOfBiomes = 4;
				float[] distance = new float[numberOfBiomes + 1];
				for(int i = 0; i <= numberOfBiomes; i++) {
					distance[i] = Float.MAX_VALUE;
				}
				// Sort the biomes by their distance in height-heat-humidity space:
				Biome[] closeBiomes = new Biome[numberOfBiomes];
				for(RegistryElement reg : registries.biomeRegistry.registered()) {
					Biome biome = (Biome)reg;
					if(closeBiomes[0] == null) closeBiomes[0] = biome;
					float dist = biome.dist(heightMap[ix][iy], heatMap[ix][iy], humidityMap[ix][iy]);
					int position = numberOfBiomes+1;
					for(int i = numberOfBiomes; i >= 0; i--) {
						if(dist < distance[i]) {
							position = i;
							if(i < numberOfBiomes - 1) {
								distance[i+1] = distance[i];
								closeBiomes[i+1] = closeBiomes[i];
							} else if(i == numberOfBiomes - 1) {
								distance[i+1] = distance[i];
							}
						}
					}
					if(position < numberOfBiomes) {
						distance[position] = dist;
						closeBiomes[position] = biome;
					} else if(position == numberOfBiomes) {
						distance[position] = dist;
					}
				}
				for(int i = 1; i < numberOfBiomes; i++) {
					if(closeBiomes[i] == null) {
						closeBiomes[i] = closeBiomes[i-1];
						distance[i] = distance[i-1];
					}
				}
				// Interpolate between the closest biomes:
				float offset = 1/distance[numberOfBiomes];
				
				float height = 0;
				float weight = 0;
				
				for(int i = 0; i < numberOfBiomes; i++) {
					Biome biome = closeBiomes[i];
					float dist = distance[i];
					float localHeight = (rougherMap[ix][iy]-0.5f)*biome.getRoughness();
					// A roughness factor of > 1 or < -1 should also be possible. In that case the terrain should "mirror" at the(averaged) height limit(minHeight, maxHeight) of the biomes:
					localHeight += biome.height;
					localHeight -= biome.minHeight;
					localHeight = CubyzMath.floorMod(localHeight, 2*(biome.maxHeight - biome.minHeight));
					if(localHeight > (biome.maxHeight - biome.minHeight)) localHeight = 2*(biome.maxHeight - biome.minHeight) - localHeight;
					localHeight += biome.minHeight;
					float localWeight = 1/dist - offset;
					height += localHeight*localWeight;
					weight += localWeight;
				}
				height = height/weight;
				heightMap[ix][iy] = height;
				for(int i = 0; i < numberOfBiomes; i++) {
					if(closeBiomes[i].minHeight <= height && closeBiomes[i].maxHeight >= height) {
						biomeMap[ix][iy] = closeBiomes[i];
						break;
					}
				}
				if(biomeMap[ix][iy] == null) {
					// A rare event that is really unlikely and if it occures mostly harmless.
					// In some rare cases it might create unexpected things(like trees under water or similar).
					// Those things are not supposed to happen, but due to their rareness they are considered a feature rather than a bug.
					biomeMap[ix][iy] = closeBiomes[0];
				}
			}
		}
	}
}