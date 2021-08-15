package cubyz.world;

import java.util.ArrayList;
import java.util.Random;

import cubyz.api.CurrentSurfaceRegistries;
import cubyz.utils.algorithms.DelaunayTriangulator;
import cubyz.utils.datastructures.RandomList;
import cubyz.utils.math.CubyzMath;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.save.RegionIO;
import cubyz.world.save.TorusIO;

/**
 * A regionSize×regionSize big chunk of height and biome-maps.
 */
public class Region {
	public static int regionShift = 9;
	public static int regionSize = 1 << regionShift;
	public static int regionMask = regionSize - 1;
	
	private float[][] heightMap;
	private Biome[][] biomeMap;
	private int voxelSize;
	private final Surface surface;
	public final int wx, wz;
	public final RegionIO regIO;
	
	public int minHeight = Integer.MAX_VALUE;
	public int maxHeight = 0;
	
	// Data used for generating the map:
	protected ArrayList<BiomePoint> biomeList = new ArrayList<BiomePoint>(50);
	protected int[] triangles;
	
	private static ThreadLocal<PerlinNoise> threadLocalNoise = new ThreadLocal<PerlinNoise>() {
		@Override
		protected PerlinNoise initialValue() {
			return new PerlinNoise();
		}
	};
	
	public Region(int x, int z, long seed, Surface surface, CurrentSurfaceRegistries registries, TorusIO tio, int initialVoxelSize) {
		this.wx = x;
		this.wz = z;
		this.surface = surface;
		
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
	 * Stores the point of a biome placement.
	 */
	private static final class BiomePoint {
		final float height;
		final Biome biome;
		final int x, z;
		final long seed;
		public BiomePoint(Random rand, int x, int z, Biome biome) {
			this.x = x;
			this.z = z;
			this.biome = biome;
			height = (biome.maxHeight - biome.minHeight)*rand.nextFloat() + biome.minHeight;
			seed = rand.nextLong();
		}
		
		public Biome getFittingReplacement(float height) {
			// Check if the existing Biome fits and if not choose a fitting replacement:
			Biome biome = this.biome;
			if(height < biome.minHeight) {
				Random rand = new Random(seed ^ 654295489239294L);
				while(height < biome.minHeight) {
					if(biome.lowerReplacements.length == 0) break;
					biome = biome.lowerReplacements[rand.nextInt(biome.lowerReplacements.length)];
				}
			} else if(height > biome.maxHeight) {
				Random rand = new Random(seed ^ 56473865395165948L);
				while(height > biome.maxHeight) {
					if(biome.upperReplacements.length == 0) break;
					biome = biome.upperReplacements[rand.nextInt(biome.upperReplacements.length)];
				}
			}
			return biome;
		}
	}
	
	private static float s(float x) {
		return (3 - 2*x)*x*x;
	}
	
	// TODO: less edgy terrain.
	public void interpolateBiomes(Random rand, int x, int z, BiomePoint n1, BiomePoint n2, BiomePoint n3, float[][] heightMap, Biome[][] biomeMap, float[][] mountainMap, float[][] hillMap, float[][] roughMap, int voxelSize) {
		float interpolationWeight = (n2.z - n3.z)*(n1.x - n3.x) + (n3.x - n2.x)*(n1.z - n3.z);
		float w1 = ((n2.z - n3.z)*(x - n3.x) + (n3.x - n2.x)*(z - n3.z))/interpolationWeight;
		float w2 = ((n3.z - n1.z)*(x - n3.x) + (n1.x - n3.x)*(z - n3.z))/interpolationWeight;
		float w3 = 1 - w1 - w2;
		// s-curve the whole thing for extra smoothness:
		w1 = s(w1);
		w2 = s(w2);
		w3 = s(w3);
		// Randomize the values slightly to get a less linear look:
		float biomeWeight1 = w1*(3 + rand.nextFloat());
		float biomeWeight2 = w2*(3 + rand.nextFloat());
		float biomeWeight3 = w3*(3 + rand.nextFloat());
		// Norm them:
		float sum = w1 + w2 + w3;
		w1 /= sum;
		w2 /= sum;
		w3 /= sum;
		sum = biomeWeight1 + biomeWeight2 + biomeWeight3;
		biomeWeight1 /= sum;
		biomeWeight2 /= sum;
		biomeWeight3 /= sum;
		int mapX = x/voxelSize;
		int mapZ = z/voxelSize;
		heightMap[mapX][mapZ] = w1*n1.height + w2*n2.height + w3*n3.height;
		
		// Add roughness:
		float roughness = w1*n1.biome.roughness + w2*n2.biome.roughness + w3*n3.biome.roughness;
		heightMap[mapX][mapZ] += (roughMap[mapX][mapZ] - 0.5f)*roughness;
		// In case of extreme roughness the terrain should "mirror" at the interpolated height limits(minHeight, maxHeight) of the biomes:
		float minHeight = w1*n1.biome.minHeight + w2*n2.biome.minHeight + w3*n3.biome.minHeight;
		float maxHeight = w1*n1.biome.maxHeight + w2*n2.biome.maxHeight + w3*n3.biome.maxHeight;
		heightMap[mapX][mapZ] = CubyzMath.floorMod(heightMap[mapX][mapZ] - minHeight, 2*(maxHeight - minHeight));
		if(heightMap[mapX][mapZ] > maxHeight - minHeight) {
			heightMap[mapX][mapZ] = 2*(maxHeight - minHeight) - heightMap[mapX][mapZ];
		}
		heightMap[mapX][mapZ] += minHeight;
		
		// Add mountains:
		float mountains = w1*n1.biome.mountains + w2*n2.biome.mountains + w3*n3.biome.mountains;
		heightMap[mapX][mapZ] += (mountainMap[mapX][mapZ] - 0.5f)*2*mountains;
		
		// In case of low height the terrain should "mirror" at the interpolated lower height limit of the biomes:
		if(heightMap[mapX][mapZ] < minHeight) heightMap[mapX][mapZ] = 2*minHeight - heightMap[mapX][mapZ];
		
		// Add hills:
		float hills = w1*n1.biome.hills + w2*n2.biome.hills + w3*n3.biome.hills;
		heightMap[mapX][mapZ] += (hillMap[mapX][mapZ] - 0.5f)*2*hills;

		// Get the closest biome:
		BiomePoint first = n1;
		if(biomeWeight2 > biomeWeight1) {
			first = n2;
			if(biomeWeight3 > biomeWeight2) {
				first = n3;
			}
		} else if(biomeWeight3 > biomeWeight1) {
			first = n3;
		}
		// Get a replacement biome that fits the height. Make the terrain rough by using a slightly randomized heightmap:
		biomeMap[mapX][mapZ] = first.getFittingReplacement(heightMap[mapX][mapZ] + rand.nextFloat()*4 - 2);
		
		this.minHeight = Math.min(this.minHeight, (int)heightMap[mapX][mapZ]);
		this.minHeight = Math.max(this.minHeight, 0);
		this.maxHeight = Math.max(this.maxHeight, (int)heightMap[mapX][mapZ]);
	}
	
	public void generateBiomesForNearbyRegion(Random rand, int x, int z, ArrayList<BiomePoint> biomeList, RandomList<Biome> availableBiomes) {
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
			biomeList.add(new BiomePoint(rand, biomeX, biomeZ, availableBiomes.getRandomly(rand)));
		}
	}
	
	public void drawTriangle(BiomePoint n1, BiomePoint n2, BiomePoint n3, float[][] heightMap, Biome[][] biomeMap, float[][] mountainMap, float[][] hillMap, float[][] roughMap, CurrentSurfaceRegistries registries, int voxelSize) {
		Random rand = new Random(n1.x*5478361L ^ n1.z*5642785727L ^ n2.x*6734896731L ^ n2.z*657438643875L ^ n3.x*65783958734L ^ n3.z*673891094012L);
		// Sort them by z coordinate:
		BiomePoint smallest = n1.z < n2.z ? (n1.z < n3.z ? n1 : n3) : (n2.z < n3.z ? n2 : n3);
		BiomePoint second = smallest == n1 ? (n2.z < n3.z ? n2 : n3) : (smallest == n2 ? (n1.z < n3.z ? n1 : n3) : (n1.z < n2.z ? n1 : n2));
		BiomePoint third = (n1 == smallest | n1 == second) ? ((n2 == smallest | n2 == second) ? n3 : n2) : n1;
		// Calculate the slopes of the edges:
		float m1 = (float)(second.x-smallest.x)/(second.z-smallest.z);
		float m2 = (float)(third.x-smallest.x)/(third.z-smallest.z);
		float m3 = (float)(third.x-second.x)/(third.z-second.z);
		// Go through the lower-z-part of the triangle:
		int minZ = alignToGrid(Math.max(smallest.z, 0), voxelSize);
		int maxZ = Math.min(second.z, regionSize);
		
		long rand1 = rand.nextLong() | 1;
		long rand2 = rand.nextLong() | 1;
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
				rand.setSeed(px*rand1 ^ pz*rand2);
				interpolateBiomes(rand, px, pz, n1, n2, n3, heightMap, biomeMap, mountainMap, hillMap, roughMap, voxelSize);
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
				rand.setSeed(px*rand1 ^ pz*rand2);
				interpolateBiomes(rand, px, pz, n1, n2, n3, heightMap, biomeMap, mountainMap, hillMap, roughMap, voxelSize);
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
				rand.setSeed(l1*CubyzMath.worldModulo(this.wx + x, surface.getSizeX()) ^ l2*CubyzMath.worldModulo(this.wz + z, surface.getSizeZ()) ^ seed);
				RandomList<Biome> biomes = registries.biomeRegistry.byTypeBiomes.get(surface.getBiomeMap()[CubyzMath.worldModulo(wx + x, surface.getSizeX()) >> Region.regionShift][CubyzMath.worldModulo(wz + z, surface.getSizeZ()) >> Region.regionShift]);
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
		
		// A ridgid noise map to generate interesting mountains.
		float[][] mountainMap = threadLocalNoise.get().generateRidgidNoise(wx, wz, regionSize, regionSize, 1024, 16, seed ^ -954936678493L, surface.getSizeX(), surface.getSizeZ(), voxelSize, 0.5f);
		
		// A smooth map for smaller hills.
		float[][] hillMap = threadLocalNoise.get().generateRidgidNoise(wx, wz, regionSize, regionSize, 128, 32, seed ^ -954936678493L, surface.getSizeX(), surface.getSizeZ(), voxelSize, 0.5f);
		
		// A fractal map to generate high-detail roughness.
		float[][] roughMap = new float[regionSize/voxelSize][regionSize/voxelSize];
		Noise.generateSparseFractalTerrain(wx/voxelSize, wz/voxelSize, regionSize/voxelSize, regionSize/voxelSize, 64/voxelSize, seed ^ -954936678493L, surface.getSizeX(), surface.getSizeZ(), roughMap, voxelSize);
		
		// "Render" the triangles onto the biome map:
		for(int i = 0; i < triangles.length; i += 3) {
			drawTriangle(biomeList.get(triangles[i]), biomeList.get(triangles[i+1]), biomeList.get(triangles[i+2]), newHeightMap, newBiomeMap, mountainMap, hillMap, roughMap, registries, voxelSize);
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