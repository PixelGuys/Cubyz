package io.cubyz.items;

import io.cubyz.blocks.CustomOre;
import io.cubyz.translate.TextKey;

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
	
	public static CustomItem fromOre(CustomOre ore) {
		CustomItem item = new CustomItem();
		item.color = ore.getColor();
		if(ore.getName().endsWith("um")) {
			item.type = METAL;
		} else if(ore.getName().endsWith("ite")) {
				item.type = CRYSTAL;
		} else {
			item.type = GEM;
		}
		item.setID(ore.getRegistryID());
		item.setName(new TextKey(ore.getName()));
		return item;
	}
}
