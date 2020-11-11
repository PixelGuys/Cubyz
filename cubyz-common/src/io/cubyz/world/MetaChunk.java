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
		Random rand = new Random(seed);
		long l1 = rand.nextLong();
		long l2 = rand.nextLong();
		// Start by initializing biomes on grid points TODO: Support different biome sizes:
		Biome[][] biomeMap = new Biome[257][257];
		float[][] heightMap = new float[257][257];
		for(int x = 0; x <= 256; x += 256) {
			for(int z = 0; z <= 256; z += 256) {
				rand.setSeed(l1*(this.wx + x) ^ l2*(this.wz + z) ^ seed);
				ArrayList<Biome> biomes = registries.biomeRegistry.byTypeBiomes.get(world.getBiomeMap()[CubyzMath.worldModulo(wx + x, world.getSizeX()) >> 8][CubyzMath.worldModulo(wz + z, world.getSizeZ()) >> 8]);
				if(biomes.size() == 0) {
					System.out.println(world.getBiomeMap()[wx >> 8][wz >> 8]);
				}
				biomeMap[x][z] = biomes.get(rand.nextInt(biomes.size()));
				heightMap[x][z] = biomeMap[x][z].height;
			}
		}
		
		// Use a fractal algorithm to divide the biome and height maps:

		for(int res = 128; res > 0; res >>>= 1) {
			// x coordinate on the grid:
			for(int x = 0; x <= 256; x += res<<1) {
				for(int z = res; z+res <= 256; z += res<<1) {
					rand.setSeed(CubyzMath.worldModulo(wx + x, world.getSizeX())*l1 ^ CubyzMath.worldModulo(wz + z, world.getSizeZ())*l2 ^ seed);
					if(rand.nextBoolean()) {
						biomeMap[x][z] = biomeMap[x][z-res];
					} else {
						biomeMap[x][z] = biomeMap[x][z+res];
					}
					heightMap[x][z] = (heightMap[x][z-res]+heightMap[x][z+res])/2 + (rand.nextFloat()-0.5f)*res/256*biomeMap[x][z].getRoughness();
					if(heightMap[x][z] >= biomeMap[x][z].maxHeight) heightMap[x][z] = biomeMap[x][z].maxHeight - 0.00001f;
					if(heightMap[x][z] < biomeMap[x][z].minHeight) heightMap[x][z] = biomeMap[x][z].minHeight;
				}
			}
			// y coordinate on the grid:
			for(int x = res; x+res <= 256; x += res<<1) {
				for(int z = 0; z <= 256; z += res<<1) {
					rand.setSeed(CubyzMath.worldModulo(wx + x, world.getSizeX())*l1 ^ CubyzMath.worldModulo(wz + z, world.getSizeZ())*l2 ^ seed);
					if(rand.nextBoolean()) {
						biomeMap[x][z] = biomeMap[x-res][z];
					} else {
						biomeMap[x][z] = biomeMap[x+res][z];
					}
					heightMap[x][z] = (heightMap[x-res][z]+heightMap[x+res][z])/2 + (rand.nextFloat()-0.5f)*res/256*biomeMap[x][z].getRoughness();
					if(heightMap[x][z] >= biomeMap[x][z].maxHeight) heightMap[x][z] = biomeMap[x][z].maxHeight - 0.00001f;
					if(heightMap[x][z] < biomeMap[x][z].minHeight) heightMap[x][z] = biomeMap[x][z].minHeight;
				}
			}
			// No coordinate on the grid:
			for(int x = res; x+res <= 256; x += res<<1) {
				for(int z = res; z+res <= 256; z += res<<1) {
					rand.setSeed(CubyzMath.worldModulo(wx + x, world.getSizeX())*l1 ^ CubyzMath.worldModulo(wz + z, world.getSizeZ())*l2 ^ seed);
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
					heightMap[x][z] = (heightMap[x-res][z-res]+heightMap[x+res][z-res]+heightMap[x-res][z+res]+heightMap[x+res][z+res])/4 + (rand.nextFloat()-0.5f)*res/256*biomeMap[x][z].getRoughness();
					if(heightMap[x][z] >= biomeMap[x][z].maxHeight) heightMap[x][z] = biomeMap[x][z].maxHeight - 0.00001f;
					if(heightMap[x][z] < biomeMap[x][z].minHeight) heightMap[x][z] = biomeMap[x][z].minHeight;
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
	}
}