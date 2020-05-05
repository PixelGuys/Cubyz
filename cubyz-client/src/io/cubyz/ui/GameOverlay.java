package io.cubyz.ui;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.ui.components.InventorySlot;
import io.jungle.Window;

public class GameOverlay extends MenuGUI {

	int crosshair;
	int selection;
	int heart, halfHeart;

	private InventorySlot inv [] = new InventorySlot[8];
	
	@Override
	public void init(long nvg) {
		crosshair = NGraphics.loadImage("assets/cubyz/textures/crosshair.png");
		selection = NGraphics.loadImage("assets/cubyz/guis/inventory/selected_slot.png");
		heart = NGraphics.loadImage("assets/cubyz/textures/heart.png");
		halfHeart = NGraphics.loadImage("assets/cubyz/textures/half_heart.png");
		Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64-256, 64);
		}
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(crosshair, win.getWidth() / 2 - 16, win.getHeight() / 2 - 16, 32, 32);
		NGraphics.setColor(0, 0, 0);
		if(!(Cubyz.gameUI.getMenuGUI() instanceof GeneralInventory)) {
			NGraphics.drawImage(selection, win.getWidth()/2 - 254 + Cubyz.inventorySelection*64, win.getHeight() - 62, 60, 60);
			for(int i = 0; i < 8; i++) {
				inv[i].reference = Cubyz.world.getLocalPlayer().getInventory().getStack(i); // without it, if moved in inventory, stack won't refresh
				inv[i].render(nvg, win);
			}
		}
		// Draw the health bar:#
		int health = Cubyz.world.getLocalPlayer().health;
		for(int i = 0; i < health; i += 2) {
			if(i+1 == health) {	// Draw half a heart.
				NGraphics.drawImage(halfHeart, win.getWidth()/2 - 254 + i*8, win.getHeight() - 88, 16, 16);
			} else { // Draw a full heart.
				NGraphics.drawImage(heart, win.getWidth()/2 - 254 + i*8, win.getHeight() - 88, 16, 16);
			}
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
