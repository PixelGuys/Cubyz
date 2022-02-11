package cubyz.world.items;

import cubyz.api.CurrentWorldRegistries;
import cubyz.utils.json.JsonObject;
import cubyz.world.items.tools.Tool;

/**
 * A storage container for Items.
 */

public class Inventory {
	private ItemStack[] items; // First 8 item stacks are the hotbar
	
	public int addItem(Item i, int amount) {
		if (i == null || amount == 0)
			return 0;
		assert(amount >= 0) : "Did you ever see a negative amount of "+i.getName()+"?";
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
	
	public boolean hasStack(int slot) {
		return items[slot] != null;
	}
	
	public int getAmount(int slot) {
		return items[slot].getAmount();
	}
	
	public JsonObject save() {
		JsonObject json = new JsonObject();
		json.put("capacity", items.length);
		for (int i = 0; i < items.length; i++) {
			JsonObject stackJson = new JsonObject();
			ItemStack stack = items[i];
			if (stack.getItem() != null) {
				stackJson.put("item", stack.getItem().getRegistryID().toString());
				stackJson.put("amount", stack.getAmount());
				if (stack.getItem() instanceof Tool) {
					Tool tool = (Tool)stack.getItem();
					stackJson.put("tool", tool.save());
				}
				json.put(String.valueOf(i), stackJson);
			}
		}
		return json;
	}
	
	public void loadFrom(JsonObject json, CurrentWorldRegistries registries) {
		items = new ItemStack[json.getInt("capacity", 0)];
		for(int i = 0; i < items.length; i++) {
			JsonObject stackJson = json.getObject(String.valueOf(i));
			if (stackJson != null) {
				Item item = registries.itemRegistry.getByID(stackJson.getString("item", "null"));
				if (item == null) {
					// Check if it is a tool:
					JsonObject tool = stackJson.getObject("tool");
					if (tool != null) {
						item = new Tool(tool, registries);
					} else {
						// item not existant in this version of the game. Can't do much so ignore it.
						items[i] = new ItemStack();
						continue;
					}
				}
				ItemStack stack = new ItemStack(item);
				stack.add(stackJson.getInt("amount", 1));
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
