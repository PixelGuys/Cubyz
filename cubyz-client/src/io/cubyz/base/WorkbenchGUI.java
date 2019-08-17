package io.cubyz.base;

import org.jungle.MouseInput;
import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.ItemStack;
import io.cubyz.ui.GeneralInventory;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.InventorySlot;

// TODO
public class WorkbenchGUI extends GeneralInventory {

	@Override
	protected void positionSlots() {
		width = 576;
		height = 576;
	}

	@Override
	protected void mouseAction(MouseInput mouse, Window win) {
		ItemStack newlyCarried;
		for(int i = 0; i < inv.length; i++) {
			// TODO: Don't really swap the references. Just swap the contents of the references. That will make everything a lot easier.
			newlyCarried = inv[i].grabWithMouse(mouse, carried, win.getWidth()/2, win.getHeight());
			if(newlyCarried != null) {
				Cubyz.world.getLocalPlayer().getInventory().setSlot(carried, i);
				carried = newlyCarried;
				if (i == 37) {
					// Remove items in the crafting grid.
					for(int j = 32; j <= 36; j++) {
						inv[j].reference.add(-1);
					}
				}
			}
			if(i >= 32) {
				checkCrafting();
			}
		}
	}
	
	@Override
	public MenuGUI setInventory(Inventory in) {
		inv = new InventorySlot[38];
		Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64-256, 64);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+8] = new InventorySlot(inventory.getStack(i+8), i*64-256, 256);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+16] = new InventorySlot(inventory.getStack(i+16), i*64-256, 320);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+24] = new InventorySlot(inventory.getStack(i+24), i*64-256, 384);
		}
		inv[32] = new InventorySlot(in.getStack(0), 0, 544);
		inv[33] = new InventorySlot(in.getStack(1), 64, 544);
		inv[34] = new InventorySlot(in.getStack(2), 0, 480);
		inv[35] = new InventorySlot(in.getStack(3), 64, 480);
		inv[36] = new InventorySlot(in.getStack(4), 192, 512);
		inv[37] = new InventorySlot(in.getStack(5), 192, 512, true);
		return this;
	}
	
	private void checkCrafting() {
		// TODO!
	}

}
