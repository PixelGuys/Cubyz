package cubyz.gui;

import cubyz.client.Cubyz;
import cubyz.client.rendering.Window;
import cubyz.gui.components.InventorySlot;
import cubyz.world.items.Inventory;

/**
 * Basic overlay while in-game.<br>
 * Contains hotbar, hunger bars, and crosshair.
 */

public class GameOverlay extends MenuGUI {

	int crosshair;
	int selection;
	int[] healthBar;
	int[] hungerBar;
	
	long lastPlayerHurtMs; // stored here and not in Player for easier multiplayer integration
	float lastPlayerHealth;

	private InventorySlot inv [] = new InventorySlot[8];
	
	@Override
	public void init(long nvg) {
		crosshair = NGraphics.loadImage("assets/cubyz/textures/crosshair.png");
		selection = NGraphics.loadImage("assets/cubyz/guis/inventory/selected_slot.png");
		healthBar = new int[8];
		healthBar[0] = NGraphics.loadImage("assets/cubyz/textures/health_bar_beg_empty.png");
		healthBar[1] = NGraphics.loadImage("assets/cubyz/textures/health_bar_beg_full.png");
		healthBar[2] = NGraphics.loadImage("assets/cubyz/textures/health_bar_end_empty.png");
		healthBar[3] = NGraphics.loadImage("assets/cubyz/textures/health_bar_end_full.png");
		healthBar[4] = NGraphics.loadImage("assets/cubyz/textures/health_bar_mid_empty.png");
		healthBar[5] = NGraphics.loadImage("assets/cubyz/textures/health_bar_mid_half.png");
		healthBar[6] = NGraphics.loadImage("assets/cubyz/textures/health_bar_mid_full.png");
		healthBar[7] = NGraphics.loadImage("assets/cubyz/textures/health_bar_icon.png");
		hungerBar = new int[8];
		hungerBar[0] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_beg_empty.png");
		hungerBar[1] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_beg_full.png");
		hungerBar[2] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_end_empty.png");
		hungerBar[3] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_end_full.png");
		hungerBar[4] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_mid_empty.png");
		hungerBar[5] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_mid_half.png");
		hungerBar[6] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_mid_full.png");
		hungerBar[7] = NGraphics.loadImage("assets/cubyz/textures/hunger_bar_icon.png");
		Inventory inventory = Cubyz.player.getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64 - 256, 64, Component.ALIGN_BOTTOM);
		}
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(crosshair, win.getWidth()/2 - 16, win.getHeight()/2 - 16, 32, 32);
		NGraphics.setColor(0, 0, 0);
		if(!(Cubyz.gameUI.getMenuGUI() instanceof GeneralInventory)) {
			NGraphics.drawImage(selection, win.getWidth()/2 - 254 + Cubyz.inventorySelection*64, win.getHeight() - 62, 60, 60);
			for(int i = 0; i < 8; i++) {
				inv[i].reference = Cubyz.player.getInventory().getStack(i); // without it, if moved in inventory, stack won't refresh
				inv[i].render(nvg, win);
			}
		}
		// Draw the health bar:
		float maxHealth = Cubyz.player.maxHealth;
		float health = Cubyz.player.health;
		if(lastPlayerHealth != health) {
			if(lastPlayerHealth > health) {
				lastPlayerHurtMs = System.currentTimeMillis();
			}
			lastPlayerHealth = health;
		}
		if (System.currentTimeMillis() < lastPlayerHurtMs+510) {
			NGraphics.setColor(255, 50, 50, (int) (255-(System.currentTimeMillis()-lastPlayerHurtMs))/2);
			NGraphics.fillRect(0, 0, win.getWidth(), win.getHeight());
		}
		String s = Math.round(health*10)/10.0f + "/" + Math.round(maxHealth) + " HP";
		float width = NGraphics.getTextWidth(s);
		NGraphics.drawImage(healthBar[7], (int)(win.getWidth() - maxHealth*12 - 40 - width), 6, 24, 24);
		NGraphics.drawText(win.getWidth() - maxHealth*12 - 10 - width, 9, s);
		for(int i = 0; i < maxHealth; i += 2) {
			boolean half = i + 1 == health;
			boolean empty = i >= health;
			
			int idx = 0;
			if(i == 0) { // beggining
				idx = empty ? 0 : 1;
			} else if(i == maxHealth-2) { // end
				idx = i + 1 >= health ? 2 : 3;
			} else {
				idx = empty ? 4 : (half ? 5 : 6); // if empty = 4, half = 5, full = 6
			}
			NGraphics.drawImage(healthBar[idx], (int)(i*12 + win.getWidth() - maxHealth*12 - 4), 6, 24, 24);
		}
		// Draw the hunger bar:
		float maxHunger = Cubyz.player.maxHunger;
		float hunger = Cubyz.player.hunger;
		s = Math.round(hunger*10)/10.0f + "/" + Math.round(maxHunger) + " HP";
		width = NGraphics.getTextWidth(s);
		NGraphics.drawImage(hungerBar[7], (int)(win.getWidth() - maxHunger*12 - 40 - width), 36, 24, 24);
		NGraphics.drawText(win.getWidth()-maxHunger*12 - 10 - width, 39, s);
		for(int i = 0; i < maxHunger; i += 2) {
			boolean half = i + 1 == hunger;
			boolean empty = i >= hunger;
			
			int idx = 0;
			if(i == 0) { // beggining
				idx = empty ? 0 : 1;
			} else if(i == maxHunger-2) { // end
				idx = i + 1 >= hunger ? 2 : 3;
			} else {
				idx = empty ? 4 : (half ? 5 : 6); // if empty = 4, half = 5, full = 6
			}
			NGraphics.drawImage(hungerBar[idx], (int)(i*12 + win.getWidth() - maxHunger*12 - 4), 36, 24, 24);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
