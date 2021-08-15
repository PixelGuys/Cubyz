package cubyz.world.items;

/**
 * Used for chance based block drops.
 */

public class BlockDrop {
	public final Item item;
	public final float amount;
	public BlockDrop(Item item, float amount) {
		this.item = item;
		this.amount = amount;
	}
}
