package io.cubyz.world.cubyzgenerators;

import java.util.Arrays;
import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.base.init.BlockInit;
import io.cubyz.blocks.Block;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

public class CrystalCavernGenerator implements FancyGenerator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_crystal_cavern");
	}
	
	@Override
	public int getPriority() {
		return 65537; // Directly after normal caves.
	}
	
	private static final int range = 32;
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
					long randY = (long)z*rand2;
					rand.setSeed(randX ^ randY ^ seed);
					considerCoordinates(x, z, cx, cz, chunk, vegetationIgnoreMap, heightMap);
				}
			}
		}
	}
	
	private void generateCave(long random, int cx, int cy, Block[][][] chunk, double worldX, double worldH, double worldY, float size, float direction, float slope, int curStep, double caveHeightModifier, boolean[][] vegetationIgnoreMap, int[][] heightMap, int[][] crystalSpawns, int[] index) {
		double cwx = (double) (cx*16 + 8);
		double cwy = (double) (cy*16 + 8);
		float directionModifier = 0.0F;
		float slopeModifier = 0.0F;
		Random localRand = new Random(random);
		// Choose a random cave length if not specified:
		int local = range*16 - 2*(int)size;
		int caveLength = local - localRand.nextInt(local / 4);

		for(boolean highSlope = localRand.nextInt(6) == 0; curStep < caveLength; ++curStep) {
			double xyscale = 1.5 + Math.sin(curStep*Math.PI/caveLength)*size;
			double hscale = xyscale*caveHeightModifier;
			// Move cave center point one unit into a direction given by slope and direction:
			float xzunit = (float)Math.cos(slope);
			float hunit = (float)Math.sin(slope);
			double dx = Math.cos(direction) * xzunit;
			double dz = Math.sin(direction) * xzunit;
			worldX += dx;
			worldH += hunit;
			worldY += Math.sin(direction)*xzunit;

			if(highSlope) {
				slope *= 0.92F;
			} else {
				slope *= 0.7F;
			}

			slope += slopeModifier * 0.01F;
			direction += directionModifier * 0.01F;
			slopeModifier *= 0.9F;
			directionModifier *= 0.75F;
			slopeModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*2;
			directionModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*4;
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
				int hmin = (int)(worldH - hscale - 1); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
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
								double distToCenterH = ((double) curH + 0.5 - worldH) / (hscale);
								if(distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterY*distToCenterY < 1.0 && !water.equals(chunk[curX][curY][curHeightIndex]) && !ice.equals(chunk[curX][curY][curHeightIndex])) {
									chunk[curX][curY][curHeightIndex] = null;
									if(heightMap[curX][curY] == curHeightIndex)
										vegetationIgnoreMap[curX][curY] = true;
								}
								--curHeightIndex;
							}
						}
					}
				}
			}
			// Consider a good amount of crystal spawns in the region.
			for(int i = 0; i < 20; i++) {
				// Choose a random point on the surface to generate a crystal there:
				double theta = 2*Math.PI*rand.nextDouble();
		        double phi = Math.acos(1 - 2*rand.nextDouble());
		        double x = Math.sin(phi)*Math.cos(theta);
		        double y = Math.sin(phi)*Math.sin(theta);
		        double z = Math.cos(phi);
		        // Check if the crystal touches the wall:
		        if(Math.abs(dx*x+hunit*y+dz*z) < 0.05) {
			        crystalSpawns[index[0]++] = new int[] {(int)(worldX + x*xyscale), (int)(worldH + y*hscale), (int)(worldY + z*xyscale)};
			        break; // Generate at most one crystal per cave slice.
		        }
			}
		}
	}
	
	private double distSqr(double x, double y, double z) {
		return x*x+y*y+z*z;
	}
	
	private void considerCrystal(int wx, int wz, int[] xyz, Block[][][] chunk, long seed) {
		if(xyz[0] >= wx-32 && xyz[0] <= wx+48 && xyz[2] >= wz-32 && xyz[2] <= wz+48) {
			int x = xyz[0]-wx;
			int y = xyz[1];
			int z = xyz[2]-wz;
			Random rand = new Random(seed);
			// Make some crystal spikes in random directions:
			int spikes = rand.nextInt(4) + 4;
			for(int i = 0; i < spikes; i++) {
				int length = rand.nextInt(16)+16;
				// Choose a random direction:
				double theta = 2*Math.PI*rand.nextDouble();
		        double phi = Math.acos(1 - 2*rand.nextDouble());
		        double dx = Math.sin(phi)*Math.cos(theta);
		        double dy = Math.sin(phi)*Math.sin(theta);
		        double dz = Math.cos(phi);
		        for(int j = 0; j < length; j++) {
		        	double x2 = x+dx*j;
		        	double y2 = y+dy*j;
		        	double z2 = z+dz*j;
		        	double size = 12*(length-j)/length/spikes;
		        	int xMin = (int)(x2-size);
		        	int xMax = (int)(x2+size);
		        	int yMin = (int)(y2-size);
		        	int yMax = (int)(y2+size);
		        	int zMin = (int)(z2-size);
		        	int zMax = (int)(z2+size);
		        	for(int x3 = xMin; x3 <= xMax; x3++) {
			        	for(int y3 = yMin; y3 <= yMax; y3++) {
				        	for(int z3 = zMin; z3 <= zMax; z3++) {
				        		double dist = distSqr(x3-x2, y3-y2, z3-z2);
				        		if(dist <= size*size) {
						        	if(x3 >= 0 && x3 < 16 && y3 >= 0 && y3 < 256 && z3 >= 0 && z3 < 16) {
						        		if(chunk[(int)x3][(int)z3][(int)y3] == null) {
						        			chunk[(int)x3][(int)z3][(int)y3] = BlockInit.glowCrystal;
						        		}
						        	}
				        		}
				        	}
			        	}
		        	}
		        }
			}
		}
	}

	private void considerCoordinates(int x, int y, int cx, int cy, Block[][][] chunk, boolean[][] vegetationIgnoreMap, int[][] heightMap) {
		if(rand.nextInt(1024) != 0) return; // This should be pretty rare(mostly because it is so huge).
		// Choose some in world coordinates to start generating:
		double worldX = (double)((x << 4) + rand.nextInt(16));
		double worldH = 50; // TODO: More varied.
		double worldY = (double)((y << 4) + rand.nextInt(16));
		float direction = rand.nextFloat()*(float)Math.PI*2.0F;
		float slope = (rand.nextFloat() - 0.5F)/4.0F;
		float size = rand.nextFloat()*2.0F + rand.nextFloat()+40.0f;
		int[][] crystalSpawns = new int[1024][3];
		int[] index = {0};
		long rand1 = rand.nextLong();
		long rand2 = rand.nextLong();
		long rand3 = rand.nextLong();
		generateCave(rand.nextLong(), cx, cy, chunk, worldX, worldH, worldY, size, direction, slope, 0, 0.75, vegetationIgnoreMap, heightMap, crystalSpawns, index);

		// Generate the crystals:
		for(int i = 0; i < index[0]; i++) {
			considerCrystal(cx << 4, cy << 4, crystalSpawns[i], chunk, crystalSpawns[i][0]*rand1 + crystalSpawns[i][1]*rand2 + crystalSpawns[i][2]*rand3);
		}
	}
}
