package cubyz.world.items;

import cubyz.utils.translate.TextKey;
import cubyz.world.blocks.CustomBlock;

/**
 * Used for randomly generated items.
 */

public class CustomItem extends Item {
	private static final int GEM = 0, METAL = 1, CRYSTAL = 2;// More to come.
	private int color;
	int type;
	public int getColor() {
		return color;
	}
	
	public boolean isGem() {
		return type == GEM;
	}
	
	public boolean isCrystal() {
		return type == CRYSTAL;
	}
	
	public static CustomItem fromOre(CustomBlock block) {
		CustomItem item = new CustomItem();
		item.color = block.color;
		if(block.getName().endsWith("um")) {
			item.type = METAL;
		} else if(block.getName().endsWith("ite")) {
				item.type = CRYSTAL;
		} else {
			item.type = GEM;
		}
		item.setID(block.getRegistryID());
		item.setName(TextKey.createTextKey(block.getName()));
		return item;
	}
}
