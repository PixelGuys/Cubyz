package cubyz.world.terrain.noise;

import java.util.Arrays;
import java.util.Random;

/**
 * Blue noise (aka Poisson Disk Sampling) is a pattern that ensures that all points have a minimum distance towards their neigbors.
 * This contains a static blue noise pattern that is calculated once and then used everywhere around the world. because it is so big the player will never notice issues.
 */
public final class StaticBlueNoise {
	private static final int SIZE_SHIFT = 10;
	private static final int SIZE = 1 << SIZE_SHIFT;
	private static final int SIZE_MASK = SIZE - 1;
	private static final int FEATURE_SHIFT = 2;
	private static final int FEATURE_SIZE = 1 << FEATURE_SHIFT;
	private static final int FEATURE_MASK = FEATURE_SIZE - 1;

	/** Uses a simple square grid as a base. */
	private static final byte[] pattern = new byte[SIZE * SIZE];

	/**
	 * Loads a pre-seeded noise map that is used for world generation.
	 */
	public static void load() {
		Random rand = new Random(54095248685739L);
		final int DIST_SQUARE_LIMIT = 8;
		final int REPETITIONS = 4;
		final int ITERATIONS = 16;
		// Go through all points and try to move them randomly.
		// Ensures that the grid is valid in each step.
		// This is repeated multiple times for optimal results.
		// In the last repetition is enforced, to remove grid artifacts.
		for(int rep = 0; rep < REPETITIONS; rep++) {
			for(int i = 0; i < pattern.length; i++) {
				int y = i & SIZE_MASK;
				int x = i >> SIZE_SHIFT & SIZE_MASK;
				outer:
				for(int it = 0; it < ITERATIONS || rep == REPETITIONS - 1; it++) { // Try to select a random point until it fits.
					byte point = (byte) (rand.nextInt() & 63);
					int xOffset = point >>> 3 & 7;
					int yOffset = point & 7;
					// Go through all neighbors and check validity:
					for(int dx = -2; dx <= 2; dx++) {
						for(int dy = -2; dy <= 2; dy++) {
							if (dx == 0 && dy == 0) continue; // Don't compare with itself!
							int neighbor = (x + dx & SIZE_MASK) << SIZE_SHIFT | (y + dy & SIZE_MASK);
							byte neighborPos = pattern[neighbor];
							int nx = (neighborPos >>> 3) + (dx << FEATURE_SHIFT);
							int ny = (neighborPos & 7) + (dy << FEATURE_SHIFT);
							int distSqr = (nx - xOffset) * (nx - xOffset) + (ny - yOffset) * (ny - yOffset);
							if (distSqr < DIST_SQUARE_LIMIT) {
								continue outer;
							}
						}
					}

					pattern[i] = point;
					break;
				}
			}
		}
	}

	private static final byte sample(int x, int y) {
		return pattern[x << SIZE_SHIFT | y];
	}
	/**
	 * Takes a subregion of the grid. Corrdinates are returned relative to x and y compressed into 16 bits each.
	 * @param x
	 * @param y
	 * @param width < 2¹⁶ - 8
	 * @param height < 2¹⁶ - 8
	 * @return (x << 16 | y)
	 */
	public static final int[] getRegionData(int x, int y, int width, int height) {
		int xMin = ((x & ~FEATURE_MASK) - FEATURE_SIZE) >> FEATURE_SHIFT;
		int yMin = ((y & ~FEATURE_MASK) - FEATURE_SIZE) >> FEATURE_SHIFT;
		int xMax = (x + width & ~FEATURE_MASK) >> FEATURE_SHIFT;
		int yMax = (y + height & ~FEATURE_MASK) >> FEATURE_SHIFT;
		int[] result = new int[(xMax - xMin + 1) * (yMax - yMin + 1)];
		int index = 0;
		for(int xMap = xMin; xMap <= xMax; xMap++) {
			for(int yMap = yMin; yMap <= yMax; yMap++) {
				byte val = sample(xMap & SIZE_MASK, yMap & SIZE_MASK);
				int xRes = (xMap - xMin) << FEATURE_SHIFT;
				xRes += val >>> 3;
				int yRes = (yMap - yMin) << FEATURE_SHIFT;
				yRes += val & 7;
				if (xRes >= 0 && xRes < width && yRes >= 0 && yRes < height)
					result[index++] = xRes << 16 | yRes;
			}
		}
		return Arrays.copyOf(result, index);
	}
}
