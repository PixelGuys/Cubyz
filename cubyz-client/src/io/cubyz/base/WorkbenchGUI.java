package io.cubyz.base;

import org.jungle.MouseInput;
import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;
import io.cubyz.items.tools.Pickaxe;
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
		for(int i = 0; i < inv.length; i++) {
			// TODO: Don't really swap the references. Just swap the contents of the references. That will make everything a lot easier.
			if(inv[i].grabWithMouse(mouse, carried, win.getWidth()/2, win.getHeight())) {
				if (i == 35 && inv[35].reference.getItem() != null) {
					// Remove items in the crafting grid.
					for(int j = 32; j <= 34; j++) {
						inv[j].reference.clear(); // TODO: Perform a proper material management.
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
		inv = new InventorySlot[36];
		Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64-256, 64);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+8] = new InventorySlot(inventory.getStack(i+8), i*64-256, 192);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+16] = new InventorySlot(inventory.getStack(i+16), i*64-256, 256);
		}
		for(int i = 0; i < 8; i++) {
			inv[i+24] = new InventorySlot(inventory.getStack(i+24), i*64-256, 320);
		}
		inv[32] = new InventorySlot(in.getStack(0), -96, 552); // head
		inv[33] = new InventorySlot(in.getStack(1), -128, 480); // binding
		inv[34] = new InventorySlot(in.getStack(2), -96, 408); // handle
		inv[35] = new InventorySlot(in.getStack(3), 32, 480, true); // new tool
		return this;
	}
	
	private void checkCrafting() {
		inv[35].reference.clear();
		Item item = Pickaxe.canCraft(inv[32].reference, inv[33].reference, inv[34].reference); // TODO: Make more then just pickaxes!
		if(item != null) {
			inv[35].reference.setItem(item);
			inv[35].reference.add(1);
		}
	}

}
