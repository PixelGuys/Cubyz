package cubyz.world.terrain.generators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.Ore;
import cubyz.world.terrain.CaveBiomeMap;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * Generator of ore veins.
 */

public class OreGenerator implements Generator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "ore");
	}
	
	@Override
	public int getPriority() {
		return 32768; // Somewhere before cave generation.
	}

	private Ore[] ores;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		ores = registries.oreRegistry.registered(new Ore[0]);
	}


	// Works basically similar to cave generation, but considers a lot less chunks and has a few other differences.
	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, CaveMap caveMap, CaveBiomeMap biomeMap) {
		if (!(chunk instanceof NormalChunk)) return;
		FastRandom rand = new FastRandom(seed);
		int rand1 = rand.nextInt() | 1;
		int rand2 = rand.nextInt() | 1;
		int rand3 = rand.nextInt() | 1;
		int cx = wx >> NormalChunk.chunkShift;
		int cy = wy >> NormalChunk.chunkShift;
		int cz = wz >> NormalChunk.chunkShift;
		// Generate caves from all nearby chunks:
		for(int x = cx - 1; x <= cx + 1; ++x) {
			for(int y = cy - 1; y <= cy + 1; ++y) {
				for(int z = cz - 1; z <= cz + 1; ++z) {
					int randX = x*rand1;
					int randY = y*rand2;
					int randZ = z*rand3;
					considerCoordinates(x, y, z, cx, cy, cz, chunk, (randY << 48) ^ (randY >>> 16) ^ (randX << 32) ^ randZ ^ seed);
				}
			}
		}
	}

	private void considerCoordinates(int x, int y, int z, int cx, int cy, int cz, Chunk chunk, long seed) {
		FastRandom rand = new FastRandom(0);
		for(Ore ore : ores) {
			if(ore.maxHeight <= y << NormalChunk.chunkShift) continue;
			// Compose the seeds from some random stats of the ore. They generally shouldn't be the same for two different ores.
			rand.setSeed(seed ^ (ore.maxHeight) ^ (Float.floatToIntBits(ore.size)) ^ Blocks.id(ore.block).getID().charAt(0) ^ Float.floatToIntBits(Blocks.hardness(ore.block)));
			// Determine how many veins of this type start in this chunk. The number depends on parameters set for the specific ore:
			int veins = (int)ore.veins;
			if(ore.veins - veins >= rand.nextFloat()) veins++;
			for(int j = 0; j < veins; ++j) {
				// Choose some in world coordinates to start generating:
				double relX = (x-cx << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				double relY = (y-cy << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				double relZ = (z-cz << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				// Choose a random volume and create a radius from that:
				double size = (rand.nextFloat() + 0.5f)*ore.size;
				double expectedVolume = 2*size/ore.density; // Double the volume, because later the density is actually halfed.
				double radius = Math.cbrt(expectedVolume*3/4/Math.PI);
				int xMin = (int)Math.ceil(relX - radius);
				int xMax = (int)Math.ceil(relX + radius);
				int zMin = (int)Math.ceil(relZ - radius);
				int zMax = (int)Math.ceil(relZ + radius);
				xMin = Math.max(xMin, 0);
				xMax = Math.min(xMax, Chunk.chunkSize*chunk.voxelSize);
				zMin = Math.max(zMin, 0);
				zMax = Math.min(zMax, Chunk.chunkSize*chunk.voxelSize);
				FastRandom noiseRand = new FastRandom(rand.nextLong());

				for(int curX = xMin; curX < xMax; curX += chunk.voxelSize) {
					double distToCenterX = (curX - relX)/radius;
					for(int curZ = zMin; curZ < zMax; curZ += chunk.voxelSize) {
						double distToCenterZ = (curZ - relZ)/radius;
						double yDistance = radius*Math.sqrt(1 - distToCenterX*distToCenterX - distToCenterZ*distToCenterZ);
						int yMin = (int)Math.ceil(relY - yDistance);
						int yMax = (int)Math.ceil(relY + yDistance);
						yMin = Math.max(yMin, 0);
						yMax = Math.min(yMax, Chunk.chunkSize*chunk.voxelSize);

						for(int curY = yMin; curY < yMax; curY += chunk.voxelSize) {
							double distToCenterY = (curY - relY)/radius;
							double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
							if(distToCenter < 1) {
								// Add some roughness. The ore density gets smaller at the edges:
								if((1 - (distToCenter))*ore.density >= noiseRand.nextFloat()) {
									if(ore.canCreateVeinInBlock(chunk.getBlock(curX, curY, curZ))) {
										chunk.updateBlockInGeneration(curX, curY, curZ, ore.block);
									}
								}
							}
						}
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x88773787bc9e0105L;
	}
}
