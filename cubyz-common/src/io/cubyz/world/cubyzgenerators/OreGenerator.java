package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Ore;

public class OreGenerator implements Generator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_ore");
	}
	
	@Override
	public int getPriority() {
		return 32768; // Somewhere before cave generation.
	}
	
	private static Block stone = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:stone");

	public static Ore[] ores;
	public OreGenerator() {}


	// Works basically similar to cave generation, but considers a lot less chunks and has a few other differences.
	@Override
	public void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap) {
		Random rand = new Random(seed);
		int rand1 = rand.nextInt() | 1;
		int rand2 = rand.nextInt() | 1;
		// Generate caves from all nearby chunks:
		for(int x = cx - 1; x <= cx + 1; ++x) {
			for(int z = cz - 1; z <= cz + 1; ++z) {
				int randX = x*rand1;
				int randZ = z*rand2;
				rand.setSeed((randX << 32) ^ randZ ^ seed);
				considerCoordinates(x, z, cx, cz, chunk, (randX << 32) ^ randZ ^ seed);
			}
		}
	}
	private void considerCoordinates(int x, int z, int cx, int cz, Block[][][] chunk, long seed) {
		Random rand = new Random();
		for(int i = 0; i < ores.length; i++) {
			// Compose the seeds from some random stats of the ore. They generally shouldn't be the same for two different ores.
			rand.setSeed(seed^(ores[i].maxHeight)^(Float.floatToIntBits(ores[i].size))^ores[i].getRegistryID().getID().charAt(0)^Float.floatToIntBits(ores[i].getHardness()));
			// Determine how many veins of this type start in this chunk. The number depends on parameters set for the specific ore:
			int veins = (int)Math.round(2*ores[i].veins*rand.nextFloat());
			for(int j = 0; j < veins; ++j) {
				// Choose some in world coordinates to start generating:
				double worldX = (double)((x << 4) + rand.nextInt(16));
				double worldY = (double)rand.nextInt(ores[i].maxHeight);
				double worldZ = (double)((z << 4) + rand.nextInt(16));
				float direction = rand.nextFloat()*(float)Math.PI*2.0F;
				float slope = (rand.nextFloat() - 0.5F)/4.0F;
				int size = (int)Math.round(2*ores[i].size*rand.nextFloat()); // Desired number of ore blocks in this vein. Might not get reached depending on the underground conditions. For example the last ore placed has a lower chance of getting placed all blocks.
				// Using V = π/2 *length*radius² which is the volume formula for the non-direction changing shape of the ore vein.
				// Since the actual volume is smaller because the vein changes direction, I'll use the approximation V = 1.5*length*radius²
				// Start with some arbitrary length that isn't too big( < 6, so the size is also accounted for):
				int length = 1 + rand.nextInt(5);
				float radius = (float)Math.sqrt(size/(float)length/1.5);
				if(2*radius + length > 8) { // Make sure the vein isn't too big:
					radius = 4 - length/2.0f;
				}
				generateVein(rand.nextLong(), cx, cz, chunk, worldX, worldY, worldZ, radius, direction, slope, length, ores[i]);
			}
		}
	}
	private void generateVein(long random, int cx, int cz, Block[][][] chunk, double worldX, double worldY, double worldZ, float radius, float direction, float slope, int veinLength, Block ore) {
		double cwx = (double) (cx*16 + 8);
		double cwz = (double) (cz*16 + 8);
		float directionModifier = 0.0F;
		float slopeModifier = 0.0F;
		Random localRand = new Random(random);
		for(int curStep = 1; curStep < veinLength; ++curStep) {
			double scale = Math.sin(curStep*Math.PI/veinLength)*radius;
			// Move vein center point one unit into a direction given by slope and direction:
			float xzunit = (float)Math.cos(slope);
			float hunit = (float)Math.sin(slope);
			worldX += Math.cos(direction) * xzunit;
			worldY += hunit;
			worldZ += Math.sin(direction)*xzunit;
			slope += slopeModifier * 0.1F;
			direction += directionModifier * 0.1F;
			slopeModifier *= 0.9F;
			directionModifier *= 0.75F;
			slopeModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*2;
			directionModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*4;

			// Add a small chance to ignore one point of the vein to make the walls look more rough.
			if(localRand.nextInt(4) != 0) {
				double deltaX = worldX - cwx;
				double deltaZ = worldZ - cwz;
				double stepsLeft = (double)(veinLength - curStep);
				double maxLength = (double)(radius + 8);
				// Abort if the vein is getting to far away from this chunk:
				if(deltaX*deltaX + deltaZ*deltaZ - stepsLeft*stepsLeft > maxLength*maxLength) {
					return;
				}

				// Only care about it if it is inside the current chunk:
				if(worldX >= cwx - 8 - scale && worldZ >= cwz - 8 - scale && worldX <= cwx + 8 + scale && worldZ <= cwz + 8 + scale) {
					// Determine min and max of the current vein segment in all directions.
					int xmin = (int)(worldX - scale) - cx*16 - 1;
					int xmax = (int)(worldX + scale) - cx*16 + 1;
					int ymin = (int)(worldY - scale) - 1;
					int ymax = (int)(worldY + scale) + 1;
					int zmin = (int)(worldZ - scale) - cz*16 - 1;
					int zmax = (int)(worldZ + scale) - cz*16 + 1;
					if (xmin < 0)
						xmin = 0;
					if (xmax > 16)
						xmax = 16;
					if (ymin < 1)
						ymin = 1; // Don't make veins expand to the bedrock layer.
					if (ymax > 248)
						ymax = 248;
					if (zmin < 0)
						zmin = 0;
					if (zmax > 16)
						zmax = 16;

					// Go through all blocks within range of the vein center and change them if they
					// are within range of the center.
					for(int curX = xmin; curX < xmax; ++curX) {
						double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / scale;
						
						for(int curZ = zmin; curZ < zmax; ++curZ) {
							double distToCenterZ = ((double) (curZ + cz*16) + 0.5 - worldZ) / scale;
							int curHeightIndex = ymax;
							if(distToCenterX * distToCenterX + distToCenterZ * distToCenterZ < 1.0) {
								for(int curY = ymax - 1; curY >= ymin; --curY) {
									double distToCenterY = ((double) curY + 0.5 - worldY) / scale;
									// The first ore that gets into a position will be placed:
									if(chunk[curX][curZ][curHeightIndex] == stone && distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ < 1.0) {
										chunk[curX][curZ][curHeightIndex] = ore;
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

	@Override
	public long getGeneratorSeed() {
		return 0x88773787bc9e0105L;
	}
}
