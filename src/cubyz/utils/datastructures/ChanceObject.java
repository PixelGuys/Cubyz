package cubyz.utils.datastructures;

/**
 * An object that has a relative chance of being drawn from a list.
 * An example of this are biomes. There are more and less rare biomes, but the rarity isn't global, but always relative to that of all other biomes, because only one can be chosen.
 */

public abstract class ChanceObject {
	/** The chance is stored as an integer to avoid calculation errors on addition/subtraction. */
	public final int chance;
	/**
	 * Scales the float and converts the chance to an integer. This should be irrelevant because you normally only want relative chance anyways, but low values like 10⁻⁴ or lower will be interpreted as 0.
	 * @param chance ≥ 0
	 */
	public ChanceObject(float chance) {
		if (chance < 0) throw new IllegalArgumentException("chance must be bigger than or equal to 0!");
		int intChance = (int)(chance*10000);
		if (intChance < 0) intChance = Integer.MAX_VALUE;
		this.chance = intChance;
	}
	/**
	 * The relative chance. Since this chance only depends on the values of other objects, it's value alone has no meaning.
	 * @param chance ≥ 0
	 */
	public ChanceObject(int chance) {
		if (chance < 0) throw new IllegalArgumentException("chance must be bigger than or equal to 0!");
		this.chance = chance;
	}
}
