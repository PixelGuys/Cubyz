package io.cubyz.world;

import java.util.Random;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.RegionIO;
import io.cubyz.save.TorusIO;
import io.cubyz.util.RandomList;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * A 256×256 big chunk of height-/heat-/humidity-/… and resulting biome-maps.
 */
public class Region {
	
	public final float[][] heightMap;
	public final Biome[][] biomeMap;
	private final Surface world;
	public final int wx, wz;
	public final RegionIO regIO;
	
	public Region(int x, int z, long seed, Surface world, CurrentSurfaceRegistries registries, TorusIO tio) {
		this.wx = x;
		this.wz = z;
		this.world = world;
		
		regIO = new RegionIO(this, tio);
		
		heightMap = new float[256][256];
		
		biomeMap = new Biome[256][256];
		advancedHeightMapGeneration(seed, registries);
	}
	
	private final Biome getRandomBiome(Random rand, int x, int z, long l1, long l2, long seed, CurrentSurfaceRegistries registries) {
		rand.setSeed(l1*(this.wx + x) ^ l2*(this.wz + z) ^ seed);
		RandomList<Biome> biomes = registries.biomeRegistry.byTypeBiomes.get(world.getBiomeMap()[CubyzMath.worldModulo(wx + x, world.getSizeX()) >> 8][CubyzMath.worldModulo(wz + z, world.getSizeZ()) >> 8]);
		return biomes.getRandomly(rand);
	}
	
	/**
	 * A direction dependent classifier of length.
	 */
	private static final class RandomNorm {
		/**6 directions spaced at 60° angles apart.*/
		static final float[] directions = {
				0.25881904510252096f, 0.9659258262890682f,
				//-0.7071067811865475f, 0.7071067811865476f,
				-0.9659258262890683f, -0.2588190451025208f,
				//-0.2588190451025215f, -0.9659258262890681f,
				0.7071067811865468f, -0.7071067811865483f,
				//0.9659258262890684f, 0.25881904510252024f,
				/*0.25881904510252096f, -0.9659258262890682f,
				-0.7071067811865475f, -0.7071067811865476f,
				-0.9659258262890683f, 0.2588190451025208f,
				-0.2588190451025215f, 0.9659258262890681f,
				0.7071067811865468f, 0.7071067811865483f,
				0.9659258262890684f, -0.25881904510252024f,*/
		};
		final float[] norms = new float[3];
		final float height;
		final Biome biome;
		final int x, z;
		public RandomNorm(Random rand, int x, int z, Biome biome) {
			this.x = x;
			this.z = z;
			this.biome = biome;
			height = (biome.maxHeight - biome.minHeight)*rand.nextFloat() + biome.minHeight;
			for(int i = 0; i < norms.length; i++) {
				norms[i] = rand.nextFloat();
			}
		}
		public float getInterpolationValue(int x, int z) {
			x -= this.x;
			z -= this.z;
			if(x == 0 & z == 0) return 1;
			float distSquare = (x*x + z*z);
			float dist = (float)Math.sqrt(distSquare);
			float value = 0;
			for(int i = 0; i < norms.length; i++) {
				value += norms[i]*Math.max(0, s((x*directions[2*i] + z*directions[2*i + 1])/dist));
			}
			return value;
		}
	}
	
	private static float s(float x) {
		return (3 - 2*x)*x*x;
	}
	
	public void interpolateBiomes(int x, int z, RandomNorm n1, RandomNorm n2, RandomNorm n3) {
		float interpolationWeight = (n2.z - n3.z)*(n1.x - n3.x) + (n3.x - n2.x)*(n1.z - n3.z);
		float w1 = ((n2.z - n3.z)*(x - n3.x) + (n3.x - n2.x)*(z - n3.z))/interpolationWeight;
		float w2 = ((n3.z - n1.z)*(x - n3.x) + (n1.x - n3.x)*(z - n3.z))/interpolationWeight;
		float w3 = 1 - w1 - w2;
		// s-curve the whole thing for extra smoothness:
		w1 = s(w1);
		w2 = s(w2);
		w3 = s(w3);
		float val1 = n1.getInterpolationValue(x, z)*w1;
		float val2 = n2.getInterpolationValue(x, z)*w2;
		float val3 = n3.getInterpolationValue(x, z)*w3;
		Biome b = n1.biome;
		if(val2 > val1) {
			b = n2.biome;
			if(val3 > val2) {
				b = n3.biome;
			}
		} else if(val3 > val1) {
			b = n3.biome;
		}
		biomeMap[x][z] = b;
		heightMap[x][z] = (val1*n1.height + val2*n2.height + val3*n3.height)/(val1 + val2 + val3)*World.WORLD_HEIGHT;
	}
	
	public void advancedHeightMapGeneration(long seed, CurrentSurfaceRegistries registries) {
		Random rand = new Random(seed);
		long l1 = rand.nextLong();
		long l2 = rand.nextLong();
		// Init the closest grid point aligned biomes.
		// Every second line is shifted by half a region in y-direction.
		if((wz & 256) == 256) {
			Biome biome = getRandomBiome(rand, 0, 0, l1, l2, seed, registries);
			RandomNorm bLNorm = new RandomNorm(rand, 0, 0, biome);
			biome = getRandomBiome(rand, 256, 0, l1, l2, seed, registries);
			RandomNorm bRNorm = new RandomNorm(rand, 256, 0, biome);
			biome = getRandomBiome(rand, -128, 256, l1, l2, seed, registries);
			RandomNorm tLNorm = new RandomNorm(rand, -128, 256, biome);
			biome = getRandomBiome(rand, 128, 256, l1, l2, seed, registries);
			RandomNorm tMNorm = new RandomNorm(rand, 128, 256, biome);
			biome = getRandomBiome(rand, 384, 256, l1, l2, seed, registries);
			RandomNorm tRNorm = new RandomNorm(rand, 384, 256, biome);
			
			// top left region:
			for(int z = 0; z < 256; z++) {
				int maxX = z/2;
				for(int x = 0; x < maxX; x++) {
					interpolateBiomes(x, z, bLNorm, tLNorm, tMNorm);
				}
			}
			// bottom mid region:
			for(int z = 0; z < 256; z++) {
				int minX = z/2;
				int maxX = 256 - z/2;
				for(int x = minX; x < maxX; x++) {
					interpolateBiomes(x, z, bLNorm, tMNorm, bRNorm);
				}
			}
			// top right region:
			for(int z = 0; z < 256; z++) {
				int minX = 256 - z/2;
				for(int x = minX; x < 256; x++) {
					interpolateBiomes(x, z, tMNorm, tRNorm, bRNorm);
				}
			}
		} else {
			Biome biome = getRandomBiome(rand, 0, 256, l1, l2, seed, registries);
			RandomNorm tLNorm = new RandomNorm(rand, 0, 256, biome);
			biome = getRandomBiome(rand, 256, 256, l1, l2, seed, registries);
			RandomNorm tRNorm = new RandomNorm(rand, 256, 256, biome);
			biome = getRandomBiome(rand, -128, 0, l1, l2, seed, registries);
			RandomNorm bLNorm = new RandomNorm(rand, -128, 0, biome);
			biome = getRandomBiome(rand, 128, 0, l1, l2, seed, registries);
			RandomNorm bMNorm = new RandomNorm(rand, 128, 0, biome);
			biome = getRandomBiome(rand, 384, 0, l1, l2, seed, registries);
			RandomNorm bRNorm = new RandomNorm(rand, 384, 0, biome);
			
			// top left region:
			for(int z = 0; z < 256; z++) {
				int maxX = 128 - z/2;
				for(int x = 0; x < maxX; x++) {
					interpolateBiomes(x, z, bLNorm, tLNorm, bMNorm);
				}
			}
			// top mid region:
			for(int z = 0; z < 256; z++) {
				int minX = 128 - z/2;
				int maxX = 128 + z/2;
				for(int x = minX; x < maxX; x++) {
					interpolateBiomes(x, z, tLNorm, bMNorm, tRNorm);
				}
			}
			// top right region:
			for(int z = 0; z < 256; z++) {
				int minX = 128 + z/2;
				for(int x = minX; x < 256; x++) {
					interpolateBiomes(x, z, bMNorm, tRNorm, bRNorm);
				}
			}
		}
	}
}