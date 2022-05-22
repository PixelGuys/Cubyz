package cubyz.utils;

/**
 * A bunch of random functions that don't require an object and are faster than java.util.Random due to not promising thread safety.
 * The random algorithm is taken from java.util.Random.
 */
public class FastRandom {

	private static final long multiplier = 0x5DEECE66DL;
	private static final long addend = 0xBL;
	private static final long mask = (1L << 48) - 1;

	private static final double DOUBLE_UNIT = 0x1.0p-53; // 1.0 / (1L << 53)

	private long seed;

	public FastRandom(long seed) {
		this.seed = seed;
		initialScramble();
	}

	public void setSeed(long seed) {
		this.seed = seed;
		initialScramble();
	}

	private static long initialScramble(long seed) {
		return (seed ^ multiplier) & mask;
	}
	private void initialScramble() {
		seed = (seed ^ multiplier) & mask;
	}

	private static int next(long seed, int bits) {
		seed = initialScramble(seed);
		seed = (seed*multiplier + addend) & mask;
		return (int)(seed >>> (48 - bits));
	}
	private static int next(long[] seed, int bits) {
		seed[0] = (seed[0]*multiplier + addend) & mask;
		return (int)(seed[0] >>> (48 - bits));
	}
	private int next(int bits) {
		seed = (seed*multiplier + addend) & mask;
		return (int)(seed >>> (48 - bits));
	}

	public static int nextInt(long seed) {
		return next(seed, 32);
	}
	public int nextInt() {
		return next(32);
	}

	public static int nextInt(long seed, int bound) {
		assert bound > 0 : "Illegal bound.";
		int r = next(seed, 31);
		int m = bound - 1;
		if ((bound & m) == 0)  // i.e., bound is a power of 2
			r = (int)((bound * (long)r) >> 31);
		else { // reject over-represented candidates
			for (int u = r;
				 u - (r = u % bound) + m < 0;
				 u = next(seed, 31))
				;
		}
		return r;
	}
	public int nextInt(int bound) {
		assert bound > 0 : "Illegal bound.";
		int r = next(31);
		int m = bound - 1;
		if ((bound & m) == 0)  // i.e., bound is a power of 2
			r = (int)((bound * (long)r) >> 31);
		else { // reject over-represented candidates
			for (int u = r;
				 u - (r = u % bound) + m < 0;
				 u = next(31))
				;
		}
		return r;
	}

	public static long nextLong(long seed) {
		long[] _seed = new long[] {initialScramble(seed)};
		return ((long)(next(_seed, 32)) << 32) + next(_seed, 32);
	}

	public long nextLong() {
		// it's okay that the bottom word remains signed.
		return ((long)(next(32)) << 32) + next(32);
	}

	public static boolean nextBoolean(long seed) {
		return next(seed, 1) != 0;
	}
	public boolean nextBoolean() {
		return next(1) != 0;
	}

	public static float nextFloat(long seed) {
		return next(seed, 24)/((float)(1 << 24));
	}
	public float nextFloat() {
		return next(24)/((float)(1 << 24));
	}

	public static double nextDouble(long seed) {
		long[] _seed = new long[] {initialScramble(seed)};
		return (((long)(next(_seed, 26)) << 27) + next(_seed, 27)) * DOUBLE_UNIT;
	}
	public double nextDouble() {
		return (((long)(next(26)) << 27) + next(27)) * DOUBLE_UNIT;
	}
}