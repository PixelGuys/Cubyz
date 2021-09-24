package cubyz.world.cubyzgenerators;

import java.util.Random;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.terrain.MapFragment;

/**
 * Generates caves using perlin worms algorithm.
 */

public class CaveGenerator implements Generator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_cave");
	}
	
	@Override
	public int getPriority() {
		return 65536;
	}
	
	private static final int range = 8;
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");
	private static Block ice = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:ice");
	
	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ServerWorld world) {
		Random rand = new Random(seed);
		int rand1 = rand.nextInt() | 1;
		int rand2 = rand.nextInt() | 1;
		int rand3 = rand.nextInt() | 1;
		int cx = wx >> NormalChunk.chunkShift;
		int cy = wy >> NormalChunk.chunkShift;
		int cz = wz >> NormalChunk.chunkShift;
		// Generate caves from all nearby chunks:
		for(int x = cx - range; x <= cx + range; ++x) {
			for(int y = cy - range; y <= cy + range; ++y) {
				for(int z = cz - range; z <= cz + range; ++z) {
					int randX = x*rand1;
					int randY = y*rand2;
					int randZ = z*rand3;
					rand.setSeed((randY << 48) ^ (randY >>> 16) ^ (randX << 32) ^ randZ ^ seed);
					considerCoordinates(x, y, z, wx, wy, wz, chunk, rand);
				}
			}
		}
	}

	private void createJunctionRoom(long localSeed, int wx, int wy, int wz, Chunk chunk, double worldX, double worldY, double worldZ, Random rand) {
		// The junction room is just one single room roughly twice as wide as high.
		float size = 1 + rand.nextFloat()*6;
		double cwx = wx + NormalChunk.chunkSize/2;
		double cwz = wz + NormalChunk.chunkSize/2;
		
		// Determine width and height:
		double xzScale = 1.5 + size;
		// Vary the height/width ratio within 04 and 0.6 to add more variety:
		double yScale = xzScale*(rand.nextFloat()*0.2f + 0.4f);
		// Only care about it if it is inside the current chunk:
		if(worldX >= cwx - NormalChunk.chunkSize - xzScale*2 && worldZ >= cwz - NormalChunk.chunkSize - xzScale*2 && worldX <= cwx + NormalChunk.chunkSize + xzScale*2 && worldZ <= cwz + NormalChunk.chunkSize + xzScale*2) {
			Random localRand = new Random(localSeed);
			// Determine min and max of the current cave segment in all directions.
			int xMin = (int)(worldX - xzScale) - wx - 1;
			int xMax = (int)(worldX + xzScale) - wx + 1;
			int yMin = (int)(worldY - 0.7*yScale) - wy; // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
			int yMax = (int)(worldY + yScale) - wy + 1;
			int zMin = (int)(worldZ - xzScale) - wz - 1;
			int zMax = (int)(worldZ + xzScale) - wz + 1;
			if (xMin < 0)
				xMin = 0;
			if (xMax > NormalChunk.chunkSize)
				xMax = NormalChunk.chunkSize;
			if (yMin < 0)
				yMin = 0;
			if (yMax > NormalChunk.chunkSize)
				yMax = NormalChunk.chunkSize;
			if (zMin < 0)
				zMin = 0;
			if (zMax > NormalChunk.chunkSize)
				zMax = NormalChunk.chunkSize;
			// Go through all blocks within range of the cave center and remove them if they
			// are within range of the center.
			for(int curX = xMin; curX < xMax; ++curX) {
				double distToCenterX = ((double) (curX + wx) - worldX) / xzScale;
				
				for(int curZ = zMin; curZ < zMax; ++curZ) {
					double distToCenterZ = ((double) (curZ + wz) - worldZ) / xzScale;
					if(distToCenterX * distToCenterX + distToCenterZ * distToCenterZ < 1.0) {
						for(int curY = yMax - 1; curY >= yMin; --curY) {
							double distToCenterY = ((double) (curY + wy) - worldY) / yScale;
							double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
							if(distToCenter < 1.0) {
								// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
								if((distToCenter <= 0.9 || localRand.nextInt(6) != 0) && !water.equals(chunk.getBlock(curX, curY, curZ)) && !ice.equals(chunk.getBlock(curX, curY, curZ))) {
									chunk.updateBlock(curX, curY, curZ, null);
								}
							}
						}
					}
				}
			}
		}
	}
	private void generateCave(long random, int wx, int wy, int wz, Chunk chunk, double worldX, double worldY, double worldZ, float size, float direction, float slope, int curStep, int caveLength, double caveHeightModifier) {
		double cwx = (double) (wx + NormalChunk.chunkSize/2);
		double cwz = (double) (wz + NormalChunk.chunkSize/2);
		float directionModifier = 0.0F;
		float slopeModifier = 0.0F;
		Random localRand = new Random(random);
		// Choose a random cave length if not specified:
		if(caveLength == 0) {
			int local = range*NormalChunk.chunkSize - NormalChunk.chunkSize;
			caveLength = local - localRand.nextInt(local / 4);
		}

		int smallJunctionPos = localRand.nextInt(caveLength / 2) + caveLength / 4;

		for(boolean highSlope = localRand.nextInt(6) == 0; curStep < caveLength; ++curStep) {
			double xzScale = 1.5 + Math.sin(curStep*Math.PI/caveLength)*size;
			double yScale = xzScale*caveHeightModifier;
			// Move cave center point one unit into a direction given by slope and direction:
			float xzUnit = (float)Math.cos(slope);
			float yUnit = (float)Math.sin(slope);
			worldX += Math.cos(direction) * xzUnit;
			worldY += yUnit;
			worldZ += Math.sin(direction)*xzUnit;

			// reduce the slope, so most caves will be flat most of the time.
			if(highSlope) {
				slope *= 0.92F;
			} else {
				slope *= 0.7F;
			}

			slope += slopeModifier * 0.1F;
			direction += directionModifier * 0.1F;
			slopeModifier *= 0.9F;
			directionModifier *= 0.75F;
			slopeModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*2;
			directionModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*4;
			
			// Add a small junction at a random point in the cave:
			if(curStep == smallJunctionPos && size > 1 && caveLength > 0) {
				this.generateCave(localRand.nextLong(), wx, wy, wz, chunk, worldX, worldY, worldZ, localRand.nextFloat()*0.5F + 0.5F, direction - ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				this.generateCave(localRand.nextLong(), wx, wy, wz, chunk, worldX, worldY, worldZ, localRand.nextFloat()*0.5F + 0.5F, direction + ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				return;
			}

			// Add a small chance to ignore one point of the cave to make the walls look more rough.
			if(localRand.nextInt(4) != 0) {
				double deltaX = worldX - cwx;
				double deltaZ = worldZ - cwz;
				double stepsLeft = (double)(caveLength - curStep);
				double maxLength = (double)(size + 8);
				// Abort if the cave is getting to far away from this chunk:
				if(deltaX*deltaX + deltaZ*deltaZ - stepsLeft*stepsLeft > maxLength*maxLength) {
					return;
				}

				// Only care about it if it is inside the current chunk:
				if(worldX >= cwx - NormalChunk.chunkSize/2 - xzScale && worldZ >= cwz - NormalChunk.chunkSize/2 - xzScale && worldX <= cwx + NormalChunk.chunkSize/2 + xzScale && worldZ <= cwz + NormalChunk.chunkSize/2 + xzScale) {
					// Determine min and max of the current cave segment in all directions.
					int xMin = (int)(worldX - xzScale) - wx - 1;
					int xMax = (int)(worldX + xzScale) - wx + 1;
					int yMin = (int)(worldY - 0.7*yScale) - wy; // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
					int yMax = (int)(worldY + yScale) - wy + 1;
					int zMin = (int)(worldZ - xzScale) - wz - 1;
					int zMax = (int)(worldZ + xzScale) - wz + 1;
					if (xMin < 0)
						xMin = 0;
					if (xMax > NormalChunk.chunkSize)
						xMax = NormalChunk.chunkSize;
					if (yMin < 0)
						yMin = 0;
					if (yMax > NormalChunk.chunkSize)
						yMax = NormalChunk.chunkSize;
					if (zMin < 0)
						zMin = 0;
					if (zMax > NormalChunk.chunkSize)
						zMax = NormalChunk.chunkSize;

					// Go through all blocks within range of the cave center and remove them if they
					// are within range of the center.
					for(int curX = xMin; curX < xMax; ++curX) {
						double distToCenterX = ((double) (curX + wx) - worldX) / xzScale;
						
						for(int curZ = zMin; curZ < zMax; ++curZ) {
							double distToCenterZ = ((double) (curZ + wz) - worldZ) / xzScale;
							if(distToCenterX * distToCenterX + distToCenterZ * distToCenterZ < 1.0) {
								for(int curY = yMax - 1; curY >= yMin; --curY) {
									double distToCenterH = ((double) (curY + wy) - worldY) / yScale;
									if(distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterZ*distToCenterZ < 1.0 && !water.equals(chunk.getBlock(curX, curY, curZ)) && !ice.equals(chunk.getBlock(curX, curY, curZ))) {
										chunk.updateBlock(curX, curY, curZ, null);
									}
								}
							}
						}
					}
				}
			}
		}
	}

	private void considerCoordinates(int x, int y, int z, int wx, int wy, int wz, Chunk chunk, Random rand) {
		// Use a height depending chance to spawn a cave in this chunk. Below y=-128 caves spawn roughly every 16 chunks, Above y=128 no caves spawn:
		if(rand.nextInt(512) > (2 - 2*Math.max((y << NormalChunk.chunkShift) + 128, 0)/256.0f)*NormalChunk.chunkSize) return;

		// Choose some in world coordinates to start generating:
		double worldX = (double)((x << NormalChunk.chunkShift) + rand.nextInt(NormalChunk.chunkSize));
		double worldY = (double)((y << NormalChunk.chunkShift) + rand.nextInt(NormalChunk.chunkSize));
		double worldZ = (double)((z << NormalChunk.chunkShift) + rand.nextInt(NormalChunk.chunkSize));
		// Randomly pick how many caves origin from this location and add a junction room if there are more than 2:
		int starters = 1+rand.nextInt(4);
		if(starters > 1) {
			createJunctionRoom(rand.nextLong(), wx, wy, wz, chunk, worldX, worldY, worldZ, rand);
		}
		
		for(int i = 0; i < starters; ++i) {
			float direction = rand.nextFloat()*(float)Math.PI*2.0F;
			float slope = (rand.nextFloat() - 0.5F)/4.0F;
			// Greatly increase the slope for a small amount of random caves:
			if(rand.nextInt(16) == 0) {
				slope *= 8.0F;
			}
			float size = rand.nextFloat()*2.0F + rand.nextFloat();
			// Increase the size of a small proportion of the caves by up to 4 times the original size:
			if(rand.nextInt(10) == 0) {
				size *= rand.nextFloat()*rand.nextFloat()*3.0F + 1.0F;
			}

			generateCave(rand.nextLong(), wx, wy, wz, chunk, worldX, worldY, worldZ, size, direction, slope, 0, 0, 1);
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0xb898ec9ce9d2ef37L;
	}
}
