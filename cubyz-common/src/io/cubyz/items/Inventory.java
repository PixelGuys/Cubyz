package io.cubyz.items;

import io.cubyz.blocks.Block;

public class Inventory {
	private ItemStack[] items = new ItemStack[32]; // First 8 item stacks are the hotbar
	
	public void addItem(Item i, int amount) {
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
	
	public void addBlock(Block b, int amount) {
		for(int j = 0; j < items.length; j++) {
			if(items[j] != null && items[j].getBlock() == b && !items[j].filled()) {
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
				items[j] = new ItemStack(b);
				amount -= items[j].add(amount);
				if(amount == 0) {
					return;
				}
			}
		}
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
}
