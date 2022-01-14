package cubyz.world.items;

import cubyz.utils.json.JsonObject;
import cubyz.utils.translate.TextKey;
import cubyz.world.blocks.Blocks;

/**
 * Item that corresponds to a block and places that block on use.
 */

public class ItemBlock extends Item {

	private final int block;
	
	public ItemBlock(int block, JsonObject json) {
		super(Blocks.id(block), json);
		this.block = block;
		this.setName(TextKey.createTextKey("block." + Blocks.id(block).getMod() + "." + Blocks.id(block).getID() + ".name"));
	}
	
	public int getBlock() {
		return block;
	}
	
}
