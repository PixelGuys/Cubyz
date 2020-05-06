package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.items.CustomItem;
import io.cubyz.items.Item;

public class ItemInit {

	public static final ArrayList<Item> ITEMS = new ArrayList<>();
	public static final ArrayList<CustomItem> CUSTOM_ITEMS = new ArrayList<>();
	
	public static void register(Item item) {
		ITEMS.add(item);
	}
	
	public static void registerAll(Registry<Item> reg) {
		
		reg.registerAll(ITEMS);
	}
	
	public static void registerCustom(CustomItem item) {
		register(item);
		CUSTOM_ITEMS.add(item); // Keep track of the custom items to prevent spamming the whole list with custom items upon rejoin.
	}
	
	public static void resetCustom() {
		for(Item item : CUSTOM_ITEMS) {
			ITEMS.remove(item);
		}
		CUSTOM_ITEMS.clear();
	}
	
}
