package io.cubyz.ui;

import org.jungle.Window;
import org.jungle.hud.Font;

import io.cubyz.client.Cubyz;
import io.cubyz.items.Inventory;
import io.cubyz.items.Item;
import io.cubyz.ui.components.Label;

public class GameOverlay extends MenuGUI {

	int crosshair;
	int hotBar;
	int selection;

	private Label inv [] = new Label[8];
	
	@Override
	public void init(long nvg) {
		crosshair = NGraphics.loadImage("assets/cubyz/textures/crosshair.png");
		hotBar = NGraphics.loadImage("assets/cubyz/guis/inventory/inventory_bar.png");
		selection = NGraphics.loadImage("assets/cubyz/guis/inventory/selected_slot.png");
		for(int i = 0; i < 8; i++) {
			inv[i] = new Label();
			inv[i].setFont(new Font("OpenSans Bold", 16.f));
		}
	}

	@Override
	public void render(long nvg, Window win) {
		NGraphics.drawImage(crosshair, win.getWidth() / 2 - 16, win.getHeight() / 2 - 16, 32, 32);
		NGraphics.drawImage(hotBar, win.getWidth()/2 - 255, win.getHeight() - 64, 510, 64);
		NGraphics.setColor(0, 0, 0);
		Inventory inventory = Cubyz.world.getLocalPlayer().getInventory();
		for(int i = 0; i < 8; i++) {
			Item item = inventory.getItem(i);
			if(item != null) {
				if(item.getImage() == -1) {
					item.setImage(NGraphics.loadImage(item.getTexture()));
				}
				NGraphics.drawImage(item.getImage(), win.getWidth()/2 - 255 + i*510/8+2, win.getHeight() - 62, 510/8-4, 60);
				if(i == Cubyz.inventorySelection) {
					NGraphics.drawImage(selection, win.getWidth()/2 - 255 + i*510/8+2, win.getHeight() - 62, 510/8-4, 60);
				}
				inv[i].setText("" + inventory.getAmount(i));
				inv[i].setPosition(win.getWidth()/2 - 255 + (i+1)*510/8 - 16, win.getHeight()-16);
				inv[i].render(nvg, win);
			}
		}
	}

	@Override
	public boolean isFullscreen() {
		return false;
	}

}
