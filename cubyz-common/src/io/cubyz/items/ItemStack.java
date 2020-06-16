package io.cubyz.items;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.ndt.NDTContainer;

public class ItemStack {

	private Item item;
	int number = 0;
	
	public ItemStack() {
		item = null;
	}
	
	public ItemStack(Item item) {
		this.item = item;
	}
	
	public ItemStack(Item item, int amount) {
		this.item = item;
		number = amount;
	}
	
	public void update() {}
	
	public boolean filled() {
		return number >= item.stackSize;
	}
	
	public boolean empty() {
		return number <= 0;
	}
	
	public int add(int number) {
		this.number += number;
		if(this.number < 0) {
			number = number-this.number;
			this.number = 0;
		}
		else if(this.number > item.stackSize) {
			number = number-this.number+item.stackSize;
			this.number = item.stackSize;
		}
		if(empty()) {
			clear();
		}
		return number;
	}
	
	public void setItem(Item i) {
		item = i;
	}
	
	public Item getItem() {
		return item;
	}
	
	public Block getBlock() {
		if(item == null)
			return null;
		if (item instanceof ItemBlock)
			return ((ItemBlock) item).getBlock();
		else
			return null;
	}
	
	public int getAmount() {
		return number;
	}
	
	public void setAmount(int a) { // For use in special cases only!
		number = a;
	}
	
	public void loadFrom(NDTContainer container, CurrentSurfaceRegistries registries) {
		item = registries.itemRegistry.getByID(container.getString("id"));
		if (container.hasKey("size"))
			number = container.getInteger("size");
		else
			number = 1;
	}
	
	public void saveTo(NDTContainer container) {
		container.setString("id", item.getRegistryID().toString());
		container.setInteger("size", number);
	}
	
	public void clear() {
		item = null;
		number = 0;
	}
	
}