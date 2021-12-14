package cubyz.world.terrain.worldgenerators;

import java.util.Random;

import cubyz.api.Resource;
import cubyz.world.terrain.BiomePoint;
import cubyz.world.terrain.ClimateMap;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.MapGenerator;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.noise.FractalNoise;
import cubyz.world.terrain.noise.PerlinNoise;

import static cubyz.world.terrain.MapFragment.*;

public class NoisyVoronoi implements MapGenerator {

	@Override
	public Resource getRegistryID() {
		// TODO Auto-generated method stub
		return new Resource("cubyz:noisy_voronoi");
	}
	
	private static ThreadLocal<PerlinNoise> threadLocalNoise = new ThreadLocal<PerlinNoise>() {
		@Override
		protected PerlinNoise initialValue() {
			return new PerlinNoise();
		}
	};

	@Override
	public void generateMapFragment(MapFragment map) {
		int scaledSize = MapFragment.MAP_SIZE/map.voxelSize;
		// Create the biomes that will be placed on the map:
		BiomePoint[][] biomePositions = new BiomePoint[MAP_SIZE/BIOME_SIZE + 3][MAP_SIZE/BIOME_SIZE + 3];
		long seed = map.world.getSeed();
		Biome.Type[][] typeMap = ClimateMap.getBiomeMap(map.world, map.wx - BIOME_SIZE, map.wz - BIOME_SIZE, MAP_SIZE + 3*BIOME_SIZE, MAP_SIZE + 3*BIOME_SIZE);
		Random rand = new Random();
		for(int x = -BIOME_SIZE; x <= MAP_SIZE + BIOME_SIZE; x += BIOME_SIZE) {
			for(int z = -BIOME_SIZE; z <= MAP_SIZE + BIOME_SIZE; z += BIOME_SIZE) {
				rand.setSeed((x + map.wx)*65784967549L + (z + map.wz)*6758934659L + seed);
				int xIndex = x/BIOME_SIZE + 1;
				int zIndex = z/BIOME_SIZE + 1;
				Biome.Type type = typeMap[xIndex][zIndex];
				Biome biome = map.world.getCurrentRegistries().biomeRegistry.byTypeBiomes.get(type).getRandomly(rand);
				biomePositions[xIndex][zIndex] = new BiomePoint(biome, (x + rand.nextInt(BIOME_SIZE) - BIOME_SIZE/2)/(float)map.voxelSize, (z + rand.nextInt(BIOME_SIZE) - BIOME_SIZE/2)/(float)map.voxelSize, rand.nextFloat()*(biome.maxHeight - biome.minHeight) + biome.minHeight, rand.nextLong());
			}
		}
		int scaledBiomeSize = BIOME_SIZE/map.voxelSize;
		float[][] xOffsetMap = new float[scaledSize][scaledSize];
		float[][] zOffsetMap = new float[scaledSize][scaledSize];

		FractalNoise.generateSparseFractalTerrain(map.wx, map.wz, MAP_SIZE, MAP_SIZE, BIOME_SIZE/2, seed^675396758496549L, xOffsetMap, map.voxelSize);
		FractalNoise.generateSparseFractalTerrain(map.wx, map.wz, MAP_SIZE, MAP_SIZE, BIOME_SIZE/2, seed^543864367373859L, zOffsetMap, map.voxelSize);

		// A ridgid noise map to generate interesting mountains.
		float[][] mountainMap = threadLocalNoise.get().generateRidgidNoise(map.wx, map.wz, MAP_SIZE, MAP_SIZE, 1024, 16, seed ^ 6758947592930535L, map.voxelSize, 0.5f);
		
		// A smooth map for smaller hills.
		float[][] hillMap = threadLocalNoise.get().generateSmoothNoise(map.wx, map.wz, MAP_SIZE, MAP_SIZE, 128, 32, seed ^ -157839765839495820L, map.voxelSize, 0.5f);
		
		// A fractal map to generate high-detail roughness.
		float[][] roughMap = new float[scaledSize][scaledSize];
		FractalNoise.generateSparseFractalTerrain(map.wx, map.wz, MAP_SIZE, MAP_SIZE, 64, seed ^ -954936678493L, roughMap, map.voxelSize);
		
		for(int x = 0; x < map.heightMap.length; x++) {
			for(int z = 0; z < map.heightMap.length; z++) {
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
						if (dist > 0.9f && maxNorm < 1) {
							float borderMax = 0.9f*maxNorm/dist;
							float scale = 1/(1 - borderMax);
							dist = dist*(1 - maxNorm)*scale + scale*(maxNorm - borderMax)*maxNorm;
						}
						if (dist <= 1) {
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
				map.heightMap[x][z] = height;
				map.minHeight = Math.min(map.minHeight, (int)map.heightMap[x][z]);
				map.minHeight = Math.max(map.minHeight, 0);
				map.maxHeight = Math.max(map.maxHeight, (int)map.heightMap[x][z]);
				

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
						if (distSquare < shortestDist) {
							shortestDist = distSquare;
							shortestBiome = biomePositions[x0][z0];
						}
					}
				}
				map.biomeMap[x][z] = shortestBiome.getFittingReplacement(height + rand.nextFloat()*4 - 2);
			}
		}
	}
	
}
