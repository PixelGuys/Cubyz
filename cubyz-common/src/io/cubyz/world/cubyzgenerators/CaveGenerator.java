package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

public class CaveGenerator implements FancyGenerator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_cave");
	}
	
	@Override
	public int getPriority() {
		return 65536;
	}
	
	private static final int range = 8;
	private static Random rand = new Random();
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");
	private static Block ice = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:ice");
	
	@Override
	public void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, int[][] heightMap, Biome[][] biomeMap) {
		synchronized(rand) {
			rand.setSeed(seed);
			long rand1 = rand.nextLong();
			long rand2 = rand.nextLong();
			// Generate caves from all nearby chunks:
			for(int x = cx - range; x <= cx + range; ++x) {
				for(int z = cz - range; z <= cz + range; ++z) {
					long randX = (long)x*rand1;
					long randZ = (long)z*rand2;
					rand.setSeed(randX ^ randZ ^ seed);
					considerCoordinates(x, z, cx, cz, chunk, vegetationIgnoreMap, heightMap);
				}
			}
		}
	}

	private void createJunctionRoom(long localSeed, int cx, int cz, Block[][][] chunk, double worldX, double worldY, double worldZ, boolean[][] vegetationIgnoreMap, int[][] heightMap) {
		// The junction room is just one single room roughly twice as wide as high.
		float size = 1 + rand.nextFloat()*6;
		double cwx = cx*16 + 8;
		double cwz = cz*16 + 8;
		
		// Determine width and height:
		double xzScale = 1.5 + size;
		// Vary the height/width ratio within 04 and 0.6 to add more variety:
		double yScale = xzScale*(rand.nextFloat()*0.2f + 0.4f);
		// Only care about it if it is inside the current chunk:
		if(worldX >= cwx - 16 - xzScale*2 && worldZ >= cwz - 16 - xzScale*2 && worldX <= cwx + 16 + xzScale*2 && worldZ <= cwz + 16 + xzScale*2) {
			Random localRand = new Random(localSeed);
			// Determine min and max of the current cave segment in all directions.
			int xMin = (int)(worldX - xzScale) - cx*16 - 1;
			int xMax = (int)(worldX + xzScale) - cx*16 + 1;
			int yMin = (int)(worldY - 0.7*yScale - 0.5); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
			int yMax = (int)(worldY + yScale) + 1;
			int zMin = (int)(worldZ - xzScale) - cz*16 - 1;
			int zMax = (int)(worldZ + xzScale) - cz*16 + 1;
			if (xMin < 0)
				xMin = 0;
			if (xMax > 16)
				xMax = 16;
			if (yMin < 1)
				yMin = 1; // Don't make caves expand to the bedrock layer.
			if (yMax > 248)
				yMax = 248;
			if (zMin < 0)
				zMin = 0;
			if (zMax > 16)
				zMax = 16;
			// Go through all blocks within range of the cave center and remove them if they
			// are within range of the center.
			for(int curX = xMin; curX < xMax; ++curX) {
				double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / xzScale;
				
				for(int curZ = zMin; curZ < zMax; ++curZ) {
					double distToCenterZ = ((double) (curZ + cz*16) + 0.5 - worldZ) / xzScale;
					int curYIndex = yMax;
					if(distToCenterX * distToCenterX + distToCenterZ * distToCenterZ < 1.0) {
						for(int curY = yMax - 1; curY >= yMin; --curY) {
							double distToCenterY = ((double) curY + 0.5 - worldY) / yScale;
							double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
							if(distToCenter < 1.0) {
								// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
								if((distToCenter <= 0.9 || localRand.nextInt(6) != 0) && !water.equals(chunk[curX][curZ][curYIndex]) && !ice.equals(chunk[curX][curZ][curYIndex])) {
									chunk[curX][curZ][curYIndex] = null;
									if(heightMap[curX][curZ] == curYIndex)
										vegetationIgnoreMap[curX][curZ] = true;
								}
							}
							--curYIndex;
						}
					}
				}
			}
		}
	}
	private void generateCave(long random, int cx, int cz, Block[][][] chunk, double worldX, double worldY, double worldZ, float size, float direction, float slope, int curStep, int caveLength, double caveHeightModifier, boolean[][] vegetationIgnoreMap, int[][] heightMap) {
		double cwx = (double) (cx*16 + 8);
		double cwz = (double) (cz*16 + 8);
		float directionModifier = 0.0F;
		float slopeModifier = 0.0F;
		Random localRand = new Random(random);
		// Choose a random cave length if not specified:
		if(caveLength == 0) {
			int local = range*16 - 16;
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
				this.generateCave(localRand.nextLong(), cx, cz, chunk, worldX, worldY, worldZ, localRand.nextFloat()*0.5F + 0.5F, direction - ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1, vegetationIgnoreMap, heightMap);
				this.generateCave(localRand.nextLong(), cx, cz, chunk, worldX, worldY, worldZ, localRand.nextFloat()*0.5F + 0.5F, direction + ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1, vegetationIgnoreMap, heightMap);
				return;
			}

			// Add a small chance to ignore one point of the cave to make the walls look more rough.
			if(localRand.nextInt(4) != 0) {
				double deltaX = worldX - cwx;
				double deltaZ = worldZ - cwz;
				double stepsLeft = (double)(caveLength - curStep);
				double maxLength = (double)(size + 18);
				// Abort if the cave is getting to long:
				if(deltaX*deltaX + deltaZ*deltaZ - stepsLeft*stepsLeft > maxLength*maxLength) {
					return;
				}

				// Only care about it if it is inside the current chunk:
				if(worldX >= cwx - 16 - xzScale*2 && worldZ >= cwz - 16 - xzScale*2 && worldX <= cwx + 16 + xzScale*2 && worldZ <= cwz + 16 + xzScale*2) {
					// Determine min and max of the current cave segment in all directions.
					int xMin = (int)(worldX - xzScale) - cx*16 - 1;
					int xMax = (int)(worldX + xzScale) - cx*16 + 1;
					int yMin = (int)(worldY - 0.7*yScale - 0.5); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
					int yMax = (int)(worldY + yScale) + 1;
					int zMin = (int)(worldZ - xzScale) - cz*16 - 1;
					int zMax = (int)(worldZ + xzScale) - cz*16 + 1;
					if (xMin < 0)
						xMin = 0;
					if (xMax > 16)
						xMax = 16;
					if (yMin < 1)
						yMin = 1; // Don't make caves expand to the bedrock layer.
					if (yMax > 248)
						yMax = 248;
					if (zMin < 0)
						zMin = 0;
					if (zMax > 16)
						zMax = 16;

					// Go through all blocks within range of the cave center and remove them if they
					// are within range of the center.
					for(int curX = xMin; curX < xMax; ++curX) {
						double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / xzScale;
						
						for(int curZ = zMin; curZ < zMax; ++curZ) {
							double distToCenterZ = ((double) (curZ + cz*16) + 0.5 - worldZ) / xzScale;
							int curYIndex = yMax;
							if(distToCenterX * distToCenterX + distToCenterZ * distToCenterZ < 1.0) {
								for(int curY = yMax - 1; curY >= yMin; --curY) {
									double distToCenterH = ((double) curY + 0.5 - worldY) / yScale;
									if(distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterZ*distToCenterZ < 1.0 && !water.equals(chunk[curX][curZ][curYIndex]) && !ice.equals(chunk[curX][curZ][curYIndex])) {
										chunk[curX][curZ][curYIndex] = null;
										if(heightMap[curX][curZ] == curYIndex)
											vegetationIgnoreMap[curX][curZ] = true;
									}
									--curYIndex;
								}
							}
						}
					}
				}
			}
		}
	}

	private void considerCoordinates(int x, int z, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap, int[][] heightMap) {
		// Determine how many caves start in this chunk. Make sure the number is usually close to one, but can also rarely reach higher values.
		int caveSpawns = rand.nextInt(rand.nextInt(rand.nextInt(12) + 1) + 1);

		// Add a 5/6 chance to skip this chunk to make sure the underworld isn't flooded with caves.
		if (rand.nextInt(6) != 0) {
			caveSpawns = 0;
		}

		for(int j = 0; j < caveSpawns; ++j) {
			// Choose some in world coordinates to start generating:
			double worldX = (double)((x << 4) + rand.nextInt(16));
			double worldY = (double)200*Math.pow(rand.nextDouble(), 4); // Make more caves on the bottom of the world.
			double worldZ = (double)((z << 4) + rand.nextInt(16));
			// Randomly pick how many caves origin from this location and add a junction room if there are more than 2:
			int starters = 1+rand.nextInt(4);
			if(starters > 1) {
				createJunctionRoom(rand.nextLong(), cx, cz, chunk, worldX, worldY, worldZ, vegetationIgnoreMap, heightMap);
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

				generateCave(rand.nextLong(), cx, cz, chunk, worldX, worldY, worldZ, size, direction, slope, 0, 0, 1, vegetationIgnoreMap, heightMap);
			}
		}
	}

}
