package cubyz.gui;

import cubyz.client.Cubyz;
import cubyz.gui.components.InventorySlot;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.world.items.Inventory;

/**
 * Basic overlay while in-game.<br>
 * Contains hotbar, hunger bars, and crosshair.
 */

public class GameOverlay extends MenuGUI {

	Texture crosshair;
	Texture selection;
	Texture[] healthBar;
	Texture[] hungerBar;
	
	long lastPlayerHurtMs; // stored here and not in Player for easier multiplayer integration
	float lastPlayerHealth;

	private InventorySlot inv [] = new InventorySlot[8];
	
	@Override
	public void init(long nvg) {
		crosshair = Texture.loadFromFile("assets/cubyz/textures/crosshair.png");
		selection = Texture.loadFromFile("assets/cubyz/guis/inventory/selected_slot.png");
		healthBar = new Texture[8];
		healthBar[0] = Texture.loadFromFile("assets/cubyz/textures/health_bar_beg_empty.png");
		healthBar[1] = Texture.loadFromFile("assets/cubyz/textures/health_bar_beg_full.png");
		healthBar[2] = Texture.loadFromFile("assets/cubyz/textures/health_bar_end_empty.png");
		healthBar[3] = Texture.loadFromFile("assets/cubyz/textures/health_bar_end_full.png");
		healthBar[4] = Texture.loadFromFile("assets/cubyz/textures/health_bar_mid_empty.png");
		healthBar[5] = Texture.loadFromFile("assets/cubyz/textures/health_bar_mid_half.png");
		healthBar[6] = Texture.loadFromFile("assets/cubyz/textures/health_bar_mid_full.png");
		healthBar[7] = Texture.loadFromFile("assets/cubyz/textures/health_bar_icon.png");
		hungerBar = new Texture[8];
		hungerBar[0] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_beg_empty.png");
		hungerBar[1] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_beg_full.png");
		hungerBar[2] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_end_empty.png");
		hungerBar[3] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_end_full.png");
		hungerBar[4] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_mid_empty.png");
		hungerBar[5] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_mid_half.png");
		hungerBar[6] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_mid_full.png");
		hungerBar[7] = Texture.loadFromFile("assets/cubyz/textures/hunger_bar_icon.png");
		Inventory inventory = Cubyz.player.getInventory();
		for(int i = 0; i < 8; i++) {
			inv[i] = new InventorySlot(inventory.getStack(i), i*64 - 256, 64, Component.ALIGN_BOTTOM);
		}
	}

	@Override
	public void render(long nvg) {
		Graphics.drawImage(crosshair, Window.getWidth()/2 - 16, Window.getHeight()/2 - 16, 32, 32);
		NGraphics.setColor(0, 0, 0);
		if(!(Cubyz.gameUI.getMenuGUI() instanceof GeneralInventory)) {
			Graphics.drawImage(selection, Window.getWidth()/2 - 254 + Cubyz.inventorySelection*64, Window.getHeight() - 62, 60, 60);
			for(int i = 0; i < 8; i++) {
				inv[i].reference = Cubyz.player.getInventory().getStack(i); // without it, if moved in inventory, stack won't refresh
				inv[i].render(nvg);
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
			Graphics.setColor(0xFF3232, (int) (255-(System.currentTimeMillis()-lastPlayerHurtMs))/2);
			Graphics.fillRect(0, 0, Window.getWidth(), Window.getHeight());
		}
		String s = Math.round(health*10)/10.0f + "/" + Math.round(maxHealth) + " HP";
		float width = NGraphics.getTextWidth(s);
		Graphics.drawImage(healthBar[7], (int)(Window.getWidth() - maxHealth*12 - 40 - width), 6, 24, 24);
		NGraphics.drawText(Window.getWidth() - maxHealth*12 - 10 - width, 9, s);
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
			Graphics.drawImage(healthBar[idx], (int)(i*12 + Window.getWidth() - maxHealth*12 - 4), 6, 24, 24);
		}
		// Draw the hunger bar:
		float maxHunger = Cubyz.player.maxHunger;
		float hunger = Cubyz.player.hunger;
		s = Math.round(hunger*10)/10.0f + "/" + Math.round(maxHunger) + " HP";
		width = NGraphics.getTextWidth(s);
		Graphics.drawImage(hungerBar[7], (int)(Window.getWidth() - maxHunger*12 - 40 - width), 36, 24, 24);
		NGraphics.drawText(Window.getWidth()-maxHunger*12 - 10 - width, 39, s);
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
			Graphics.drawImage(hungerBar[idx], (int)(i*12 + Window.getWidth() - maxHunger*12 - 4), 36, 24, 24);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
