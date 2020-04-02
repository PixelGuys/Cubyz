package io.cubyz.items.tools;

import io.cubyz.base.init.MaterialInit;
import io.cubyz.items.Item;

public class CustomMaterial extends Material {
	private int color;
	public CustomMaterial(int heDur, int bDur, int haDur, float dmg, float spd, int color, Item item, int value) {
		super(heDur, bDur, haDur, dmg, spd);
		this.color = color;
		addItem(item, value);
		MaterialInit.registerCustom(this);
	}
	public int getColor() {
		return color;
	}
	public String getName() { // Add color information to the name.
		return "template"+"|"+color+"|";
	}
}
