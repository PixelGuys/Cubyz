package cubyz.world.items;

import cubyz.api.CurrentWorldRegistries;
import cubyz.world.items.tools.Tool;
import pixelguys.json.JsonObject;

/**
 * A storage container for Items.
 */

public class Inventory {
	private ItemStack[] items; // First 8 item stacks are the hotbar
	
	public int addItem(Item i, int amount) {
		if (i == null || amount == 0)
			return 0;
		assert amount >= 0 : "Did you ever see a negative amount of "+i.getName()+"?";
		for(int j = 0; j < items.length; j++) {
			if (!items[j].empty() && items[j].getItem() == i && !items[j].filled()) {
				amount -= items[j].add(amount);
				if (amount == 0) {
					return 0;
				}
			}
		}
		for(int j = 0; j < items.length; j++) {
			if (items[j].empty()) {
				items[j].setItem(i);
				amount -= items[j].add(amount);
				if (amount == 0) {
					return 0;
				}
			}
		}
		// Return the amount of items that didn't fit in the inventory:
		return amount;
	}

	public boolean canCollect(Item type) {
		for(int j = 0; j < items.length; j++) {
			if(items[j].empty()) return true;
			if(items[j].getItem() == type && !items[j].filled()) {
				return true;
			}
		}
		return false;
	}
	
	public Inventory(int size) {
		items = new ItemStack[size];
		for(int i = 0; i < size; i++) {
			items[i] = new ItemStack();
		}
	}
	
	public int getBlock(int slot) {
		return items[slot].getBlock();
	}
	
	public Item getItem(int slot) {
		return items[slot].getItem();
	}
	
	public ItemStack getStack(int slot) {
		return items[slot];
	}
	
	public int getAmount(int slot) {
		return items[slot].getAmount();
	}
	
	public JsonObject save() {
		JsonObject json = new JsonObject();
		json.put("capacity", items.length);
		for (int i = 0; i < items.length; i++) {
			JsonObject stackJson = items[i].store();
			if(!stackJson.map.isEmpty()) {
				json.put(String.valueOf(i), stackJson);
			}
		}
		return json;
	}
	
	public void loadFrom(JsonObject json, CurrentWorldRegistries registries) {
		ItemStack[] newItems = new ItemStack[json.getInt("capacity", 0)];
		for(int i = 0; i < newItems.length; i++) {
			JsonObject stackJson = json.getObject(String.valueOf(i));
			if (stackJson != null) {
				Item item = Item.load(stackJson, registries);
				if (item == null) {
					newItems[i] = new ItemStack();
					continue;
				}
				ItemStack stack = new ItemStack(item);
				stack.add(stackJson.getInt("amount", 1));
				newItems[i] = stack;
			} else {
				newItems[i] = new ItemStack();
			}
		}
		items = newItems;
	}
	
	public int getCapacity() {
		return items.length;
	}
}
