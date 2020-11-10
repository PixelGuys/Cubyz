package io.cubyz.world;

import java.util.ArrayList;
import java.util.Random;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * A 256×256 big chunk of height-/heat-/humidity-/… and resulting biome-maps.
 */
public class MetaChunk {
	
	public float[][] heightMap;
	public Biome[][] biomeMap;
	Surface world;
	public int wx, wz;
	
	public MetaChunk(int x, int z, long seed, Surface world, CurrentSurfaceRegistries registries) {
		this.wx = x;
		this.wz = z;
		this.world = world;
		
		heightMap = new float[256][256];
		
		biomeMap = new Biome[256][256];
		advancedHeightMapGeneration(seed, registries);
	}
	
	public void advancedHeightMapGeneration(long seed, CurrentSurfaceRegistries registries) {
		float[][] rougherMap = Noise.generateFractalTerrain(wx, wz, 256, 256, 128, seed ^ -954936678493L, world.getSizeX(), world.getSizeZ()); // Map used to add terrain roughness.
		Random rand = new Random(seed);
		long l1 = rand.nextLong();
		long l2 = rand.nextLong();
		// Start by initializing biomes on grid points TODO: Support different biome sizes:
		Biome[][] biomeMap = new Biome[257][257];
		float[][] roughnessMap = new float[257][257];
		float[][] heightMap = new float[257][257];
		for(int x = 0; x <= 256; x += 256) {
			for(int z = 0; z <= 256; z += 256) {
				rand.setSeed(l1*(this.wx + x) ^ l2*(this.wz + z) ^ seed);
				ArrayList<Biome> biomes = registries.biomeRegistry.byTypeBiomes.get(world.getBiomeMap()[wx >> 8][wz >> 8]);
				if(biomes.size() == 0) {
					System.out.println(world.getBiomeMap()[wx >> 8][wz >> 8]);
				}
				biomeMap[x][z] = biomes.get(rand.nextInt(biomes.size()));
				roughnessMap[x][z] = biomeMap[x][z].getRoughness();
				heightMap[x][z] = biomeMap[x][z].height;
			}
		}
		
		// Use a fractal algorithm to divide the biome and height maps:

		for(int res = 128; res > 0; res >>>= 1) {
			// x coordinate on the grid:
			for(int x = 0; x <= 256; x += res<<1) {
				for(int z = res; z+res <= 256; z += res<<1) {
					rand.setSeed((wx + x)*l1 ^ (wz + z)*l2 ^ seed);
					heightMap[x][z] = (heightMap[x][z-res]+heightMap[x][z+res])/2 + (rand.nextFloat()-0.5f)*res/256;
					if(rand.nextBoolean()) {
						biomeMap[x][z] = biomeMap[x][z-res];
					} else {
						biomeMap[x][z] = biomeMap[x][z+res];
					}
					if(heightMap[x][z] >= 1) heightMap[x][z] = 0.9999f;
					if(heightMap[x][z] < 0) heightMap[x][z] = 0;
				}
			}
			// y coordinate on the grid:
			for(int x = res; x+res <= 256; x += res<<1) {
				for(int z = 0; z <= 256; z += res<<1) {
					rand.setSeed((wx + x)*l1 ^ (wz + z)*l2 ^ seed);
					heightMap[x][z] = (heightMap[x-res][z]+heightMap[x+res][z])/2 + (rand.nextFloat()-0.5f)*res/256;
					if(rand.nextBoolean()) {
						biomeMap[x][z] = biomeMap[x-res][z];
					} else {
						biomeMap[x][z] = biomeMap[x+res][z];
					}
					if(heightMap[x][z] >= 1) heightMap[x][z] = 0.9999f;
					if(heightMap[x][z] < 0) heightMap[x][z] = 0;
				}
			}
			// No coordinate on the grid:
			for(int x = res; x+res <= 256; x += res<<1) {
				for(int z = res; z+res <= 256; z += res<<1) {
					rand.setSeed((wx + x)*l1 ^ (wz + z)*l2 ^ seed);
					heightMap[x][z] = (heightMap[x-res][z-res]+heightMap[x+res][z-res]+heightMap[x-res][z+res]+heightMap[x+res][z+res])/4 + (rand.nextFloat()-0.5f)*res/256;
					if(rand.nextBoolean()) {
						if(rand.nextBoolean()) {
							biomeMap[x][z] = biomeMap[x-res][z-res];
						} else {
							biomeMap[x][z] = biomeMap[x+res][z-res];
						}
					} else {
						if(rand.nextBoolean()) {
							biomeMap[x][z] = biomeMap[x-res][z+res];
						} else {
							biomeMap[x][z] = biomeMap[x+res][z+res];
						}
					}
					if(heightMap[x][z] >= 1) heightMap[x][z] = 0.9999f;
					if(heightMap[x][z] < 0) heightMap[x][z] = 0;
				}
			}
		}
		
		// Multiply world height and put it into final arrays:
		for(int x = 0; x < 256; x++) {
			for(int z = 0; z < 256; z++) {
				this.heightMap[x][z] = heightMap[x][z]*World.WORLD_HEIGHT;
				this.biomeMap[x][z] = biomeMap[x][z];
			}
		}
		
		// TODO: Add roughness.
		
		/*
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
				heightMap[ix][iy] = height*World.WORLD_HEIGHT;
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
		}*/
	}
	public float applyRoughness(Biome biome, float height, float roughness, float roughnessmap) {
		float localHeight = roughness;
		// A roughness factor of > 1 or < -1 should also be possible. In that case the terrain should "mirror" at the(averaged) height limit(minHeight, maxHeight) of the biomes:
		localHeight += height;
		localHeight -= biome.minHeight;
		localHeight = CubyzMath.floorMod(localHeight, 2*(biome.maxHeight - biome.minHeight));
		if(localHeight > (biome.maxHeight - biome.minHeight)) localHeight = 2*(biome.maxHeight - biome.minHeight) - localHeight;
		localHeight += biome.minHeight;
		return localHeight;
	}
}