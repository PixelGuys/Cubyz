package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.items.Item;

public class ItemInit {

	public static final ArrayList<Item> ITEMS = new ArrayList<>();
	public static Item stick;
	
	static {
		stick = new Item();
		stick.setID("cubyz:stick");
		stick.setTexture("materials/stick.png");
	}
	
	public static void register(Item item) {
		ITEMS.add(item);
	}
	
	public static void registerAll(Registry<Item> reg) {
		
		reg.registerAll(ITEMS);
	}
	
}
