package cubyz.world.terrain;

import java.util.Random;

import cubyz.api.CurrentWorldRegistries;
import cubyz.world.ServerWorld;
import cubyz.world.save.MapIO;
import cubyz.world.save.WorldIO;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.noise.FractalNoise;
import cubyz.world.terrain.noise.PerlinNoise;

/**
 * Generates and stores the height and Biome maps of the planet.
 */
public class MapFragment extends MapFragmentCompare {
	
	private static class BiomePoint {
		final Biome biome;
		final float x;
		final float z;
		final float height;
		final long seed;
		public BiomePoint(Biome biome, float x, float z, float height, long seed) {
			this.biome = biome;
			this.x = x;
			this.z = z;
			this.height = height;
			this.seed = seed;
		}
		float distSquare(float x, float z) {
			return (this.x - x)*(this.x - x) + (this.z - z)*(this.z - z);
		}
		float maxNorm(float x, float z) {
			return Math.max(Math.abs(x - this.x), Math.abs(z - this.z));
		}
		Biome getFittingReplacement(float height) {
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
	public static final int BIOME_SHIFT = 7;
	/** The average diameter of a biome. */
	public static final int BIOME_SIZE = 1 << BIOME_SHIFT;
	public static final int MAP_SHIFT = 10;
	public static final int MAP_SIZE = 1 << MAP_SHIFT;
	public static final int MAP_MASK = MAP_SIZE - 1;
	
	private static ThreadLocal<PerlinNoise> threadLocalNoise = new ThreadLocal<PerlinNoise>() {
		@Override
		protected PerlinNoise initialValue() {
			return new PerlinNoise();
		}
	};
	
	public final ServerWorld world;
	public float[][] heightMap;
	public Biome[][] biomeMap;
	public final MapIO mapIO;
	
	public int minHeight = Integer.MAX_VALUE;
	public int maxHeight = 0;
	
	public MapFragment(int wx, int wz, long seed, ServerWorld world, CurrentWorldRegistries registries, WorldIO tio, int voxelSize) {
		super(wx, wz, voxelSize);
		this.world = world;
		mapIO = new MapIO(this, tio);
		generateMap(seed, registries, voxelSize);
	}
	
	public synchronized void generateMap(long seed, CurrentWorldRegistries registries, int resolution) {
		int scaledSize = MAP_SIZE/resolution;
		float[][] heightMap = new float[scaledSize][scaledSize];
		Biome[][] biomeMap = new Biome[scaledSize][scaledSize];
		// Create the biomes that will be placed on the map:
		BiomePoint[][] biomePositions = new BiomePoint[MAP_SIZE/BIOME_SIZE + 3][MAP_SIZE/BIOME_SIZE + 3];
		Biome.Type[][] typeMap = ClimateMap.getBiomeMap(seed, wx - BIOME_SIZE, wz - BIOME_SIZE, MAP_SIZE + 3*BIOME_SIZE, MAP_SIZE + 3*BIOME_SIZE);
		Random rand = new Random();
		for(int x = -BIOME_SIZE; x <= MAP_SIZE + BIOME_SIZE; x += BIOME_SIZE) {
			for(int z = -BIOME_SIZE; z <= MAP_SIZE + BIOME_SIZE; z += BIOME_SIZE) {
				rand.setSeed((x + wx)*65784967549L + (z + wz)*6758934659L + seed);
				int xIndex = x/BIOME_SIZE + 1;
				int zIndex = z/BIOME_SIZE + 1;
				Biome.Type type = typeMap[xIndex][zIndex];
				Biome biome = registries.biomeRegistry.byTypeBiomes.get(type).getRandomly(rand);
				biomePositions[xIndex][zIndex] = new BiomePoint(biome, (x + rand.nextInt(BIOME_SIZE) - BIOME_SIZE/2)/(float)resolution, (z + rand.nextInt(BIOME_SIZE) - BIOME_SIZE/2)/(float)resolution, rand.nextFloat()*(biome.maxHeight - biome.minHeight) + biome.minHeight, rand.nextLong());
			}
		}
		int scaledBiomeSize = BIOME_SIZE/resolution;
		float[][] xOffsetMap = new float[scaledSize][scaledSize];
		float[][] zOffsetMap = new float[scaledSize][scaledSize];

		FractalNoise.generateSparseFractalTerrain(wx, wz, MAP_SIZE, MAP_SIZE, BIOME_SIZE/2, seed^675396758496549L, xOffsetMap, resolution);
		FractalNoise.generateSparseFractalTerrain(wx, wz, MAP_SIZE, MAP_SIZE, BIOME_SIZE/2, seed^543864367373859L, zOffsetMap, resolution);

		// A ridgid noise map to generate interesting mountains.
		float[][] mountainMap = threadLocalNoise.get().generateRidgidNoise(wx, wz, MAP_SIZE, MAP_SIZE, 1024, 16, seed ^ 6758947592930535L, resolution, 0.5f);
		
		// A smooth map for smaller hills.
		float[][] hillMap = threadLocalNoise.get().generateSmoothNoise(wx, wz, MAP_SIZE, MAP_SIZE, 128, 32, seed ^ -157839765839495820L, resolution, 0.5f);
		
		// A fractal map to generate high-detail roughness.
		float[][] roughMap = new float[scaledSize][scaledSize];
		FractalNoise.generateSparseFractalTerrain(wx, wz, MAP_SIZE, MAP_SIZE, 64, seed ^ -954936678493L, roughMap, resolution);
		
		for(int x = 0; x < heightMap.length; x++) {
			for(int z = 0; z < heightMap.length; z++) {
				// Do the biome interpolation:
				float totalWeight = 0;
				float height = 0;
				float roughness = 0;
				float hills = 0;
				float mountains = 0;
				int xBiome = (x + scaledBiomeSize/2)/scaledBiomeSize;
				int zBiome = (z + scaledBiomeSize/2)/scaledBiomeSize;
				for(int x0 = xBiome; x0 <= xBiome+2; x0++) {
					for(int z0 = zBiome; z0 <= zBiome+2; z0++) {
						float dist = (float)Math.sqrt(biomePositions[x0][z0].distSquare(x, z));
						dist /= scaledBiomeSize;
						float maxNorm = biomePositions[x0][z0].maxNorm(x, z)/scaledBiomeSize;
						// There are cases where this point is further away than 1 unit from all nearby biomes. For that case the euclidian distance function is interpolated to the max-norm for higher distances.
						if(dist > 0.9f && maxNorm < 1) {
							float borderMax = 0.9f*maxNorm/dist;
							float scale = 1/(1 - borderMax);
							dist = dist*(1 - maxNorm)*scale + scale*(maxNorm - borderMax)*maxNorm;
						}
						if(dist <= 1) {
							float weight = (1 - dist);
							// smooth the interpolation with the s-curve:
							weight = weight*weight*(3 - 2*weight);
							height += biomePositions[x0][z0].height*weight;
							roughness += biomePositions[x0][z0].biome.roughness*weight;
							hills += biomePositions[x0][z0].biome.hills*weight;
							mountains += biomePositions[x0][z0].biome.mountains*weight;
							totalWeight += weight;
						}
					}
				}
				// Norm the result:
				height /= totalWeight;
				roughness /= totalWeight;
				hills /= totalWeight;
				mountains /= totalWeight;
				height += (roughMap[x][z] - 0.5f)*2*roughness;
				height += (hillMap[x][z] - 0.5f)*2*hills;
				height += (mountainMap[x][z] - 0.5f)*2*mountains;
				heightMap[x][z] = height;
				this.minHeight = Math.min(this.minHeight, (int)heightMap[x][z]);
				this.minHeight = Math.max(this.minHeight, 0);
				this.maxHeight = Math.max(this.maxHeight, (int)heightMap[x][z]);
				

				// Select a biome. The shape of the biome is randomized by applying noise (fractal noise and white noise) to the coordinates.
				float updatedX = x + (rand.nextInt(8) - 3.5f)*scaledBiomeSize/128 + (xOffsetMap[x][z] - 0.5f)*scaledBiomeSize/2;
				float updatedZ = z + (rand.nextInt(8) - 3.5f)*scaledBiomeSize/128 + (zOffsetMap[x][z] - 0.5f)*scaledBiomeSize/2;
				xBiome = (int)(updatedX + scaledBiomeSize/2)/scaledBiomeSize;
				zBiome = (int)(updatedZ + scaledBiomeSize/2)/scaledBiomeSize;
				float shortestDist = Float.MAX_VALUE;
				BiomePoint shortestBiome = null;
				for(int x0 = xBiome; x0 <= xBiome+2; x0++) {
					for(int z0 = zBiome; z0 <= zBiome+2; z0++) {
						float distSquare = biomePositions[x0][z0].distSquare(updatedX, updatedZ);
						if(distSquare < shortestDist) {
							shortestDist = distSquare;
							shortestBiome = biomePositions[x0][z0];
						}
					}
				}
				biomeMap[x][z] = shortestBiome.getFittingReplacement(height + rand.nextFloat()*4 - 2);
			}
		}
		synchronized(this) {
			this.biomeMap = biomeMap;
			this.heightMap = heightMap;
		}
	}
	
	public Biome getBiome(int wx, int wz) {
		wx = (wx & MAP_MASK)/voxelSize;
		wz = (wz & MAP_MASK)/voxelSize;
		return biomeMap[wx][wz];
	}
	
	public float getHeight(int wx, int wz) {
		wx = (wx & MAP_MASK)/voxelSize;
		wz = (wz & MAP_MASK)/voxelSize;
		return heightMap[wx][wz];
	}
	
	public int getMinHeight() {
		return minHeight;
	}
	
	public int getMaxHeight() {
		return maxHeight;
	}
}
