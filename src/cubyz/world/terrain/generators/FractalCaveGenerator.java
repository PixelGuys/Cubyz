package cubyz.world.terrain.generators;

import java.util.Random;

import org.joml.Vector3d;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.Random3D;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.ChunkManager;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.MapFragment;

/**
 * Generates caves using a fractal(=fast) algorithm.
 */

public class FractalCaveGenerator implements Generator {
	
	private static final int range = 8;
	private static final int BRANCH_LENGTH = 64;
	private static final float SPLITTING_CHANCE = 0.4f;
	private static final float SPLIT_FACTOR = 1.0f;
	private static final float SPLIT_FACTOR_Y = SPLIT_FACTOR*0.5f; // Slightly reduced to reduce splits in y-direction
	private static final float MAX_SPLIT_LENGTH = 128;
	private static final float BRANCH_CHANCE = 0.4f;
	private static final float MIN_RADIUS = 2.0f;
	private static final float MAX_INITIAL_RADIUS = 5;
	private static final float HEIGHT_VARIANCE = 0.15f;
	private static final int MAX_CAVE_HEIGHT = 128;
	private static final int CAVE_HEIGHT_WITH_MAX_DENSITY = -512;
	private static final float MAX_CAVE_DENSITY = 1/32.0f;
	private int water;
	private int ice;
	private int gravel;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		water = Blocks.getByID("cubyz:water");
		ice = Blocks.getByID("cubyz:ice");
		gravel = Blocks.getByID("cubyz:gravel");
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "fractal_cave");
	}
	
	@Override
	public int getPriority() {
		return 65536;
	}
	
	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ChunkManager generator) {
		if (chunk.voxelSize > 2) return;
		Random3D rand = new Random3D(seed);
		int cx = wx >> Chunk.chunkShift;
		int cy = wy >> Chunk.chunkShift;
		int cz = wz >> Chunk.chunkShift;
		int size = chunk.getWidth() >> Chunk.chunkShift;
		// Generate caves from all nearby chunks:
		for(int x = cx - range; x < cx + size + range; ++x) {
			for(int y = cy - range; y < cy + size + range; ++y) {
				for(int z = cz - range; z < cz + size + range; ++z) {
					rand.setSeed(x, y, z);
					considerCoordinates(x, y, z, chunk, rand);
				}
			}
		}
	}
	
	private void generateSphere(Random rand, Chunk chunk, double wx, double wy, double wz, double radius) {
		wx -= chunk.wx;
		wy -= chunk.wy;
		wz -= chunk.wz;
		int xMin = chunk.startIndex((int)(wx - radius) - 1);
		int xMax = (int)(wx + radius) + 1;
		int yMin = chunk.startIndex((int)(wy - 0.7*radius)); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
		int yMax = chunk.startIndex((int)(wy + radius) + 1);
		int zMin = chunk.startIndex((int)(wz - radius) - 1);
		int zMax = (int)(wz + radius) + 1;
		xMin = Math.max(xMin, 0);
		xMax = Math.min(xMax, chunk.getWidth());
		yMin = Math.max(yMin, 0);
		yMax = Math.min(yMax, chunk.getWidth() - chunk.voxelSize);
		zMin = Math.max(zMin, 0);
		zMax = Math.min(zMax, chunk.getWidth());
		if(xMin >= xMax || yMin >= yMax || zMin >= zMax) {
			return;
		}
		// Go through all blocks within range of the sphere center and remove them.
		for(int curX = xMin; curX < xMax; curX += chunk.voxelSize) {
			double distToCenterX = (curX - wx)/radius;
			for(int curZ = zMin; curZ < zMax; curZ += chunk.voxelSize) {
				double distToCenterZ = (curZ - wz)/radius;
				if (distToCenterX*distToCenterX + distToCenterZ*distToCenterZ < 1.0) {
					int curY = yMax;
					for(; curY >= yMin; curY -= chunk.voxelSize) {
						double distToCenterY = (curY - wy)/radius;
						double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
						if (distToCenter < 1.0) {
							// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
							if ((distToCenter <= 0.9 || rand.nextInt(6) != 0) && water != chunk.getBlock(curX, curY, curZ) && ice != chunk.getBlock(curX, curY, curZ)) {
								chunk.updateBlockInGeneration(curX, curY, curZ, 0);
							} else if(distToCenterY < 0) {
								// Add the gravel now.
								break;
							}
						} else if(distToCenterY < 0) {
							// Add the gravel now.
							break;
						}
					}
					// Replace part of the floor with gravel:
					if(curY >= 0 && curY != yMax) {
						int block = chunk.getBlock(curX, curY, curZ);
						if(rand.nextFloat() < 0.2f && block != 0 && block != water && block != ice) {
							chunk.updateBlockInGeneration(curX, curY, curZ, gravel);
						}
					}
				}
			}
		}
	}
	
	private void generateCaveBetween(long seed, Chunk chunk, double startwx, double startwy, double startwz, double endwx, double endwy, double endwz, double biasx, double biasy, double biasz, double startRadius, double endRadius, float randomness) {
		// Check if the segment can cross this chunk:
		double maxHeight = Math.max(startRadius, endRadius);
		double distance = Vector3d.distance(startwx, startwy, startwz, endwx, endwy, endwz);
		double maxFractalShift = distance*randomness;
		double safetyInterval = maxHeight + maxFractalShift;
		double xMin = Math.min(startwx, endwx) - safetyInterval;
		double yMin = Math.min(startwy, endwy) - safetyInterval;
		double zMin = Math.min(startwz, endwz) - safetyInterval;
		double xMax = Math.max(startwx, endwx) + safetyInterval;
		double yMax = Math.max(startwy, endwy) + safetyInterval;
		double zMax = Math.max(startwz, endwz) + safetyInterval;
		if(xMin < chunk.wx + chunk.getWidth() && xMax > chunk.wx
		&& yMin < chunk.wy + chunk.getWidth() && yMax > chunk.wy
		&& zMin < chunk.wz + chunk.getWidth() && zMax > chunk.wz) { // Only divide further if the cave may go through ther considered chunk.
			Random rand = new Random(seed);
			// If the lowest level is reached carve out the cave:
			if(distance < chunk.voxelSize) {
				generateSphere(rand, chunk, startwx, startwy, startwz, startRadius);
			} else { // Otherwise go to the next fractal level:
				double midwx = (startwx + endwx)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasx/4;
				double midwy = (startwy + endwy)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasy/4;
				double midwz = (startwz + endwz)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasz/4;
				double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 1)*HEIGHT_VARIANCE;
				midRadius = Math.max(midRadius, MIN_RADIUS);
				generateCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, midwx, midwy, midwz, biasx/4, biasy/4, biasz/4, startRadius, midRadius, randomness);
				generateCaveBetween(rand.nextLong(), chunk, midwx, midwy, midwz, endwx, endwy, endwz, biasx/4, biasy/4, biasz/4, midRadius, endRadius, randomness);
			}
		}
	}
	
	private void generateBranchingCaveBetween(long seed, Chunk chunk, double startwx, double startwy, double startwz, double endwx, double endwy, double endwz, double biasx, double biasy, double biasz, double startRadius, double endRadius, int centerwx, int centerwy, int centerwz, double branchLength, float randomness, boolean isStart, boolean isEnd) {
		double distance = Vector3d.distance(startwx, startwy, startwz, endwx, endwy, endwz);
		Random rand = new Random(seed);
		if(distance < 32) {
			// No more branches below that level to avoid crowded caves.
			generateCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, endwx, endwy, endwz, biasx, biasy, biasz, startRadius, endRadius, randomness);
			// Small chance to branch off:
			if(!isStart && rand.nextFloat() < BRANCH_CHANCE && branchLength > 8) {
				endwx = startwx + branchLength*(2*rand.nextFloat() - 1);
				endwy = startwy + branchLength*(2*rand.nextFloat() - 1);
				endwz = startwz + branchLength*(2*rand.nextFloat() - 1);
				double distanceToSeedPoint = Vector3d.distance(endwx, endwy, endwz, centerwx, centerwy, centerwz);
				// Reduce distance to avoid cutoffs:
				if(distanceToSeedPoint > (range - 1)*Chunk.chunkSize) {
					endwx = centerwx + (endwx - centerwx)/distanceToSeedPoint*((range - 1)*Chunk.chunkSize);
					endwy = centerwy + (endwy - centerwy)/distanceToSeedPoint*((range - 1)*Chunk.chunkSize);
					endwz = centerwz + (endwz - centerwz)/distanceToSeedPoint*((range - 1)*Chunk.chunkSize);
				}
				startRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
				biasx = branchLength*(rand.nextDouble()*2 - 1);
				biasy = branchLength*(rand.nextDouble() - 0.5);
				biasz = branchLength*(rand.nextDouble()*2 - 1);
				generateBranchingCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, endwx, endwy, endwz, biasx, biasy, biasz, startRadius, MIN_RADIUS, centerwx, centerwy, centerwz, branchLength/2, Math.min(0.5f, randomness + randomness*rand.nextFloat()*rand.nextFloat()), true, true);
			}
			return;
		}
		
		double maxFractalShift = distance*randomness;
		double weight = 0.25f + rand.nextFloat()*0.5f; // Do slightly random subdivision instead of binary subdivision, to avoid regular patterns.
		
		double w1 = (1 - weight)*(1 - weight);
		double w2 = weight*weight;
		// Small chance to generate a split:
		if(!isStart && !isEnd && distance < MAX_SPLIT_LENGTH && rand.nextFloat() < SPLITTING_CHANCE) {
			biasx += distance*SPLIT_FACTOR*(rand.nextFloat() - 0.5);
			biasy += distance*SPLIT_FACTOR_Y*(rand.nextFloat() - 0.5);
			biasz += distance*SPLIT_FACTOR*(rand.nextFloat() - 0.5);
			
			double midwx = startwx*weight + endwx*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasx*weight*(1 - weight);
			double midwy = startwy*weight + endwy*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasy*weight*(1 - weight);
			double midwz = startwz*weight + endwz*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasz*weight*(1 - weight);
			double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 1)*HEIGHT_VARIANCE;
			midRadius = Math.max(midRadius, MIN_RADIUS);
			generateBranchingCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, midwx, midwy, midwz, biasx*w1, biasy*w1, biasz*w1, startRadius, midRadius, centerwx, centerwy, centerwz, branchLength, randomness, isStart, false);
			generateBranchingCaveBetween(rand.nextLong(), chunk, midwx, midwy, midwz, endwx, endwy, endwz, biasx*w2, biasy*w2, biasz*w2, midRadius, endRadius, centerwx, centerwy, centerwz, branchLength, randomness, false, isEnd);
			
			// Do some tweaking to the variables before making the second part:
			biasx = -biasx;
			biasy = -biasy;
			biasz = -biasz;
			startRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
			endRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
		}
		// Divide it into smaller segments and slightly randomize them:
		double midwx = startwx*weight + endwx*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasx*weight*(1 - weight);
		double midwy = startwy*weight + endwy*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasy*weight*(1 - weight);
		double midwz = startwz*weight + endwz*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasz*weight*(1 - weight);
		double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 2)*HEIGHT_VARIANCE;
		midRadius = Math.max(midRadius, MIN_RADIUS);
		generateBranchingCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, midwx, midwy, midwz, biasx*w1, biasy*w1, biasz*w1, startRadius, midRadius, centerwx, centerwy, centerwz, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(rand.nextLong(), chunk, midwx, midwy, midwz, endwx, endwy, endwz, biasx*w2, biasy*w2, biasz*w2, midRadius, endRadius, centerwx, centerwy, centerwz, branchLength, randomness, false, isEnd);
	}

	private void considerCoordinates(int x, int y, int z, Chunk chunk, Random3D rand) {
		// Choose some in world coordinates to start generating:
		double startwx = (double)((x << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
		double startwy = (double)((y << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
		double startwz = (double)((z << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
		
		// At y = CAVE_HEIGHT_WITH_MAX_DENSITY blocks the chance is saturated, while at MAX_CAVE_HEIGTH the chance gets 0:
		if(rand.nextFloat() >= MAX_CAVE_DENSITY*Math.min(1, (MAX_CAVE_HEIGHT - startwy)/(MAX_CAVE_HEIGHT - CAVE_HEIGHT_WITH_MAX_DENSITY))) return;
		
		int starters = 1 + rand.nextInt(4);
		for(; starters != 0; starters--) {
			int endX = x + rand.nextInt(2*range - 2) - (range - 1);
			int endY = y + rand.nextInt(2*range - 2) - (range - 1);
			int endZ = z + rand.nextInt(2*range - 2) - (range - 1);
			rand.setSeed(endX, endY, endZ); // Every chunk has the same start/destination position, to increase cave connectivity.
			double endwx = (double)((endX << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
			double endwy = (double)((endY << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
			double endwz = (double)((endZ << Chunk.chunkShift) + rand.nextInt(Chunk.chunkSize));
			double startRadius = rand.nextFloat()*MAX_INITIAL_RADIUS + 2*MIN_RADIUS;
			double endRadius = rand.nextFloat()*MAX_INITIAL_RADIUS + 2*MIN_RADIUS;
			double caveLength = Vector3d.distance(startwx, startwy, startwz, endwx, endwy, endwz);
			generateBranchingCaveBetween(rand.nextLong(), chunk, startwx, startwy, startwz, endwx, endwy, endwz, caveLength*(rand.nextDouble() - 0.5), caveLength*(rand.nextDouble() - 0.5)/2, caveLength*(rand.nextDouble() - 0.5), startRadius, endRadius, x << Chunk.chunkShift, y << Chunk.chunkShift, z << Chunk.chunkShift, BRANCH_LENGTH, 0.1f, true, true);
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0xb898ec9ce9d2ef37L;
	}
}
