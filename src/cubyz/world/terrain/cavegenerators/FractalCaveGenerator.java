package cubyz.world.terrain.cavegenerators;

import cubyz.utils.FastRandom;
import org.joml.Vector3d;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.Random3D;
import cubyz.world.terrain.CaveMapFragment;
import pixelguys.json.JsonObject;

/**
 * Generates cave system using a fractal algorithm.
 */

public class FractalCaveGenerator implements CaveGenerator {
	private static final int CHUNK_SHIFT = 5;
	private static final int CHUNK_SIZE = 1 << CHUNK_SHIFT;
	private static final int RANGE = 8;
	private static final int BRANCH_LENGTH = 64;
	private static final float SPLITTING_CHANCE = 0.4f;
	private static final float SPLIT_FACTOR = 1.0f;
	private static final float Y_SPLIT_REDUCTION = 0.5f; // To reduce splitting in y-direction.
	private static final float MAX_SPLIT_LENGTH = 128;
	private static final float BRANCH_CHANCE = 0.4f;
	private static final float MIN_RADIUS = 2.0f;
	private static final float MAX_INITIAL_RADIUS = 5;
	private static final float HEIGHT_VARIANCE = 0.15f;
	private static final int MAX_CAVE_HEIGHT = 128;
	private static final int CAVE_HEIGHT_WITH_MAX_DENSITY = -512;
	private static final float MAX_CAVE_DENSITY = 1/32.0f;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
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
	public void generate(long seed, CaveMapFragment map) {
		if (map.voxelSize > 2) return;
		Random3D rand = new Random3D(seed);
		int cx = map.wx >> CHUNK_SHIFT;
		int cy = map.wy >> CHUNK_SHIFT;
		int cz = map.wz >> CHUNK_SHIFT;
		// Generate caves from all nearby chunks:
		for(int x = cx - RANGE; x < cx + CaveMapFragment.WIDTH*map.voxelSize/CHUNK_SIZE + RANGE; ++x) {
			for(int y = cy - RANGE; y < cy + CaveMapFragment.HEIGHT*map.voxelSize/CHUNK_SIZE + RANGE; ++y) {
				for(int z = cz - RANGE; z < cz + CaveMapFragment.WIDTH*map.voxelSize/CHUNK_SIZE + RANGE; ++z) {
					rand.setSeed(x, y, z);
					considerCoordinates(x, y, z, map, rand);
				}
			}
		}
	}
	
	private void generateSphere(FastRandom rand, CaveMapFragment map, double wx, double wy, double wz, double radius) {
		wx -= map.wx;
		wy -= map.wy;
		wz -= map.wz;
		int xMin = (int)(wx - radius) - 1;
		int xMax = (int)(wx + radius) + 1;
		int zMin =(int)(wz - radius) - 1;
		int zMax = (int)(wz + radius) + 1;
		xMin = Math.max(xMin, 0);
		xMax = Math.min(xMax, CaveMapFragment.WIDTH*map.voxelSize);
		zMin = Math.max(zMin, 0);
		zMax = Math.min(zMax, CaveMapFragment.WIDTH*map.voxelSize);
		if(xMin >= xMax || wy - radius + 1 >= CaveMapFragment.HEIGHT*map.voxelSize || wy + radius + 1 < 0 || zMin >= zMax) {
			return;
		}
		// Go through all blocks within range of the sphere center and remove them.
		for(int curX = xMin; curX < xMax; curX += map.voxelSize) {
			double distToCenterX = (curX - wx)/radius;
			for(int curZ = zMin; curZ < zMax; curZ += map.voxelSize) {
				double distToCenterZ = (curZ - wz)/radius;
				double yDistance = radius*Math.sqrt(0.9*0.9 - distToCenterX*distToCenterX - distToCenterZ*distToCenterZ);
				int yMin = (int)(wy - yDistance);
				int yMax = (int)(wy + yDistance);
				map.removeRange(curX, curZ, yMin, yMax); // Remove the center range in a single call.
				// Add some roughness at the upper cave walls:
				for(int curY = yMax; curY <= CaveMapFragment.HEIGHT*map.voxelSize; curY += map.voxelSize) {
					double distToCenterY = (curY - wy)/radius;
					double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
					if (distToCenter < 1) {
						// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
						if (rand.nextInt(6) != 0) {
							map.removeRange(curX, curZ, curY, curY+1);
						}
					} else {
						break;
					}
				}
				// Add some roughness at the upper cave walls:
				for(int curY = yMin; curY >= 0; curY -= map.voxelSize) {
					double distToCenterY = (curY - wy)/radius;
					double distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
					if (distToCenter < 1) {
						// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
						if (rand.nextInt(6) == 0) {
							map.removeRange(curX, curZ, curY, curY+1);
						}
					} else {
						break;
					}
				}
			}
		}
	}
	
	private void generateCaveBetween(long seed, CaveMapFragment map, double startwx, double startwy, double startwz, double endwx, double endwy, double endwz, double biasx, double biasy, double biasz, double startRadius, double endRadius, float randomness) {
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
		if(xMin < map.wx + CaveMapFragment.WIDTH*map.voxelSize && xMax > map.wx
		&& yMin < map.wy + CaveMapFragment.HEIGHT*map.voxelSize && yMax > map.wy
		&& zMin < map.wz + CaveMapFragment.WIDTH*map.voxelSize && zMax > map.wz) { // Only divide further if the cave may go through ther considered chunk.
			FastRandom rand = new FastRandom(seed);
			// If the lowest level is reached carve out the cave:
			if(distance < map.voxelSize) {
				generateSphere(rand, map, startwx, startwy, startwz, startRadius);
			} else { // Otherwise go to the next fractal level:
				double midwx = (startwx + endwx)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasx/4;
				double midwy = (startwy + endwy)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasy/4;
				double midwz = (startwz + endwz)/2 + maxFractalShift*((2*rand.nextFloat() - 1)) + biasz/4;
				double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 1)*HEIGHT_VARIANCE;
				midRadius = Math.max(midRadius, MIN_RADIUS);
				generateCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, midwx, midwy, midwz, biasx/4, biasy/4, biasz/4, startRadius, midRadius, randomness);
				generateCaveBetween(rand.nextLong(), map, midwx, midwy, midwz, endwx, endwy, endwz, biasx/4, biasy/4, biasz/4, midRadius, endRadius, randomness);
			}
		}
	}
	
	private void generateBranchingCaveBetween(long seed, CaveMapFragment map, double startwx, double startwy, double startwz, double endwx, double endwy, double endwz, double biasX, double biasY, double biasZ, double startRadius, double endRadius, int centerwx, int centerwy, int centerwz, double branchLength, float randomness, boolean isStart, boolean isEnd) {
		double distance = Vector3d.distance(startwx, startwy, startwz, endwx, endwy, endwz);
		FastRandom rand = new FastRandom(seed);
		if(distance < 32) {
			// No more branches below that level to avoid crowded caves.
			generateCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, endwx, endwy, endwz, biasX, biasY, biasZ, startRadius, endRadius, randomness);
			// Small chance to branch off:
			if(!isStart && rand.nextFloat() < BRANCH_CHANCE && branchLength > 8) {
				endwx = startwx + branchLength*(2*rand.nextFloat() - 1);
				endwy = startwy + branchLength*(2*rand.nextFloat() - 1);
				endwz = startwz + branchLength*(2*rand.nextFloat() - 1);
				double distanceToSeedPoint = Vector3d.distance(endwx, endwy, endwz, centerwx, centerwy, centerwz);
				// Reduce distance to avoid cutoffs:
				if(distanceToSeedPoint > (RANGE - 1)*CHUNK_SIZE) {
					endwx = centerwx + (endwx - centerwx)/distanceToSeedPoint*((RANGE - 1)*CHUNK_SIZE);
					endwy = centerwy + (endwy - centerwy)/distanceToSeedPoint*((RANGE - 1)*CHUNK_SIZE);
					endwz = centerwz + (endwz - centerwz)/distanceToSeedPoint*((RANGE - 1)*CHUNK_SIZE);
				}
				startRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
				biasX = branchLength*(rand.nextDouble()*2 - 1);
				biasY = branchLength*(rand.nextDouble() - 0.5);
				biasZ = branchLength*(rand.nextDouble()*2 - 1);
				generateBranchingCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, endwx, endwy, endwz, biasX, biasY, biasZ, startRadius, MIN_RADIUS, centerwx, centerwy, centerwz, branchLength/2, Math.min(0.5f, randomness + randomness*rand.nextFloat()*rand.nextFloat()), true, true);
			}
			return;
		}
		
		double maxFractalShift = distance*randomness;
		double weight = 0.25f + rand.nextFloat()*0.5f; // Do slightly random subdivision instead of binary subdivision, to avoid regular patterns.
		
		double w1 = (1 - weight)*(1 - weight);
		double w2 = weight*weight;
		// Small chance to generate a split:
		if(!isStart && !isEnd && distance < MAX_SPLIT_LENGTH && rand.nextFloat() < SPLITTING_CHANCE) {
			// Find a random direction perpendicular to the current cave direction:
			double splitX = rand.nextFloat() - 0.5f;
			double splitY = Y_SPLIT_REDUCTION*(rand.nextFloat() - 0.5f);
			// Normalize
			double splitLength = (float)Math.sqrt(splitX*splitX + splitY*splitY);
			splitX /= splitLength;
			splitY /= splitLength;
			// Calculate bias offsets:
			double biasLength = Math.sqrt(biasX*biasX + biasY*biasY + biasZ*biasZ);
			double offsetY = splitY*SPLIT_FACTOR*distance;
			double offsetX = splitX*SPLIT_FACTOR*distance * biasZ/biasLength;
			double offsetZ = -splitX*SPLIT_FACTOR*distance * biasX/biasLength;

			biasX += offsetX;
			biasY += offsetY;
			biasZ += offsetZ;
			
			double midwx = startwx*weight + endwx*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasX*weight*(1 - weight);
			double midwy = startwy*weight + endwy*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasY*weight*(1 - weight);
			double midwz = startwz*weight + endwz*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasZ*weight*(1 - weight);
			double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 1)*HEIGHT_VARIANCE;
			midRadius = Math.max(midRadius, MIN_RADIUS);
			generateBranchingCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, midwx, midwy, midwz, biasX*w1, biasY*w1, biasZ*w1, startRadius, midRadius, centerwx, centerwy, centerwz, branchLength, randomness, isStart, false);
			generateBranchingCaveBetween(rand.nextLong(), map, midwx, midwy, midwz, endwx, endwy, endwz, biasX*w2, biasY*w2, biasZ*w2, midRadius, endRadius, centerwx, centerwy, centerwz, branchLength, randomness, false, isEnd);
			
			// Do some tweaking to the variables before making the second part:
			biasX -= 2*offsetX;
			biasY -= 2*offsetY;
			biasZ -= 2*offsetZ;
			startRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
			endRadius = (startRadius - MIN_RADIUS)*rand.nextFloat() + MIN_RADIUS;
		}
		// Divide it into smaller segments and slightly randomize them:
		double midwx = startwx*weight + endwx*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasX*weight*(1 - weight);
		double midwy = startwy*weight + endwy*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasY*weight*(1 - weight);
		double midwz = startwz*weight + endwz*(1 - weight) + maxFractalShift*(2*rand.nextFloat() - 1) + biasZ*weight*(1 - weight);
		double midRadius = (startRadius + endRadius)/2 + maxFractalShift*(2*rand.nextFloat() - 2)*HEIGHT_VARIANCE;
		midRadius = Math.max(midRadius, MIN_RADIUS);
		generateBranchingCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, midwx, midwy, midwz, biasX*w1, biasY*w1, biasZ*w1, startRadius, midRadius, centerwx, centerwy, centerwz, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(rand.nextLong(), map, midwx, midwy, midwz, endwx, endwy, endwz, biasX*w2, biasY*w2, biasZ*w2, midRadius, endRadius, centerwx, centerwy, centerwz, branchLength, randomness, false, isEnd);
	}

	private void considerCoordinates(int x, int y, int z, CaveMapFragment map, Random3D rand) {
		// Choose some in world coordinates to start generating:
		double startwx = (x << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
		double startwy = (y << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
		double startwz = (z << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
		
		// At y = CAVE_HEIGHT_WITH_MAX_DENSITY blocks the chance is saturated, while at MAX_CAVE_HEIGTH the chance gets 0:
		if(rand.nextFloat() >= MAX_CAVE_DENSITY*Math.min(1, (MAX_CAVE_HEIGHT - startwy)/(MAX_CAVE_HEIGHT - CAVE_HEIGHT_WITH_MAX_DENSITY))) return;
		
		int starters = 1 + rand.nextInt(4);
		for(; starters != 0; starters--) {
			int endX = x + rand.nextInt(2*RANGE - 2) - (RANGE - 1);
			int endY = y + rand.nextInt(2*RANGE - 2) - (RANGE - 1);
			int endZ = z + rand.nextInt(2*RANGE - 2) - (RANGE - 1);
			rand.setSeed(endX, endY, endZ); // Every chunk has the same start/destination position, to increase cave connectivity.
			double endwx = (endX << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
			double endwy = (endY << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
			double endwz = (endZ << CHUNK_SHIFT) + rand.nextInt(CHUNK_SIZE);
			double startRadius = rand.nextFloat()*MAX_INITIAL_RADIUS + 2*MIN_RADIUS;
			double endRadius = rand.nextFloat()*MAX_INITIAL_RADIUS + 2*MIN_RADIUS;
			double caveLength = Vector3d.distance(startwx, startwy, startwz, endwx, endwy, endwz);
			generateBranchingCaveBetween(rand.nextLong(), map, startwx, startwy, startwz, endwx, endwy, endwz, caveLength*(rand.nextDouble() - 0.5), caveLength*(rand.nextDouble() - 0.5)/2, caveLength*(rand.nextDouble() - 0.5), startRadius, endRadius, x << CHUNK_SHIFT, y << CHUNK_SHIFT, z << CHUNK_SHIFT, BRANCH_LENGTH, 0.1f, true, true);
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0xb898ec9ce9d2ef37L;
	}
}
