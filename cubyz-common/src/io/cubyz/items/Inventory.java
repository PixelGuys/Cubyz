package io.cubyz.items;

import io.cubyz.blocks.Block;
import io.cubyz.ndt.NDTContainer;

public class Inventory {
	private ItemStack[] items; // First 8 item stacks are the hotbar
	
	public void addItem(Item i, int amount) {
		if(i == null || amount == 0)
			return;
		for(int j = 0; j < items.length; j++) {
			if(items[j] != null && items[j].getItem() == i && !items[j].filled()) {
				amount -= items[j].add(amount);
				if(items[j].empty()) {
					items[j] = null;
				}
				if(amount == 0) {
					return;
				}
			}
		}
		for(int j = 0; j < items.length; j++) {
			if(items[j] == null) {
				items[j] = new ItemStack(i);
				amount -= items[j].add(amount);
				if(amount == 0) {
					return;
				}
			}
		}
		// TODO: Consider a full inventory
	}
	
	public Inventory(int size) {
		items = new ItemStack[size];
	}
	
	public Inventory() {
		this(0);
	}
	
	public Block getBlock(int selection) {
		if(items[selection] == null)
			return null;
		return items[selection].getBlock();
	}
	
	public Item getItem(int selection) {
		if(items[selection] == null)
			return null;
		return items[selection].getItem();
	}
	
	public int getAmount(int selection) {
		if(items[selection] == null)
			return 0;
		return items[selection].number;
	}
	
	public void saveTo(NDTContainer container) {
		container.setInteger("capacity", items.length);
		for (int i = 0; i < items.length; i++) {
			
		}
	}
	
	public void loadFrom(NDTContainer container) {
		items = new ItemStack[container.getInteger("capacity")];
		for (int i = 0; i < items.length; i++) {
			
		}
	}
}
