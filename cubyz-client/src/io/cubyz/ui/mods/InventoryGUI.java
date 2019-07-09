package io.cubyz.ui.mods;

import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.NGraphics;
import io.cubyz.ui.components.InventorySlot;

// TODO: add possibility to capture and release stacks with the mouse.

public class InventoryGUI extends MenuGUI {

	private InventorySlot inv [] = null;

	public void close() {
		Cubyz.mouse.setGrabbed(true);
		 // TODO: take care about what happens when the window is closed , but the mouse captured a stack.
	}

	@Override
	public void init(long nvg) {
		Cubyz.mouse.setGrabbed(false);
		if(inv == null) {
			inv = new InventorySlot[32];
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
		}
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.setColor(0, 0, 0);
		for(int i = 0; i < inv.length; i++) {
			inv[i].render(nvg, win);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
