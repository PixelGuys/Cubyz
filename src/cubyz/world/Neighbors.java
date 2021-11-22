package cubyz.world;

/**
 * Contains a bunch of constants used to describe neighboring blocks.
 * Every piece of code in Cubyz should use this!
 */

public class Neighbors {
	/** How many neighbors there are. */
	public static final int NEIGHBORS = 6;
	/** Directions → Index */
	public static final int	DIR_UP = 0,
	                        DIR_DOWN = 1,
	                        DIR_POS_X = 2,
	                        DIR_NEG_X = 3,
	                        DIR_POS_Z = 4,
	                        DIR_NEG_Z = 5;
	/** Index to relative position */
	public static final int[] REL_X = new int[] {0, 0, 1, -1, 0, 0},
	                          REL_Y = new int[] {1, -1, 0, 0, 0, 0},
	                          REL_Z = new int[] {0, 0, 0, 0, 1, -1};
	/** Index to bitMask for bitmap direction data */
	public static final byte[] BIT_MASK = new byte[] {0x01, 0x02, 0x04, 0x08, 0x10, 0x20};
}
