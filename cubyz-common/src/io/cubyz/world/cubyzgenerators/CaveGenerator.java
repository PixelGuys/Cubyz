package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;

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
	private static Random rand = new Random();
	
	@Override
	public void generate(long seed, int cx, int cy, Block[][][] chunk) {
		synchronized(rand) {
			rand.setSeed(seed);
			long rand1 = rand.nextLong();
			long rand2 = rand.nextLong();
			// Generate caves from all nearby chunks:
			for(int x = cx - range; x <= cx + range; ++x) {
				for(int y = cy - range; y <= cy + range; ++y) {
					long randX = (long)x*rand1;
					long randY = (long)y*rand2;
					rand.setSeed(randX ^ randY ^ seed);
					considerCoordinates(x, y, cx, cy, chunk);
				}
			}
		}
	}

	private void createJunctionRoom(long localSeed, int cx, int cy, Block[][][] chunk, double worldX, double worldH, double worldY) {
		// The junction room is just one single room roughly twice as wide as high.
		float size = 1 + rand.nextFloat()*6;
		double cwx = cx*16 + 8;
		double cwy = cy*16 + 8;
		
		// Determine width and height:
		double xyscale = 1.5 + size;
		// Vary the height/width ratio within 04 and 0.6 to add more variety:
		double hscale = xyscale*(rand.nextFloat()*0.2f + 0.4f);
		// Only care about it if it is inside the current chunk:
		if(worldX >= cwx - 16 - xyscale*2 && worldY >= cwy - 16 - xyscale*2 && worldX <= cwx + 16 + xyscale*2 && worldY <= cwy + 16 + xyscale*2) {
			Random localRand = new Random(localSeed);
			// Determine min and max of the current cave segment in all directions.
			int xmin = (int)(worldX - xyscale) - cx*16 - 1;
			int xmax = (int)(worldX + xyscale) - cx*16 + 1;
			int hmin = (int)(worldH - 0.7*hscale - 0.5); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
			int hmax = (int)(worldH + hscale) + 1;
			int ymin = (int)(worldY - xyscale) - cy*16 - 1;
			int ymax = (int)(worldY + xyscale) - cy*16 + 1;
			if (xmin < 0)
				xmin = 0;
			if (xmax > 16)
				xmax = 16;
			if (hmin < 1)
				hmin = 1; // Don't make caves expand to the bedrock layer.
			if (hmax > 248)
				hmax = 248;
			if (ymin < 0)
				ymin = 0;
			if (ymax > 16)
				ymax = 16;
			// Go through all blocks within range of the cave center and remove them if they
			// are within range of the center.
			for(int curX = xmin; curX < xmax; ++curX) {
				double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / xyscale;
				
				for(int curY = ymin; curY < ymax; ++curY) {
					double distToCenterY = ((double) (curY + cy*16) + 0.5 - worldY) / xyscale;
					int curHeightIndex = hmax;
					if(distToCenterX * distToCenterX + distToCenterY * distToCenterY < 1.0) {
						for(int curH = hmax - 1; curH >= hmin; --curH) {
							double distToCenterH = ((double) curH + 0.5 - worldH) / hscale;
							double distToCenter = distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterY*distToCenterY;
							if(distToCenter < 1.0) {
								// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
								if(distToCenter <= 0.9 || localRand.nextInt(6) != 0)
									chunk[curX][curY][curHeightIndex] = null;
							}
							--curHeightIndex;
						}
					}
				}
			}
		}
	}
	private void generateCave(long random, int cx, int cy, Block[][][] chunk, double worldX, double worldH, double worldY, float size, float direction, float slope, int curStep, int caveLength, double caveHeightModifier) {
		double cwx = (double) (cx*16 + 8);
		double cwy = (double) (cy*16 + 8);
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
			double xyscale = 1.5 + Math.sin(curStep*Math.PI/caveLength)*size;
			double hscale = xyscale*caveHeightModifier;
			// Move cave center point one unit into a direction given by slope and direction:
			float xzunit = (float)Math.cos(slope);
			float hunit = (float)Math.sin(slope);
			worldX += Math.cos(direction) * xzunit;
			worldH += hunit;
			worldY += Math.sin(direction)*xzunit;

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
				this.generateCave(localRand.nextLong(), cx, cy, chunk, worldX, worldH, worldY, localRand.nextFloat()*0.5F + 0.5F, direction - ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				this.generateCave(localRand.nextLong(), cx, cy, chunk, worldX, worldH, worldY, localRand.nextFloat()*0.5F + 0.5F, direction + ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				return;
			}

			// Add a small chance to ignore one point of the cave to make the walls look more rough.
			if(localRand.nextInt(4) != 0) {
				double deltaX = worldX - cwx;
				double deltaY = worldY - cwy;
				double stepsLeft = (double)(caveLength - curStep);
				double maxLength = (double)(size + 18);
				// Abort if the cave is getting to long:
				if(deltaX*deltaX + deltaY*deltaY - stepsLeft*stepsLeft > maxLength*maxLength) {
					return;
				}

				// Only care about it if it is inside the current chunk:
				if(worldX >= cwx - 16 - xyscale*2 && worldY >= cwy - 16 - xyscale*2 && worldX <= cwx + 16 + xyscale*2 && worldY <= cwy + 16 + xyscale*2) {
					// Determine min and max of the current cave segment in all directions.
					int xmin = (int)(worldX - xyscale) - cx*16 - 1;
					int xmax = (int)(worldX + xyscale) - cx*16 + 1;
					int hmin = (int)(worldH - 0.7*hscale - 0.5); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
					int hmax = (int)(worldH + hscale) + 1;
					int ymin = (int)(worldY - xyscale) - cy*16 - 1;
					int ymax = (int)(worldY + xyscale) - cy*16 + 1;
					if (xmin < 0)
						xmin = 0;
					if (xmax > 16)
						xmax = 16;
					if (hmin < 1)
						hmin = 1; // Don't make caves expand to the bedrock layer.
					if (hmax > 248)
						hmax = 248;
					if (ymin < 0)
						ymin = 0;
					if (ymax > 16)
						ymax = 16;

					// Go through all blocks within range of the cave center and remove them if they
					// are within range of the center.
					for(int curX = xmin; curX < xmax; ++curX) {
						double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / xyscale;
						
						for(int curY = ymin; curY < ymax; ++curY) {
							double distToCenterY = ((double) (curY + cy*16) + 0.5 - worldY) / xyscale;
							int curHeightIndex = hmax;
							if(distToCenterX * distToCenterX + distToCenterY * distToCenterY < 1.0) {
								for(int curH = hmax - 1; curH >= hmin; --curH) {
									double distToCenterH = ((double) curH + 0.5 - worldH) / hscale;
									if(distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterY*distToCenterY < 1.0) {
										chunk[curX][curY][curHeightIndex] = null;
									}
									--curHeightIndex;
								}
							}
						}
					}
				}
			}
		}
	}

	private void considerCoordinates(int x, int y, int cx, int cy, Block[][][] chunk) {
		// Determine how many caves start in this chunk. Make sure the number is usually close to one, but can also rarely reach higher values.
		int caveSpawns = rand.nextInt(rand.nextInt(rand.nextInt(15) + 1) + 1);

		// Add a 5/6 chance to skip this chunk to make sure the underworld isn't flooded with caves.
		if (rand.nextInt(6) != 0) {
			caveSpawns = 0;
		}

		for(int j = 0; j < caveSpawns; ++j) {
			// Choose some in world coordinates to start generating:
			double worldX = (double)((x << 4) + rand.nextInt(16));
			double worldH = (double)rand.nextInt(rand.nextInt(200) + 8); // Make more caves on the bottom of the world.
			double worldY = (double)((y << 4) + rand.nextInt(16));
			// Randomly pick how many caves origin from this location and add a junction room if there are more than 2:
			int starters = 1+rand.nextInt(4);
			if(starters > 1) {
				createJunctionRoom(rand.nextLong(), cx, cy, chunk, worldX, worldH, worldY);
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

				generateCave(rand.nextLong(), cx, cy, chunk, worldX, worldH, worldY, size, direction, slope, 0, 0, 1);
			}
		}
	}

}
