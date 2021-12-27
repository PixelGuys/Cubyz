package cubyz.utils;

import java.util.Random;

/**
 * Basically java.util.Random with an additional 3d seed function, that is generated from the initial seed.
 */
public class Random3D extends Random {
	private final int rand1;
	private final int rand2;
	private final int rand3;
	private final long worldSeed;
	
	public Random3D(long worldSeed) {
		super(worldSeed);
		rand1 = nextInt() | 1;
		rand2 = nextInt() | 1;
		rand3 = nextInt() | 1;
		this.worldSeed = worldSeed;
	}
	
	/**
	 * Uses 3d coordiantes as a seed. To make this unique, the seed additionally uses the world seed(from the constructor of this).
	 * @param x
	 * @param y
	 * @param z
	 */
	public void setSeed(int x, int y, int z) {
		int randX = x*rand1;
		int randY = y*rand2;
		int randZ = z*rand3;
		setSeed((randY << 48) ^ (randY >>> 16) ^ (randX << 32) ^ randZ ^ worldSeed);
	}
}
