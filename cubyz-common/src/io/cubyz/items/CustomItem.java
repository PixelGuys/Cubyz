package io.cubyz.items;

import io.cubyz.blocks.CustomOre;

public class CustomItem extends Item {
	private static int GEM = 0, METAL = 1;// More to come.
	private int color;
	int type;
	public int getColor() {
		return color;
	}
	
	public boolean isGem() {
		return type == GEM;
	}
	
	public static CustomItem fromOre(CustomOre ore) {
		CustomItem item = new CustomItem();
		item.color = ore.getColor();
		if(ore.getName().endsWith("um")) {
			item.type = METAL;
		} else {
			item.type = GEM;
		}
		item.setID(ore.getRegistryID());
		return item;
	}
}
