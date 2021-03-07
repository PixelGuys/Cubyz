package io.cubyz.world;

import java.util.ArrayList;
import java.util.Random;
import java.util.function.Consumer;

import io.cubyz.algorithms.DelaunayTriangulator;
import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.RegionIO;
import io.cubyz.save.TorusIO;
import io.cubyz.util.RandomList;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * A regionSize×regionSize big chunk of height-/heat-/humidity-/… and resulting biome-maps.
 */
public class Region {
	public static int regionShift = 9;
	public static int regionSize = 1 << regionShift;
	public static int regionMask = regionSize - 1;
	
	private float[][] heightMap;
	private Biome[][] biomeMap;
	private int voxelSize;
	private final Surface world;
	public final int wx, wz;
	public final RegionIO regIO;
	
	public int minHeight = Integer.MAX_VALUE;
	public int maxHeight = 0;
	
	// Data used for generating the map:
	protected ArrayList<RandomNorm> biomeList = new ArrayList<RandomNorm>(50);
	protected int[] triangles;
	
	public Region(int x, int z, long seed, Surface world, CurrentSurfaceRegistries registries, TorusIO tio, int initialVoxelSize) {
		this.wx = x;
		this.wz = z;
		this.world = world;
		
		regIO = new RegionIO(this, tio);
		prepareGeneration(seed, registries);
		advancedHeightMapGeneration(seed, registries, voxelSize = initialVoxelSize);
	}
	
	/**
	 * Generates higher resolution terrain if necessary.
	 * @param seed
	 * @param registries
	 * @param voxelSize size of the new resolution. Must be a power of 2!
	 */
	public synchronized void ensureResolution(long seed, CurrentSurfaceRegistries registries, int voxelSize) {
		if(voxelSize < this.voxelSize) {
			advancedHeightMapGeneration(seed, registries, voxelSize);
		}
	}
	
	/**
	 * A direction dependent classifier of length.
	 */
	private static final class RandomNorm {
		/**3 directions spaced at 120° angles apart.*/
		static final float[] directions = {
				0.25881904510252096f, 0.9659258262890682f,
				-0.9659258262890683f, -0.2588190451025208f,
				0.7071067811865468f, -0.7071067811865483f,
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
				norms[i] = rand.nextFloat()*0.5f + 0.5f;
			}
		}
		public float getInterpolationValue(int x, int z) {
			x -= this.x;
			z -= this.z;
			if(x == 0 & z == 0) return 1;
			float dist = (float)Math.sqrt(x*x + z*z);
			float value = 0;
			for(int i = 0; i < norms.length; i++) {
				value += norms[i]*s(Math.max(0, (x*directions[2*i] + z*directions[2*i + 1])/dist));
			}
			return value;
		}
	}
	
	private static float s(float x) {
		return (3 - 2*x)*x*x;
	}
	
	// TODO: Rougher biome borders, less edgy terrain.
	public void interpolateBiomes(int x, int z, RandomNorm n1, RandomNorm n2, RandomNorm n3, Biome r12, Biome r13, Biome r23, float[][] heightMap, Biome[][] biomeMap, float[][] roughMap, int voxelSize) {
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
		// Sort them by value:
		Biome first = n1.biome;
		Biome second = n2.biome;
		Biome replacement = r12;
		if(val2 > val1) {
			first = n2.biome;
			second = n1.biome;
			if(val3 > val2) {
				first = n3.biome;
				second = n2.biome;
				replacement = r23;
			}
		} else if(val3 > val1) {
			first = n3.biome;
			replacement = r23;
			if(val1 > val2) {
				second = n1.biome;
				replacement = r13;
			}
		} else if(val3 > val2) {
			second = n3.biome;
			replacement = r13;
		}
		int mapX = x/voxelSize;
		int mapZ = z/voxelSize;
		heightMap[mapX][mapZ] = (val1*n1.height + val2*n2.height + val3*n3.height)/(val1 + val2 + val3);
		float roughness = (val1*n1.biome.roughness + val2*n2.biome.roughness + val3*n3.biome.roughness)/(val1 + val2 + val3);
		heightMap[mapX][mapZ] += (roughMap[mapX][mapZ] - 0.5f)*roughness;
		// In case of extreme roughness the terrain should "mirror" at the interpolated height limits(minHeight, maxHeight) of the biomes:
		float minHeight = (val1*n1.biome.minHeight + val2*n2.biome.minHeight + val3*n3.biome.minHeight)/(val1 + val2 + val3);
		float maxHeight = (val1*n1.biome.maxHeight + val2*n2.biome.maxHeight + val3*n3.biome.maxHeight)/(val1 + val2 + val3);
		heightMap[mapX][mapZ] = CubyzMath.floorMod(heightMap[mapX][mapZ] - minHeight, 2*(maxHeight - minHeight));
		if(heightMap[mapX][mapZ] > maxHeight - minHeight) {
			heightMap[mapX][mapZ] = 2*(maxHeight - minHeight) - heightMap[mapX][mapZ];
		}
		heightMap[mapX][mapZ] += minHeight;
		if(first.minHeight <= heightMap[mapX][mapZ] && first.maxHeight >= heightMap[mapX][mapZ]) {
			biomeMap[mapX][mapZ] = first;
		} else if(second.minHeight <= heightMap[mapX][mapZ] && second.maxHeight >= heightMap[mapX][mapZ]) {
			biomeMap[mapX][mapZ] = second;
		} else {
			// Use a replacement biome, such as a beach:
			
			// Check if the replacement biome fits into the height region:
			if(replacement.minHeight <= heightMap[mapX][mapZ] && replacement.maxHeight >= heightMap[mapX][mapZ]) {
				biomeMap[mapX][mapZ] = replacement;
			} else {
				// Check the other possible replacement biomes instead:
				if(r12.minHeight <= heightMap[mapX][mapZ] && r12.maxHeight >= heightMap[mapX][mapZ]) {
					biomeMap[mapX][mapZ] = r12;
				} else if(r13.minHeight <= heightMap[mapX][mapZ] && r13.maxHeight >= heightMap[mapX][mapZ]) {
					biomeMap[mapX][mapZ] = r13;
				} else if(r23.minHeight <= heightMap[mapX][mapZ] && r23.maxHeight >= heightMap[mapX][mapZ]) {
					biomeMap[mapX][mapZ] = r23;
				} else {
					// If none of the replacement biomes fits, try to choose the biome that fits best:
					float b1Score = Math.max(n1.biome.minHeight - heightMap[mapX][mapZ], heightMap[mapX][mapZ] - n1.biome.maxHeight);
					float b2Score = Math.max(n2.biome.minHeight - heightMap[mapX][mapZ], heightMap[mapX][mapZ] - n2.biome.maxHeight);
					float b3Score = Math.max(n3.biome.minHeight - heightMap[mapX][mapZ], heightMap[mapX][mapZ] - n3.biome.maxHeight);
					float replacementScore = Math.max(replacement.minHeight - heightMap[mapX][mapZ], heightMap[mapX][mapZ] - replacement.maxHeight);
					Biome biome = n1.biome;
					float maxScore = b1Score;
					if(b2Score < maxScore) {
						maxScore = b2Score;
						biome = n2.biome;
					}
					if(b3Score < maxScore) {
						maxScore = b3Score;
						biome = n3.biome;
					}
					if(replacementScore < maxScore) {
						maxScore = replacementScore;
						biome = replacement;
					}
					biomeMap[mapX][mapZ] = biome;
				}
			}
		}
		this.minHeight = Math.min(this.minHeight, (int)heightMap[mapX][mapZ]);
		this.minHeight = Math.max(this.minHeight, 0);
		this.maxHeight = Math.max(this.maxHeight, (int)heightMap[mapX][mapZ]);
	}
	
	public void generateBiomesForNearbyRegion(Random rand, int x, int z, ArrayList<RandomNorm> biomeList, RandomList<Biome> availableBiomes) {
		int amount = 1 + rand.nextInt(3);
		outer:
		for(int i = 0; i < amount; i++) {
			int biomeX = x + NormalChunk.chunkSize + rand.nextInt(regionSize - 2*NormalChunk.chunkSize);// TODO: Consider more surrounding regions, so there is no need for this margin.
			int biomeZ = z + NormalChunk.chunkSize + rand.nextInt(regionSize - 2*NormalChunk.chunkSize);
			// Test if it is too close to other biomes:
			for(int j = 0; j < i; j++) {
				if(Math.max(Math.abs(biomeX - biomeList.get(biomeList.size() - i + j).x), Math.abs(biomeZ - biomeList.get(biomeList.size() - i + j).z)) <= 32) {
					i--;
					continue outer;
				}
			}
			biomeList.add(new RandomNorm(rand, biomeX, biomeZ, availableBiomes.getRandomly(rand)));
		}
	}
	
	public Biome findReplacement(float minHeight, float maxHeight, RandomList<Biome> biomes1, RandomList<Biome> biomes2, float random) {
		ArrayList<Biome> validBiomes = new ArrayList<Biome>();
		Consumer<Biome> action = (b) -> {
			if(b.minHeight <= minHeight & b.maxHeight >= maxHeight) {
				validBiomes.add(b);
			}
		};
		biomes1.forEach(action);
		biomes2.forEach(action);
		if(validBiomes.size() == 0) {
			// Anything is better than nothing, so choose a random biome from the whole list:
			int result = (int)(random*(biomes1.size() + biomes2.size()));
			if(result < biomes1.size()) {
				return biomes1.get(result);
			} else {
				return biomes2.get(result - biomes1.size());
			}
		}
		int result = (int)(random*validBiomes.size());
		return validBiomes.get(result);
	}
	
	public void drawTriangle(RandomNorm n1, RandomNorm n2, RandomNorm n3, float[][] heightMap, Biome[][] biomeMap, float[][] roughMap, CurrentSurfaceRegistries registries, int voxelSize) {
		Random triangleRandom = new Random(n1.x*5478361L ^ n1.z*5642785727L ^ n2.x*6734896731L ^ n2.z*657438643875L ^ n3.x*65783958734L ^ n3.z*673891094012L);
		// Determine connecting biomes in case there is a conflict:
		Biome r12 = n1.biome, r13 = n3.biome, r23 = n2.biome;
		if(n1.biome.minHeight > n2.biome.maxHeight) {
			r12 = findReplacement(n2.biome.maxHeight, n1.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n1.biome.type), registries.biomeRegistry.byTypeBiomes.get(n2.biome.type), triangleRandom.nextFloat());
		} else if(n1.biome.maxHeight < n2.biome.minHeight) {
			r12 = findReplacement(n1.biome.maxHeight, n2.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n1.biome.type), registries.biomeRegistry.byTypeBiomes.get(n2.biome.type), triangleRandom.nextFloat());
		}
		if(n1.biome.minHeight > n3.biome.maxHeight) {
			r13 = findReplacement(n3.biome.maxHeight, n1.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n1.biome.type), registries.biomeRegistry.byTypeBiomes.get(n3.biome.type), triangleRandom.nextFloat());
		} else if(n1.biome.maxHeight < n3.biome.minHeight) {
			r13 = findReplacement(n1.biome.maxHeight, n3.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n1.biome.type), registries.biomeRegistry.byTypeBiomes.get(n3.biome.type), triangleRandom.nextFloat());
		}
		if(n2.biome.minHeight > n3.biome.maxHeight) {
			r23 = findReplacement(n3.biome.maxHeight, n2.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n2.biome.type), registries.biomeRegistry.byTypeBiomes.get(n3.biome.type), triangleRandom.nextFloat());
		} else if(n2.biome.maxHeight < n3.biome.minHeight) {
			r23 = findReplacement(n2.biome.maxHeight, n3.biome.minHeight, registries.biomeRegistry.byTypeBiomes.get(n2.biome.type), registries.biomeRegistry.byTypeBiomes.get(n3.biome.type), triangleRandom.nextFloat());
		}
		// Sort them by z coordinate:
		RandomNorm smallest = n1.z < n2.z ? (n1.z < n3.z ? n1 : n3) : (n2.z < n3.z ? n2 : n3);
		RandomNorm second = smallest == n1 ? (n2.z < n3.z ? n2 : n3) : (smallest == n2 ? (n1.z < n3.z ? n1 : n3) : (n1.z < n2.z ? n1 : n2));
		RandomNorm third = (n1 == smallest | n1 == second) ? ((n2 == smallest | n2 == second) ? n3 : n2) : n1;
		// Calculate the slopes of the edges:
		float m1 = (float)(second.x-smallest.x)/(second.z-smallest.z);
		float m2 = (float)(third.x-smallest.x)/(third.z-smallest.z);
		float m3 = (float)(third.x-second.x)/(third.z-second.z);
		// Go through the lower-z-part of the triangle:
		int minZ = alignToGrid(Math.max(smallest.z, 0), voxelSize);
		int maxZ = Math.min(second.z, regionSize);
		for(int pz = minZ; pz < maxZ; pz += voxelSize) {
			int dz = pz-smallest.z;
			int xMin = (int)(m1*dz+smallest.x);
			int xMax = (int)(m2*dz+smallest.x);
			if(xMin > xMax) {
				int local = xMin;
				xMin = xMax;
				xMax = local;
			}
			xMin = alignToGrid(Math.max(xMin, 0), voxelSize);
			xMax = Math.min(xMax, regionMask);
			for(int px = xMin; px <= xMax; px += voxelSize) {
				interpolateBiomes(px, pz, n1, n2, n3, r12, r13, r23, heightMap, biomeMap, roughMap, voxelSize);
			}
		}
		// Go through the upper-z-part of the triangle:
		minZ = alignToGrid(Math.max(second.z, 0), voxelSize);
		maxZ = Math.min(third.z, regionSize);
		for(int pz = minZ; pz < maxZ; pz += voxelSize) {
			int dy0 = pz-smallest.z;
			int dy = pz-second.z;
			int xMin = (int)(m2*dy0+smallest.x);
			int xMax = (int)(m3*dy+second.x);
			if(xMin > xMax) {
				int local = xMin;
				xMin = xMax;
				xMax = local;
			}
			xMin = alignToGrid(Math.max(xMin, 0), voxelSize);
			xMax = Math.min(xMax, regionMask);
			for(int px = xMin; px <= xMax; px += voxelSize) {
				interpolateBiomes(px, pz, n1, n2, n3, r12, r13, r23, heightMap, biomeMap, roughMap, voxelSize);
			}
		}
	}
	
	public void prepareGeneration(long seed, CurrentSurfaceRegistries registries) {
		// Generate a rough map for terrain overlay:
		Random rand = new Random(seed);
		long l1 = rand.nextLong();
		long l2 = rand.nextLong();
		// Generate biomes for nearby regions:
		for(int x = -regionSize; x <= regionSize; x += regionSize) {
			for(int z = -regionSize; z <= regionSize; z += regionSize) {
				rand.setSeed(l1*(this.wx + x) ^ l2*(this.wz + z) ^ seed);
				RandomList<Biome> biomes = registries.biomeRegistry.byTypeBiomes.get(world.getBiomeMap()[CubyzMath.worldModulo(wx + x, world.getSizeX()) >> Region.regionShift][CubyzMath.worldModulo(wz + z, world.getSizeZ()) >> Region.regionShift]);
				generateBiomesForNearbyRegion(rand, x, z, biomeList, biomes);
			}
		}
		int[] points = new int[biomeList.size()*2];
		for(int i = 0; i < biomeList.size(); i++) {
			int index = i*2;
			points[index] = biomeList.get(i).x;
			points[index+1] = biomeList.get(i).z;
		}
		triangles = DelaunayTriangulator.computeTriangles(points, 0, points.length);
	}
	
	public void advancedHeightMapGeneration(long seed, CurrentSurfaceRegistries registries, int voxelSize) {
		
		float[][] newHeightMap = new float[regionSize/voxelSize][regionSize/voxelSize];
		
		Biome[][] newBiomeMap = new Biome[regionSize/voxelSize][regionSize/voxelSize];
		float[][] roughMap = new float[regionSize/voxelSize][regionSize/voxelSize];
		Noise.generateSparseFractalTerrain(wx/voxelSize, wz/voxelSize, regionSize/voxelSize, regionSize/voxelSize, 128/voxelSize, seed ^ -954936678493L, world.getSizeX(), world.getSizeZ(), roughMap, voxelSize); // TODO: Consider other Noise functions.
		// "Render" the triangles onto the biome map:
		for(int i = 0; i < triangles.length; i += 3) {
			drawTriangle(biomeList.get(triangles[i]), biomeList.get(triangles[i+1]), biomeList.get(triangles[i+2]), newHeightMap, newBiomeMap, roughMap, registries, voxelSize);
		}
		
		biomeMap = newBiomeMap;
		heightMap = newHeightMap;
		this.voxelSize = voxelSize;
	}
	
	public Biome getBiome(int wx, int wz) {
		wx = (wx & regionMask)/voxelSize;
		wz = (wz & regionMask)/voxelSize;
		return biomeMap[wx][wz];
	}
	
	public float getHeight(int wx, int wz) {
		wx = (wx & regionMask)/voxelSize;
		wz = (wz & regionMask)/voxelSize;
		return heightMap[wx][wz];
	}
	
	public int getMinHeight() {
		return minHeight;
	}
	
	public int getMaxHeight() {
		return maxHeight;
	}
	
	public int getVoxelSize() {
		return voxelSize;
	}
	
	private static int alignToGrid(int value, int voxelSize) {
		return (value + voxelSize - 1) & ~(voxelSize - 1);
	}
}