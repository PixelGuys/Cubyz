package io.cubyz.items.tools;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.items.Item;

/**
 * Tool material for a randomly generated ore.
 */

public class CustomMaterial extends Material {
	private int color;
	public CustomMaterial(int heDur, int bDur, int haDur, float dmg, float spd, int color, Item item, int value, CurrentSurfaceRegistries registries) {
		super(heDur, bDur, haDur, dmg, spd);
		this.color = color;
		addItem(item, value);
		setID(item.getRegistryID());
		registries.materialRegistry.register(this);
	}
	public int getColor() {
		return color;
	}
	public String getName() { // Add color information to the name.
		return "template"+"|"+color+"|";
	}
}
