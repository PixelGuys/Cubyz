package io.cubyz.ui.mods;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.ui.GeneralInventory;
import io.cubyz.ui.components.InventorySlot;
import io.jungle.MouseInput;
import io.jungle.Window;

/**
 * GUI of the normal inventory(when pressing 'I')<br>
 * TODO: add possibility to capture and release stacks with the mouse.
 */

public class InventoryGUI extends GeneralInventory {
	
	public InventoryGUI() {
		super(new Resource("cubyz:inventory"));
	}
	
	private void checkCrafting() {
		// Clear everything in case there is no recipe available.
		inv[36].reference.clear();
		// Find out how many items are there in the grid and put them in an array:
		int num = 0;
		Item[] ar = new Item[4];
		for(int i = 0; i < 4; i++) {
			ar[i] = inv[32 + i].reference.getItem();
			if(ar[i] != null)
				num++;
		}
		// Get the recipes for the given number of items(TODO!):
		Object[] recipes = CubyzRegistries.RECIPE_REGISTRY.registered();
		// Find a fitting recipe:
		Item item = null;
		for(int i = 0; i < recipes.length; i++) {
			Recipe rec = (Recipe) recipes[i];
			if(rec.getNum() != num)
				continue;
			item = rec.canCraft(ar, 2);
			if(item != null) {
				
				inv[36].reference.setItem(item);
				inv[36].reference.add(rec.getNumRet());
				return;
			}
		}
	}

	@Override
	protected void positionSlots() {
		if(inv == null) {
			inv = new InventorySlot[37];
			Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
			for(int i = 0; i < 8; i++) {
				inv[i] = new InventorySlot(inventory.getStack(i), i*64 - 256, 64);
			}
			for(int i = 0; i < 8; i++) {
				inv[i + 8] = new InventorySlot(inventory.getStack(i + 8), i*64 - 256, 256);
			}
			for(int i = 0; i < 8; i++) {
				inv[i + 16] = new InventorySlot(inventory.getStack(i + 16), i*64 - 256, 320);
			}
			for(int i = 0; i < 8; i++) {
				inv[i + 24] = new InventorySlot(inventory.getStack(i + 24), i*64 - 256, 384);
			}
			inv[32] = new InventorySlot(inventory.getStack(32), 0, 544);
			inv[33] = new InventorySlot(inventory.getStack(33), 64, 544);
			inv[34] = new InventorySlot(inventory.getStack(34), 0, 480);
			inv[35] = new InventorySlot(inventory.getStack(35), 64, 480);
			inv[36] = new InventorySlot(inventory.getStack(36), 192, 512, true);
		}
		width = 576;
		height = 576;
	}

	@Override
	protected void mouseAction(MouseInput mouse, Window win) {
		boolean notNull = inv[36].reference.getItem() != null;
		for(int i = 0; i < inv.length; i++) {
			if(inv[i].grabWithMouse(mouse, carried, win.getWidth()/2, win.getHeight())) {
				if (i == 36 && notNull) {
					// Remove items in the crafting grid.
					for(int j = 32; j <= 35; j++) {
						inv[j].reference.add(-1);
					}
				}
			}
			if(i >= 32) {
				checkCrafting();
			}
		}
	}
}