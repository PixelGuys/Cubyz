package cubyz.world.items;

import cubyz.utils.translate.TextKey;
import cubyz.world.blocks.Blocks;

/**
 * Item that corresponds to a block and places that block on use.
 */

public class ItemBlock extends Item {

	private int block;
	
	public ItemBlock() {
		
	}
	
	public ItemBlock(int block) {
		setBlock(block);
	}
	
	public int getBlock() {
		return block;
	}
	
	public void setBlock(int block) {
		this.block = block;
		setID(Blocks.id(block));
		this.setName(TextKey.createTextKey("block." + Blocks.id(block).getMod() + "." + Blocks.id(block).getID() + ".name"));
	}
	
}
