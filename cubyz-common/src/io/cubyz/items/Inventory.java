package io.cubyz.items;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.base.init.ItemInit;
import io.cubyz.blocks.Block;
import io.cubyz.items.tools.Tool;
import io.cubyz.ndt.NDTContainer;

public class Inventory {
	private ItemStack[] items; // First 8 item stacks are the hotbar
	
	public int addItem(Item i, int amount) {
		if(i == null || amount == 0)
			return 0;
		for(int j = 0; j < items.length; j++) {
			if(!items[j].empty() && items[j].getItem() == i && !items[j].filled()) {
				amount -= items[j].add(amount);
				if(amount == 0) {
					return 0;
				}
			}
		}
		for(int j = 0; j < items.length; j++) {
			if(items[j].empty()) {
				items[j].setItem(i);
				amount -= items[j].add(amount);
				if(amount == 0) {
					return 0;
				}
			}
		}
		// Return the amount of items that didn't fit in the inventory:
		return amount;
	}
	
	public Inventory(int size) {
		items = new ItemStack[size];
		for(int i = 0; i < size; i++) {
			items[i] = new ItemStack();
		}
	}
	
	public Block getBlock(int slot) {
		return items[slot].getBlock();
	}
	
	public Item getItem(int slot) {
		return items[slot].getItem();
	}
	
	public ItemStack getStack(int slot) {
		return items[slot];
	}
	
	public boolean hasStack(int slot) {
		return items[slot] != null;
	}
	
	public int getAmount(int slot) {
		return items[slot].getAmount();
	}
	
	public NDTContainer saveTo(NDTContainer container) {
		container.setInteger("capacity", items.length);
		for (int i = 0; i < items.length; i++) {
			NDTContainer ndt = new NDTContainer();
			ItemStack stack = items[i];
			if (stack.getItem() != null) {
				ndt.setString("item", stack.getItem().getRegistryID().toString());
				ndt.setInteger("amount", stack.getAmount());
				if(stack.getItem() instanceof Tool) {
					Tool tool = (Tool)stack.getItem();
					ndt.setContainer("tool", tool.saveTo(new NDTContainer()));
				}
				container.setContainer(String.valueOf(i), ndt);
			}
		}
		return container;
	}
	
	public void loadFrom(NDTContainer container) {
		items = new ItemStack[container.getInteger("capacity")];
		for (int i = 0; i < items.length; i++) {
			if (container.hasKey(String.valueOf(i))) {
				NDTContainer ndt = container.getContainer(String.valueOf(i));
				Item item = CubyzRegistries.ITEM_REGISTRY.getByID(ndt.getString("item"));
				if (item == null) {
					// Check if it is a tool:
					if(ndt.hasKey("tool")) {
						item = Tool.loadFrom(ndt.getContainer("tool"));
					} else {
						// Search the ItemInit which contains also custom items:
						item = ItemInit.search(ndt.getString("item"));
						if(item == null) {
							// item not existant in this version of the game. Can't do much so ignore it.
							items[i] = new ItemStack();
							continue;
						}
					}
				}
				ItemStack stack = new ItemStack(item);
				stack.add(ndt.getInteger("amount"));
				items[i] = stack;
			} else {
				items[i] = new ItemStack();
			}
		}
	}
	
	public int getCapacity() {
		return items.length;
	}
	
	public void setStack(int slot, ItemStack stack) {
		items[slot] = stack;
	}
}
